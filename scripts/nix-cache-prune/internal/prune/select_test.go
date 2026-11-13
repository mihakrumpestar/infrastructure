package prune

import (
	"testing"
	"time"
)

func at(daysAgo int, now time.Time) time.Time {
	return now.AddDate(0, 0, -daysAgo)
}

func TestParseNarinfoURL(t *testing.T) {
	cases := map[string]struct {
		body string
		want string
	}{
		"relative nar url": {
			body: "StorePath: /nix/store/abc-x\nURL: nar/1fnb.nar.xz\nCompression: xz\n",
			want: "nar/1fnb.nar.xz",
		},
		"missing url": {
			body: "StorePath: /nix/store/abc-x\nCompression: xz\n",
			want: "",
		},
		"absolute url": {
			body: "URL: https://example.com/nar/1fnb.nar.xz\n",
			want: "",
		},
		"empty body": {
			body: "",
			want: "",
		},
	}

	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			if got := ParseNarinfoURL(tc.body); got != tc.want {
				t.Fatalf("ParseNarinfoURL() = %q, want %q", got, tc.want)
			}
		})
	}
}

func TestSelect(t *testing.T) {
	now := time.Date(2026, 11, 13, 12, 0, 0, 0, time.UTC)

	const (
		fresh       = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.narinfo"
		expired     = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.narinfo"
		freshNar    = "nar/fresh.nar.xz"
		sharedNar   = "nar/shared.nar.xz"
		orphanNar   = "nar/orphan.nar.xz"
		youngNar    = "nar/young.nar.xz"
		unrelated   = "nix-cache-info"
		graceCutoff = 7
		retention   = 90
	)

	objects := []Object{
		{Key: fresh, LastModified: at(1, now)},
		{Key: expired, LastModified: at(120, now)},
		{Key: freshNar, LastModified: at(30, now)},
		{Key: sharedNar, LastModified: at(30, now)},
		{Key: orphanNar, LastModified: at(30, now)},
		{Key: youngNar, LastModified: at(1, now)},
		{Key: unrelated, LastModified: at(200, now)},
	}

	t.Run("keeps referenced nars and deletes the rest", func(t *testing.T) {
		surviving := map[string]Narinfo{
			fresh: {Key: fresh, URL: freshNar},
			// Two narinfos may point at the same NAR.
			"cccccccccccccccccccccccccccccccc.narinfo": {Key: "cccccccccccccccccccccccccccccccc.narinfo", URL: sharedNar},
		}

		got := Select(objects, surviving, now, retention, graceCutoff)

		assertKeys(t, "expired narinfos", got.ExpiredNarinfos, []string{expired})
		assertKeys(t, "orphan nars", got.OrphanNars, []string{orphanNar})
		if got.SurvivingNarinfos != 2 {
			t.Fatalf("surviving = %d, want 2", got.SurvivingNarinfos)
		}
		if got.ParseErrors != 0 {
			t.Fatalf("parse errors = %d, want 0", got.ParseErrors)
		}
	})

	t.Run("keeps all nars when a surviving narinfo cannot be parsed", func(t *testing.T) {
		surviving := map[string]Narinfo{
			fresh: {Key: fresh, URL: freshNar},
			"cccccccccccccccccccccccccccccccc.narinfo": {Key: "cccccccccccccccccccccccccccccccc.narinfo", Error: "boom"},
		}

		got := Select(objects, surviving, now, retention, graceCutoff)

		assertKeys(t, "expired narinfos", got.ExpiredNarinfos, []string{expired})
		assertKeys(t, "orphan nars", got.OrphanNars, nil)
		if got.ParseErrors != 1 {
			t.Fatalf("parse errors = %d, want 1", got.ParseErrors)
		}
	})

	t.Run("only deletes expired narinfos when nothing survives", func(t *testing.T) {
		got := Select(objects, nil, now, retention, graceCutoff)

		assertKeys(t, "expired narinfos", got.ExpiredNarinfos, []string{expired})
		assertKeys(t, "orphan nars", got.OrphanNars, []string{freshNar, orphanNar, sharedNar})
		if got.SurvivingNarinfos != 0 {
			t.Fatalf("surviving = %d, want 0", got.SurvivingNarinfos)
		}
	})
}

func TestIsNarinfo(t *testing.T) {
	cases := map[string]bool{
		"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.narinfo":     true,
		"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA.narinfo":     false,
		"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.narinfo":      false,
		"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.narinfo":    false,
		"nar/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.narinfo": false,
		"nix-cache-info": false,
	}

	for key, want := range cases {
		if got := IsNarinfo(key); got != want {
			t.Fatalf("IsNarinfo(%q) = %v, want %v", key, got, want)
		}
	}
}

func assertKeys(t *testing.T, label string, got, want []string) {
	t.Helper()

	if len(got) != len(want) {
		t.Fatalf("%s = %v, want %v", label, got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("%s = %v, want %v", label, got, want)
		}
	}
}
