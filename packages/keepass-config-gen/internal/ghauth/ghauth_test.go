package ghauth

import (
	"slices"
	"strings"
	"testing"

	"gopkg.in/yaml.v3"
)

const (
	hostGitHub = "github.com"
	hostGHE    = "ghe.example.com"
)

func TestReconcileLeavesBytesAloneWithoutAccounts(t *testing.T) {
	existing := []byte("github.com:\n    user: monalisa\n")
	for name, input := range map[string][]byte{
		"nil":   nil,
		"empty": {},
		"bytes": existing,
	} {
		t.Run(name, func(t *testing.T) {
			out, changed, guessed, err := Reconcile(input, nil)
			if err != nil {
				t.Fatal(err)
			}
			if changed {
				t.Error("changed = true, want false")
			}
			if string(out) != string(input) {
				t.Errorf("out = %q, want untouched %q", out, input)
			}
			if len(guessed) != 0 {
				t.Errorf("guessed = %v, want none", guessed)
			}
		})
	}
}

func TestReconcileEmptyDocument(t *testing.T) {
	out, changed, guessed, err := Reconcile(nil, []Account{{Host: hostGitHub, User: "monalisa"}})
	if err != nil {
		t.Fatal(err)
	}
	if !changed {
		t.Error("changed = false, want true")
	}
	if len(guessed) != 0 {
		t.Errorf("guessed = %v, want none", guessed)
	}
	want := "github.com:\n    user: monalisa\n    users:\n        monalisa: null\n"
	if string(out) != want {
		t.Errorf("out =\n%s want\n%s", out, want)
	}
}

func TestReconcileSelection(t *testing.T) {
	tests := []struct {
		name     string
		existing string
		accounts []Account
		wantUser string
		wantGues []string
	}{
		{
			name:     "existing user beats alphabetically first candidate",
			existing: "github.com:\n    user: monalisa\n    users:\n        monalisa: null\n        hubot: null\n",
			accounts: []Account{
				{Host: hostGitHub, User: "monalisa"},
				{Host: hostGitHub, User: "hubot"},
			},
			wantUser: "monalisa",
		},
		{
			name:     "single candidate",
			existing: "",
			accounts: []Account{{Host: hostGitHub, User: "hubot"}},
			wantUser: "hubot",
		},
		{
			name:     "ambiguous picks first and reports",
			existing: "",
			accounts: []Account{
				{Host: hostGitHub, User: "monalisa"},
				{Host: hostGitHub, User: "hubot"},
			},
			wantUser: "hubot",
			wantGues: []string{hostGitHub},
		},
		{
			name:     "existing user dropped when not discovered",
			existing: "github.com:\n    user: ghost\n    users:\n        ghost: null\n",
			accounts: []Account{{Host: hostGitHub, User: "monalisa"}},
			wantUser: "monalisa",
		},
		{
			name:     "inline token user is eligible",
			existing: "github.com:\n    user: tokenuser\n    users:\n        tokenuser:\n            oauth_token: ghp_inline\n",
			accounts: []Account{{Host: hostGitHub, User: "keyringuser"}},
			wantUser: "tokenuser",
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			out, changed, guessed, err := Reconcile([]byte(test.existing), test.accounts)
			if err != nil {
				t.Fatal(err)
			}
			if !changed {
				t.Error("changed = false, want true")
			}
			doc := mustParse(t, out)
			entry := mustEntry(t, doc, hostGitHub)
			if got := lookup(entry, keyUser).Value; got != test.wantUser {
				t.Errorf("user = %q, want %q", got, test.wantUser)
			}
			if !slices.Equal(guessed, test.wantGues) {
				t.Errorf("guessed = %v, want %v", guessed, test.wantGues)
			}
		})
	}
}

