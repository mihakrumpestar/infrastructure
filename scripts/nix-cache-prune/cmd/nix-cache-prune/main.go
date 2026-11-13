// Command nix-cache-prune deletes old paths from the MEGA S4 Nix binary cache.
//
// The cache is append-only: nothing removes old paths. This tool deletes
// narinfos older than --retention-days, then deletes NAR objects that are
// older than --nar-grace-days and no longer referenced by a surviving
// narinfo.
//
// Only narinfos newer than the retention cutoff are downloaded. Expired
// narinfos are deleted without being parsed, which keeps a weekly run cheap.
//
// It is a dry run unless --delete is given.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/aws/aws-sdk-go-v2/config"

	"nix-cache-prune/internal/prune"
)

type options struct {
	bucket        string
	endpoint      string
	region        string
	retentionDays int
	narGraceDays  int
	concurrency   int
	maxDelete     int
	delete        bool
	force         bool
	verbose       bool
}

type logger struct {
	verbose bool
}

func (l logger) Infof(format string, args ...any) {
	if l.verbose {
		fmt.Fprintf(os.Stderr, "INFO "+format+"\n", args...)
	}
}

func (l logger) Warnf(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "WARNING "+format+"\n", args...)
}

func (l logger) Errorf(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "ERROR "+format+"\n", args...)
}

func parseOptions(args []string) (options, error) {
	var opts options

	fs := flag.NewFlagSet("nix-cache-prune", flag.ContinueOnError)
	fs.StringVar(&opts.bucket, "bucket", os.Getenv("NIX_CACHE_BUCKET"), "cache bucket (default: $NIX_CACHE_BUCKET)")
	fs.StringVar(&opts.endpoint, "endpoint", os.Getenv("NIX_CACHE_ENDPOINT"), "S3 endpoint (default: $NIX_CACHE_ENDPOINT)")
	fs.StringVar(&opts.region, "region", os.Getenv("NIX_CACHE_REGION"), "S3 region (default: $NIX_CACHE_REGION)")
	fs.IntVar(&opts.retentionDays, "retention-days", 90, "delete narinfos older than this many days")
	fs.IntVar(&opts.narGraceDays, "nar-grace-days", 7, "keep unreferenced NARs newer than this many days")
	fs.IntVar(&opts.concurrency, "concurrency", 16, "parallel narinfo downloads")
	fs.IntVar(&opts.maxDelete, "max-delete", 10_000, "abort if more than this many objects would be deleted; 0 disables the cap")
	fs.BoolVar(&opts.delete, "delete", false, "actually delete objects; without this the run is a dry run")
	fs.BoolVar(&opts.force, "force", false, "allow deleting more than half of the narinfos in one run")
	fs.BoolVar(&opts.verbose, "verbose", false, "log progress to stderr")

	if err := fs.Parse(args); err != nil {
		return opts, err
	}

	if fs.NArg() > 0 {
		return opts, fmt.Errorf("unexpected arguments: %s", strings.Join(fs.Args(), " "))
	}

	var missing []string
	for _, setting := range []struct {
		flag  string
		value string
	}{
		{"bucket", opts.bucket},
		{"endpoint", opts.endpoint},
		{"region", opts.region},
	} {
		if setting.value == "" {
			missing = append(missing, "--"+setting.flag)
		}
	}
	if len(missing) > 0 {
		return opts, fmt.Errorf(
			"missing %s (or the matching NIX_CACHE_* environment variables)",
			strings.Join(missing, ", "),
		)
	}

	if os.Getenv("AWS_ACCESS_KEY_ID") == "" || os.Getenv("AWS_SECRET_ACCESS_KEY") == "" {
		return opts, errors.New("AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY must be set")
	}

	if !strings.Contains(opts.endpoint, "://") {
		opts.endpoint = "https://" + opts.endpoint
	}

	if opts.retentionDays < 0 || opts.narGraceDays < 0 {
		return opts, errors.New("retention and grace periods must not be negative")
	}

	if opts.concurrency < 1 {
		return opts, errors.New("--concurrency must be at least 1")
	}

	return opts, nil
}

func main() {
	opts, err := parseOptions(os.Args[1:])
	if err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return
		}
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(2)
	}

	if err := run(opts); err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}

