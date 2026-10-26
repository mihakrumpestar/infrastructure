package main

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"keepass-config-gen/internal/gen"
	"keepass-config-gen/internal/ghauth"
	"keepass-config-gen/internal/secretservice"
)

func item(service, username string) secretservice.Item {
	attributes := map[string]string{}
	if service != "" {
		attributes["service"] = service
	}
	if username != "" {
		attributes["username"] = username
	}
	return secretservice.Item{Attributes: attributes}
}

func TestAccountsFromItems(t *testing.T) {
	tests := []struct {
		name  string
		items []secretservice.Item
		want  []string
	}{
		{
			name: "two hosts with several users are sorted",
			items: []secretservice.Item{
				item("gh:github.com", "zeta"),
				item("gh:github.com", "alpha"),
				item("gh:ghe.example.com", "deploy"),
			},
			want: []string{"ghe.example.com/deploy", "github.com/alpha", "github.com/zeta"},
		},
		{
			name: "the active slot is not an account",
			items: []secretservice.Item{
				item("gh:github.com", ""),
				item("gh:github.com", "alpha"),
			},
			want: []string{"github.com/alpha"},
		},
		{
			name:  "an active slot alone yields nothing",
			items: []secretservice.Item{item("gh:github.com", "")},
		},
		{
			name: "unrelated credentials are ignored",
			items: []secretservice.Item{
				item("GitHub - https://api.github.com", "alpha"),
				item("cf:work", "alpha"),
				item("gh:github.com", "alpha"),
			},
			want: []string{"github.com/alpha"},
		},
		{
			name: "the service prefix alone is not a host",
			items: []secretservice.Item{
				item("gh:", "alpha"),
				item("gh", "alpha"),
			},
		},
		{
			name:  "items without the expected attributes are ignored",
			items: []secretservice.Item{{Attributes: map[string]string{"label": "x"}}},
		},
		{
			name: "duplicate users collapse",
			items: []secretservice.Item{
				item("gh:github.com", "alpha"),
				item("gh:github.com", "alpha"),
			},
			want: []string{"github.com/alpha"},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			var got []string
			for _, account := range accountsFromItems(test.items) {
				got = append(got, account.Host+"/"+account.User)
			}
			if strings.Join(got, ",") != strings.Join(test.want, ",") {
				t.Fatalf("accounts = %v, want %v", got, test.want)
			}
		})
	}
}

// staticSource returns a fixed account list, standing in for the keyring.
func staticSource(accounts []ghauth.Account, err error) func() ([]ghauth.Account, error) {
	return func() ([]ghauth.Account, error) { return accounts, err }
}

func readOutput(t *testing.T, path string) string {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("cannot read output: %v", err)
	}
	return string(data)
}

func TestGenerateWritesHostsFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "gh", "hosts.yml")
	o := options{Output: path, LogFile: path + ".log"}

	err := generateWith(o, staticSource([]ghauth.Account{{Host: "github.com", User: "mihakrumpestar"}}, nil))
	if err != nil {
		t.Fatal(err)
	}

	got := readOutput(t, path)
	for _, want := range []string{"github.com:", "user: mihakrumpestar", "users:", "mihakrumpestar: null"} {
		if !strings.Contains(got, want) {
			t.Fatalf("output missing %q:\n%s", want, got)
		}
	}

	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if mode := info.Mode().Perm(); mode != 0o600 {
		t.Fatalf("mode = %o, want 600", mode)
	}
}

// A locked keyring must never empty the file: that would log the user out.
func TestGenerateLeavesFileOnKeyringError(t *testing.T) {
	path := filepath.Join(t.TempDir(), "hosts.yml")
	original := "github.com:\n    user: keepme\n"
	if err := os.WriteFile(path, []byte(original), 0o600); err != nil {
		t.Fatal(err)
	}

	err := generateWith(
		options{Output: path, LogFile: path + ".log"},
		staticSource(nil, errors.New("Secret Service is locked")),
	)
	if err != nil {
		t.Fatalf("a keyring error must not fail the run: %v", err)
	}
	if got := readOutput(t, path); got != original {
		t.Fatalf("file changed:\n%s", got)
	}
}

func TestGeneratePreservesOtherHosts(t *testing.T) {
	path := filepath.Join(t.TempDir(), "hosts.yml")
	existing := "ghe.example.com:\n    user: deploy\n"
	if err := os.WriteFile(path, []byte(existing), 0o600); err != nil {
		t.Fatal(err)
	}

	if err := generateWith(
		options{Output: path, LogFile: path + ".log"},
		staticSource([]ghauth.Account{{Host: "github.com", User: "me"}}, nil),
	); err != nil {
		t.Fatal(err)
	}

	got := readOutput(t, path)
	if !strings.Contains(got, "ghe.example.com:") || !strings.Contains(got, "github.com:") {
		t.Fatalf("output lost a host:\n%s", got)
	}
}

func TestGenerateCheckIsReadOnly(t *testing.T) {
	path := filepath.Join(t.TempDir(), "hosts.yml")
	if err := os.WriteFile(path, []byte("github.com:\n    user: me\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	o := options{Output: path, LogFile: path + ".log", Check: true}
	source := staticSource([]ghauth.Account{{Host: "github.com", User: "me"}}, nil)

	// The existing file already lists the only discovered user.
	if err := generateWith(o, source); !errors.Is(err, gen.ErrChanged) {
		t.Fatalf("error = %v, want a change because users: is added", err)
	}

	// Bring the file to the reconciled shape, then --check must agree.
	if err := generateWith(options{Output: path, LogFile: path + ".log"}, source); err != nil {
		t.Fatal(err)
	}
	if err := generateWith(o, source); err != nil {
		t.Fatalf("reconciled file still reports a change: %v", err)
	}
}

func TestGenerateIsIdempotent(t *testing.T) {
	path := filepath.Join(t.TempDir(), "hosts.yml")
	o := options{Output: path, LogFile: path + ".log"}
	source := staticSource([]ghauth.Account{{Host: "github.com", User: "me"}}, nil)

	if err := generateWith(o, source); err != nil {
		t.Fatal(err)
	}
	first := readOutput(t, path)

	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := generateWith(o, source); err != nil {
		t.Fatal(err)
	}
	if got := readOutput(t, path); got != first {
		t.Fatalf("second run rewrote the file:\n%s", got)
	}
	// An unchanged run must not even touch the file.
	if after, err := os.Stat(path); err != nil || !after.ModTime().Equal(info.ModTime()) {
		t.Fatalf("unchanged run modified the file: %v", err)
	}
}

func TestGenerateEmptyKeyringCreatesNothing(t *testing.T) {
	path := filepath.Join(t.TempDir(), "hosts.yml")
	if err := generateWith(
		options{Output: path, LogFile: path + ".log"},
		staticSource(nil, nil),
	); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(path); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("an empty keyring created a file: %v", err)
	}
}