func TestReconcileKeepsInlineTokenUser(t *testing.T) {
	existing := []byte(`github.com:
    user: monalisa
    users:
        monalisa: null
        tokenuser:
            oauth_token: "ghp_inline_abc123"
`)
	out, _, _, err := Reconcile(existing, []Account{{Host: hostGitHub, User: "monalisa"}})
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(out), `oauth_token: "ghp_inline_abc123"`) {
		t.Errorf("inline token not byte-identical:\n%s", out)
	}
	entry := mustEntry(t, mustParse(t, out), hostGitHub)
	users := lookup(entry, keyUsers)
	if got := sortedKeysMap(users); !slices.Equal(got, []string{"monalisa", "tokenuser"}) {
		t.Errorf("users = %v, want both the keyring and the inline token user", got)
	}
	if token := lookup(lookup(users, "tokenuser"), keyToken); token == nil || token.Value != "ghp_inline_abc123" {
		t.Errorf("inline user mapping was rewritten: %v", token)
	}
}

func TestReconcileGuessedIsSorted(t *testing.T) {
	accounts := []Account{
		{Host: "zeta.example.com", User: "zed"},
		{Host: "zeta.example.com", User: "amy"},
		{Host: "alpha.example.com", User: "bob"},
		{Host: "alpha.example.com", User: "carol"},
	}
	_, _, guessed, err := Reconcile(nil, accounts)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"alpha.example.com", "zeta.example.com"}
	if !slices.Equal(guessed, want) {
		t.Errorf("guessed = %v, want sorted %v", guessed, want)
	}
}

func TestReconcileDropsOrphanUsers(t *testing.T) {
	existing := []byte("github.com:\n    user: monalisa\n    users:\n        monalisa: null\n        ghost: null\n")
	out, _, _, err := Reconcile(existing, []Account{{Host: hostGitHub, User: "monalisa"}})
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(out), "ghost") {
		t.Errorf("token-less orphan survived:\n%s", out)
	}
}

func TestReconcileDropsEmptyTokenUser(t *testing.T) {
	existing := []byte("github.com:\n    users:\n        ghost:\n            oauth_token: \"\"\n")
	out, _, _, err := Reconcile(existing, []Account{{Host: hostGitHub, User: "monalisa"}})
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(out), "ghost") {
		t.Errorf("user with an empty token must not survive:\n%s", out)
	}
}

func TestReconcilePreservesForeignKeys(t *testing.T) {
	existing := []byte(`github.com:
    api_host: api.github.com
    git_protocol: ssh
    user: monalisa
    users:
        ghost: null
ghe.example.com:
    user: hubot
    unknown: keep-me
`)
	out, changed, guessed, err := Reconcile(existing, []Account{{Host: hostGitHub, User: "monalisa"}})
	if err != nil {
		t.Fatal(err)
	}
	if !changed {
		t.Error("changed = false, want true")
	}
	if len(guessed) != 0 {
		t.Errorf("guessed = %v, want none", guessed)
	}
	doc := mustParse(t, out)
	gitHub := mustEntry(t, doc, hostGitHub)
	for key, want := range map[string]string{"api_host": "api.github.com", "git_protocol": "ssh"} {
		if got := lookup(gitHub, key); got == nil || got.Value != want {
			t.Errorf("%s = %v, want %s", key, got, want)
		}
	}
	if got := sortedKeysMap(lookup(gitHub, keyUsers)); !slices.Equal(got, []string{"monalisa"}) {
		t.Errorf("users = %v, want only monalisa", got)
	}
	untouched := mustEntry(t, doc, hostGHE)
	if got := lookup(untouched, keyUser).Value; got != "hubot" {
		t.Errorf("untouched host user = %q, want hubot", got)
	}
	if got := lookup(untouched, "unknown").Value; got != "keep-me" {
		t.Errorf("untouched host unknown = %q, want keep-me", got)
	}
}

func TestReconcileNullAndAbsentHostMatch(t *testing.T) {
	accounts := []Account{{Host: hostGitHub, User: "monalisa"}}
	absent, _, _, err := Reconcile(nil, accounts)
	if err != nil {
		t.Fatal(err)
	}
	nulled, _, _, err := Reconcile([]byte("github.com:\n"), accounts)
	if err != nil {
		t.Fatal(err)
	}
	if string(absent) != string(nulled) {
		t.Errorf("absent =\n%s null =\n%s", absent, nulled)
	}
}

