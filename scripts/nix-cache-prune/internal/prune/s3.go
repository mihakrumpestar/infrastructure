package prune

import (
	"context"
	"fmt"
	"io"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
)

// Store reads and deletes objects in one bucket.
type Store struct {
	client *s3.Client
	bucket string
}

// NewStore builds an S3 client for a compatible endpoint. MEGA S4 needs
// path-style addressing; the SDK signs with SigV4.
func NewStore(cfg aws.Config, bucket, endpoint string) *Store {
	return &Store{
		client: s3.NewFromConfig(cfg, func(o *s3.Options) {
			o.UsePathStyle = true
			o.BaseEndpoint = aws.String(endpoint)
			// S3-compatible services often omit the checksum trailer the SDK
			// expects, and the notice is noise on stdout-level logs.
			o.DisableLogOutputChecksumValidationSkipped = true
		}),
		bucket: bucket,
	}
}

// List returns every object in the bucket.
func (s *Store) List(ctx context.Context) ([]Object, error) {
	paginator := s3.NewListObjectsV2Paginator(s.client, &s3.ListObjectsV2Input{
		Bucket: aws.String(s.bucket),
	})

	var objects []Object
	for paginator.HasMorePages() {
		page, err := paginator.NextPage(ctx)
		if err != nil {
			return nil, fmt.Errorf("listing objects: %w", err)
		}
		for _, item := range page.Contents {
			objects = append(objects, Object{
				Key:          aws.ToString(item.Key),
				LastModified: aws.ToTime(item.LastModified),
			})
		}
	}

	return objects, nil
}

// Narinfo downloads and parses one narinfo. A failure is returned on the
// value, not as an error, because one unreadable narinfo must block NAR
// deletion without aborting the run.
func (s *Store) Narinfo(ctx context.Context, key string) Narinfo {
	out, err := s.client.GetObject(ctx, &s3.GetObjectInput{
		Bucket: aws.String(s.bucket),
		Key:    aws.String(key),
	})
	if err != nil {
		return Narinfo{Key: key, Error: err.Error()}
	}
	defer out.Body.Close()

	body, err := io.ReadAll(out.Body)
	if err != nil {
		return Narinfo{Key: key, Error: err.Error()}
	}

	url := ParseNarinfoURL(string(body))
	if url == "" {
		return Narinfo{Key: key, Error: "missing or invalid URL field"}
	}

	return Narinfo{Key: key, URL: url}
}

// DeleteError is one object S3 refused to delete.
type DeleteError struct {
	Key     string
	Message string
}

// Delete removes keys in batches of 1000, the S3 limit. A key that is already
// gone is not an error: two narinfos can share a NAR, and an interrupted run
// leaves keys that the next run deletes again.
func (s *Store) Delete(ctx context.Context, keys []string) ([]DeleteError, error) {
	var failures []DeleteError

	for start := 0; start < len(keys); start += 1000 {
		end := min(start+1000, len(keys))

		objects := make([]types.ObjectIdentifier, 0, end-start)
		for _, key := range keys[start:end] {
			objects = append(objects, types.ObjectIdentifier{Key: aws.String(key)})
		}

		out, err := s.client.DeleteObjects(ctx, &s3.DeleteObjectsInput{
			Bucket: aws.String(s.bucket),
			Delete: &types.Delete{
				Objects: objects,
				Quiet:   aws.Bool(true),
			},
		})
		if err != nil {
			return failures, fmt.Errorf("deleting objects: %w", err)
		}

		for _, item := range out.Errors {
			code := aws.ToString(item.Code)
			if code == "NoSuchKey" || code == "NotFound" {
				continue
			}
			failures = append(failures, DeleteError{
				Key:     aws.ToString(item.Key),
				Message: fmt.Sprintf("%s: %s", code, aws.ToString(item.Message)),
			})
		}
	}

	return failures, nil
}