func run(opts options) error {
	log := logger{verbose: opts.verbose}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	cfg, err := config.LoadDefaultConfig(ctx, config.WithRegion(opts.region))
	if err != nil {
		return fmt.Errorf("loading AWS configuration: %w", err)
	}

	store := prune.NewStore(cfg, opts.bucket, opts.endpoint)

	log.Infof("listing cache bucket %s", opts.bucket)
	objects, err := store.List(ctx)
	if err != nil {
		return err
	}
	log.Infof("found %d objects", len(objects))

	totalNarinfos, totalNars := countObjects(objects)

	if totalNarinfos == 0 && totalNars > 0 {
		return errors.New("found NAR objects but no narinfos; refusing to prune (check the bucket and credentials)")
	}

	now := time.Now().UTC()
	retentionCutoff := now.AddDate(0, 0, -opts.retentionDays)

	var survivingKeys []string
	for _, obj := range objects {
		if prune.IsNarinfo(obj.Key) && !obj.LastModified.Before(retentionCutoff) {
			survivingKeys = append(survivingKeys, obj.Key)
		}
	}

	surviving := fetchNarinfos(ctx, store, survivingKeys, opts.concurrency)

	selection := prune.Select(objects, surviving, now, opts.retentionDays, opts.narGraceDays)

	log.Infof(
		"narinfos: %d total, %d surviving, %d expired",
		totalNarinfos, selection.SurvivingNarinfos, len(selection.ExpiredNarinfos),
	)

	if selection.ParseErrors > 0 {
		log.Warnf(
			"%d surviving narinfo(s) could not be read or parsed; keeping them and skipping all NAR deletion",
			selection.ParseErrors,
		)
	}

	total := len(selection.ExpiredNarinfos) + len(selection.OrphanNars)
	if opts.maxDelete > 0 && total > opts.maxDelete {
		return fmt.Errorf(
			"refusing to delete %d objects with --max-delete %d; run with a higher cap or --max-delete 0",
			total, opts.maxDelete,
		)
	}

	if !opts.force && totalNarinfos >= 20 && len(selection.ExpiredNarinfos) > totalNarinfos/2 {
		return fmt.Errorf(
			"refusing to delete %d of %d narinfos; check the retention period, then rerun with --force",
			len(selection.ExpiredNarinfos), totalNarinfos,
		)
	}

	var deleteErrors []prune.DeleteError

	if opts.delete {
		log.Infof("deleting %d narinfos", len(selection.ExpiredNarinfos))
		narinfoErrors, err := store.Delete(ctx, selection.ExpiredNarinfos)
		deleteErrors = append(deleteErrors, narinfoErrors...)
		if err != nil {
			return err
		}

		log.Infof("deleting %d orphaned NARs", len(selection.OrphanNars))
		narErrors, err := store.Delete(ctx, selection.OrphanNars)
		deleteErrors = append(deleteErrors, narErrors...)
		if err != nil {
			return err
		}
	}

	out, err := json.MarshalIndent(newSummary(opts, len(objects), totalNarinfos, totalNars, selection, len(deleteErrors)), "", "  ")
	if err != nil {
		return fmt.Errorf("encoding summary: %w", err)
	}
	fmt.Println(string(out))

	if len(deleteErrors) > 0 {
		log.Errorf("%d delete error(s)", len(deleteErrors))
		for _, failure := range deleteErrors {
			log.Errorf("%s: %s", failure.Key, failure.Message)
		}
		return errors.New("some objects could not be deleted")
	}

	return nil
}

type summary struct {
	DryRun  bool `json:"dry_run"`
	Objects int  `json:"objects"`
	Narinfo struct {
		Total     int `json:"total"`
		Surviving int `json:"surviving"`
		Expired   int `json:"expired"`
		Errors    int `json:"errors"`
	} `json:"narinfos"`
	Nars struct {
		Total    int `json:"total"`
		Orphaned int `json:"orphaned"`
	} `json:"nars"`
	Deleted struct {
		Narinfos int `json:"narinfos"`
		Nars     int `json:"nars"`
	} `json:"deleted"`
	DeleteErrors int `json:"delete_errors"`
}

func newSummary(
	opts options,
	objectCount int,
	totalNarinfos int,
	totalNars int,
	selection prune.Selection,
	deleteErrors int,
) summary {
	s := summary{DryRun: !opts.delete, Objects: objectCount, DeleteErrors: deleteErrors}
	s.Narinfo.Total = totalNarinfos
	s.Narinfo.Surviving = selection.SurvivingNarinfos
	s.Narinfo.Expired = len(selection.ExpiredNarinfos)
	s.Narinfo.Errors = selection.ParseErrors
	s.Nars.Total = totalNars
	s.Nars.Orphaned = len(selection.OrphanNars)
	if opts.delete {
		s.Deleted.Narinfos = len(selection.ExpiredNarinfos)
		s.Deleted.Nars = len(selection.OrphanNars)
	}
	return s
}

func countObjects(objects []prune.Object) (narinfos int, nars int) {
	for _, obj := range objects {
		switch {
		case prune.IsNarinfo(obj.Key):
			narinfos++
		case prune.IsNar(obj.Key):
			nars++
		}
	}
	return narinfos, nars
}

// fetchNarinfos downloads the narinfos with a fixed worker pool. Each worker
// writes its own slice slot, so no locking is needed.
func fetchNarinfos(ctx context.Context, store *prune.Store, keys []string, concurrency int) map[string]prune.Narinfo {
	if len(keys) == 0 {
		return nil
	}

	infos := make([]prune.Narinfo, len(keys))
	jobs := make(chan int)

	var wg sync.WaitGroup
	for range min(concurrency, len(keys)) {
		wg.Add(1)
		go func() {
			defer wg.Done()

			for i := range jobs {
				infos[i] = store.Narinfo(ctx, keys[i])
			}
		}()
	}

	for i := range keys {
		jobs <- i
	}
	close(jobs)

	wg.Wait()

	results := make(map[string]prune.Narinfo, len(keys))
	for _, info := range infos {
		results[info.Key] = info
	}

	return results
}