func TestReconcileIdempotent(t *testing.T) {
	accounts := []Account{
		{Host: hostGitHub, User: "monalisa"},
		{Host: hostGitHub, User: "hubot"},
		{Host: hostGHE, User: "octocat"},
	}
	first, changed, guessed, err := Reconcile(nil, accounts)
	if err != nil {
		t.Fatal(err)
	}
	if !changed {
		t.Error("first pass changed = false, want true")
	}
	if !slices.Equal(guessed, []string{hostGitHub}) {
		t.Errorf("guessed = %v, want [%s]", guessed, hostGitHub)
	}
	second, changed, guessed, err := Reconcile(first, accounts)
	if err != nil {
		t.Fatal(err)
	}
	if changed {
		t.Errorf("second pass changed = true, want false:\n%s", second)
	}
	if string(second) != string(first) {
		t.Errorf("second pass bytes differ:\n%s\nvs\n%s", second, first)
	}
	if len(guessed) != 0 {
		t.Errorf("guessed = %v on second pass, want none: the written user is now a valid fallback", guessed)
	}
}

func TestReconcileIndentAndNoSeparator(t *testing.T) {
	out, _, _, err := Reconcile(nil, []Account{{Host: hostGitHub, User: "monalisa"}})
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(out), "---") {
		t.Errorf("document separator emitted:\n%s", out)
	}
	if !strings.Contains(string(out), "\n    user: monalisa") {
		t.Errorf("4-space indentation missing:\n%s", out)
	}
	if !strings.HasSuffix(string(out), "\n") || strings.HasSuffix(string(out), "\n\n") {
		t.Errorf("want exactly one trailing newline:\n%q", out)
	}
}

func TestReconcileMalformedExisting(t *testing.T) {
	for name, input := range map[string]string{
		"bad flow":  "github.com: [unclosed\n",
		"not a map": "- just\n- a list\n",
	} {
		t.Run(name, func(t *testing.T) {
			out, changed, guessed, err := Reconcile([]byte(input), []Account{{Host: hostGitHub, User: "monalisa"}})
			if err == nil {
				t.Fatal("err = nil, want parse error")
			}
			if out != nil {
				t.Errorf("out = %q, want nil", out)
			}
			if changed {
				t.Error("changed = true, want false")
			}
			if len(guessed) != 0 {
				t.Errorf("guessed = %v, want none", guessed)
			}
			if !strings.Contains(err.Error(), "hosts.yml") {
				t.Errorf("err = %v, want it to name hosts.yml", err)
			}
		})
	}
}

func TestReconcileRejectsNonMappingHost(t *testing.T) {
	out, changed, _, err := Reconcile([]byte("github.com: on\n"), []Account{{Host: hostGitHub, User: "monalisa"}})
	if err == nil {
		t.Fatal("err = nil, want error for a scalar host entry")
	}
	if out != nil || changed {
		t.Errorf("out = %q changed = %v, want no output", out, changed)
	}
}

func TestReconcileSkipsIncompleteAccounts(t *testing.T) {
	out, changed, guessed, err := Reconcile(nil, []Account{{Host: hostGitHub}, {User: "monalisa"}})
	if err != nil {
		t.Fatal(err)
	}
	if changed || out != nil || len(guessed) != 0 {
		t.Errorf("out = %q changed = %v guessed = %v, want untouched", out, changed, guessed)
	}
}

func mustParse(t *testing.T, data []byte) *document {
	t.Helper()
	doc, err := parse(data)
	if err != nil {
		t.Fatalf("parse output: %v\n%s", err, data)
	}
	return doc
}

func mustEntry(t *testing.T, doc *document, host string) *yaml.Node {
	t.Helper()
	entry := lookup(doc.root, host)
	if entry == nil || entry.Kind != yaml.MappingNode {
		t.Fatalf("host %s missing or not a mapping", host)
	}
	return entry
}

// sortedKeysMap returns the keys of a users mapping in order.
func sortedKeysMap(users *yaml.Node) []string {
	names := make([]string, 0, len(users.Content)/2)
	for i := 0; i+1 < len(users.Content); i += 2 {
		names = append(names, users.Content[i].Value)
	}
	slices.Sort(names)
	return names
}
