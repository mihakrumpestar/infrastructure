package prune

import (
	"regexp"
	"sort"
	"strings"
	"time"
)

const narPrefix = "nar/"

// narinfoName matches a narinfo object key: 32 base32 characters and ".narinfo".
var narinfoName = regexp.MustCompile(`^[0-9a-z]{32}\.narinfo$`)

func IsNarinfo(key string) bool { return narinfoName.MatchString(key) }

func IsNar(key string) bool { return strings.HasPrefix(key, narPrefix) }

// Object is a bucket object with the metadata the selection needs.
type Object struct {
	Key          string
	LastModified time.Time
}

// Narinfo is the parsed state of one narinfo. Error is set when the object
// could not be read or has no usable URL.
type Narinfo struct {
	Key   string
	URL   string
	Error string
}

// Selection is the set of keys a run may delete.
type Selection struct {
	ExpiredNarinfos   []string
	OrphanNars        []string
	ParseErrors       int
	SurvivingNarinfos int
}

// ParseNarinfoURL returns the NAR key from a narinfo body, or "" when the
// narinfo has no usable relative URL.
func ParseNarinfoURL(body string) string {
	for _, line := range strings.Split(body, "\n") {
		rest, ok := strings.CutPrefix(line, "URL:")
		if !ok {
			continue
		}
		url := strings.TrimSpace(rest)
		if strings.HasPrefix(url, narPrefix) {
			return url
		}
		return ""
	}
	return ""
}

// Select chooses expired narinfos and unreferenced NARs.
//
// A surviving narinfo that could not be read or parsed makes NAR deletion
// unsafe, because its NAR key is unknown. Expired narinfos are not parsed:
// they are deleted either way.
func Select(objects []Object, surviving map[string]Narinfo, now time.Time, retentionDays, narGraceDays int) Selection {
	retentionCutoff := now.AddDate(0, 0, -retentionDays)
	narCutoff := now.AddDate(0, 0, -narGraceDays)

	expired := make([]string, 0, len(objects))
	for _, obj := range objects {
		if IsNarinfo(obj.Key) && obj.LastModified.Before(retentionCutoff) {
			expired = append(expired, obj.Key)
		}
	}

	retainedURLs := make(map[string]struct{}, len(surviving))
	parseErrors := 0
	for _, info := range surviving {
		if info.Error != "" || info.URL == "" {
			parseErrors++
			continue
		}
		retainedURLs[info.URL] = struct{}{}
	}

	var orphans []string
	if parseErrors == 0 {
		for _, obj := range objects {
			if !IsNar(obj.Key) || !obj.LastModified.Before(narCutoff) {
				continue
			}
			if _, ok := retainedURLs[obj.Key]; !ok {
				orphans = append(orphans, obj.Key)
			}
		}
	}

	sort.Strings(expired)
	sort.Strings(orphans)

	return Selection{
		ExpiredNarinfos:   expired,
		OrphanNars:        orphans,
		ParseErrors:       parseErrors,
		SurvivingNarinfos: len(surviving),
	}
}
