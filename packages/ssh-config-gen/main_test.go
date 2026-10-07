package main

import (
	"crypto/ecdsa"
	"crypto/ed25519"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/rsa"
	"encoding/pem"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"slices"
	"strings"
	"testing"

	"golang.org/x/crypto/ssh"
)

func TestParseHosts(t *testing.T) {
	input := `
# a comment
workstation HostName=192.0.2.10 Port=2200 User=admin

git.example.com,git-alt HostName=git.example.com Port=443 User=git
*.prod.example.com User=deploy ProxyJump=bastion
`
	got := parseHosts(input)
	want := []hostEntry{
		{
			patterns: []string{"workstation"},
			options:  [][2]string{{"HostName", "192.0.2.10"}, {"Port", "2200"}, {"User", "admin"}},
		},
		{
			patterns: []string{"git.example.com", "git-alt"},
			options:  [][2]string{{"HostName", "git.example.com"}, {"Port", "443"}, {"User", "git"}},
		},
		{
			patterns: []string{"*.prod.example.com"},
			options:  [][2]string{{"User", "deploy"}, {"ProxyJump", "bastion"}},
		},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %#v, want %#v", got, want)
	}
}

func TestParseHostsGitIdentity(t *testing.T) {
	got := parseHosts("github-personal HostName=ssh.github.com Port=443 User=git git.name=Miha git.email=me@example.com")
	if len(got) != 1 {
		t.Fatalf("got %d entries, want 1", len(got))
	}
	entry := got[0]
	if entry.gitName != "Miha" || entry.gitEmail != "me@example.com" {
		t.Fatalf("git fields: name=%q email=%q", entry.gitName, entry.gitEmail)
	}
	for _, option := range entry.options {
		if strings.HasPrefix(option[0], "git.") {
			t.Fatalf("git option leaked into OpenSSH options: %v", option)
		}
	}
}

func TestParseHostsSkipsInvalidLines(t *testing.T) {
	got := parseHosts("\n   \n# only a comment\nHost=1.2.3.4\n")
	if len(got) != 1 || got[0].patterns[0] != "Host=1.2.3.4" {
		t.Fatalf("unexpected result: %#v", got)
	}
}

func TestTokenizeHonoursQuotes(t *testing.T) {
	got := tokenize(`host ProxyCommand="ssh -W %h:%p jump" User=root`)
	want := []string{"host", "ProxyCommand=ssh -W %h:%p jump", "User=root"}
	if !slices.Equal(got, want) {
		t.Fatalf("got %#v, want %#v", got, want)
	}
}

func TestExplicitIdentity(t *testing.T) {
	withIdentity := hostEntry{options: [][2]string{{"IdentityFile", "~/.ssh/id"}}}
	withoutIdentity := hostEntry{options: [][2]string{{"User", "root"}}}
	if !withIdentity.explicitIdentity() {
		t.Fatal("expected explicit identity to be detected")
	}
	if withoutIdentity.explicitIdentity() {
		t.Fatal("did not expect explicit identity")
	}
}

func TestBuildBlock(t *testing.T) {
	entry := hostEntry{patterns: []string{"a", "b"}, options: [][2]string{{"Port", "2222"}}}
	got := strings.Join(buildBlock(entry, "/tmp/a.pub", "/run/user/1000/agent.sock"), "\n")
	want := strings.Join([]string{
		"Host a b",
		"    Port 2222",
		"    IdentityFile /tmp/a.pub",
		"    IdentityAgent /run/user/1000/agent.sock",
		"    IdentitiesOnly yes",
	}, "\n")
	if got != want {
		t.Fatalf("got:\n%s\nwant:\n%s", got, want)
	}
}

func TestSanitise(t *testing.T) {
	cases := map[string]string{
		"My Host.two": "My_Host.two",
		"":            "key",
		"***":         "key",
	}
	for input, want := range cases {
		if got := sanitise(input); got != want {
			t.Errorf("sanitise(%q) = %q, want %q", input, got, want)
		}
	}
}

func TestSplitList(t *testing.T) {
	got := splitList("a@example.com, b@example.com\nc@example.com\n")
	want := []string{"a@example.com", "b@example.com", "c@example.com"}
	if !slices.Equal(got, want) {
		t.Fatalf("got %#v, want %#v", got, want)
	}
}

func TestDbFingerprintChanges(t *testing.T) {
	path := filepath.Join(t.TempDir(), "db.kdbx")
	if err := os.WriteFile(path, []byte("a"), 0o600); err != nil {
		t.Fatal(err)
	}
	first, err := dbFingerprint(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte("bb"), 0o600); err != nil {
		t.Fatal(err)
	}
	second, err := dbFingerprint(path)
	if err != nil {
		t.Fatal(err)
	}
	if first == second {
		t.Fatalf("fingerprint did not change: %q", first)
	}
}

func TestArgvPlacesOptionsAfterSubcommand(t *testing.T) {
	o := options{cli: "keepassxc-cli", yubikey: "2", noPassword: true}
	got := o.argv("export", "-f", "xml", "/db")
	want := []string{"export", "-y", "2", "--no-password", "-f", "xml", "/db"}
	if !slices.Equal(got, want) {
		t.Fatalf("got %#v, want %#v", got, want)
	}
	got = o.argv("attachment-export", "--stdout", "/db", "/Entry", "id_ed25519")
	want = []string{"attachment-export", "-y", "2", "--no-password", "--stdout", "/db", "/Entry", "id_ed25519"}
	if !slices.Equal(got, want) {
		t.Fatalf("got %#v, want %#v", got, want)
	}
}

func TestPruneIdentities(t *testing.T) {
	dir := t.TempDir()
	keepPath := filepath.Join(dir, "keep-12345678.pub")
	stalePath := filepath.Join(dir, "stale-12345678.pub")
	otherPath := filepath.Join(dir, "notes.txt")
	for _, path := range []string{keepPath, stalePath, otherPath} {
		if err := os.WriteFile(path, []byte("x"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	if err := pruneDir(dir, map[string]bool{keepPath: true}, ".pub"); err != nil {
		t.Fatal(err)
	}
	if !fileExists(keepPath) {
		t.Error("kept .pub was removed")
	}
	if fileExists(stalePath) {
		t.Error("stale .pub was not removed")
	}
	if !fileExists(otherPath) {
		t.Error("non-.pub file was removed")
	}
}

// TestParseXMLPaths guards that entry paths exclude the root group's name, which
// is what keepassxc-cli expects.
func TestParseXMLPaths(t *testing.T) {
	const doc = `<KeePassFile><Root><Group><Name>Root</Name>` +
		`<Entry><String><Key>Title</Key><Value>top</Value></String></Entry>` +
		`<Group><Name>Sub</Name>` +
		`<Entry><String><Key>Title</Key><Value>nested</Value></String></Entry>` +
		`</Group></Group></Root></KeePassFile>`

	entries, err := parseXML([]byte(doc))
	if err != nil {
		t.Fatal(err)
	}
	want := map[string]string{"top": "/top", "nested": "/Sub/nested"}
	if len(entries) != len(want) {
		t.Fatalf("got %d entries, want %d", len(entries), len(want))
	}
	for _, entry := range entries {
		if want[entry.title] != entry.path {
			t.Errorf("entry %q path = %q, want %q", entry.title, entry.path, want[entry.title])
		}
	}
}

func TestDerivePubkey(t *testing.T) {
	_, edKey, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	rsaKey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	ecdsaKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}

	cases := map[string]struct {
		key  any
		want string
	}{
		"ed25519": {edKey, "ssh-ed25519 "},
		"rsa":     {rsaKey, "ssh-rsa "},
		"ecdsa":   {ecdsaKey, "ecdsa-sha2-nistp256 "},
	}
	for name, tc := range cases {
		block, err := ssh.MarshalPrivateKey(tc.key, "")
		if err != nil {
			t.Fatalf("%s: marshal: %v", name, err)
		}
		pemBytes := pem.EncodeToMemory(block)
		pub, err := derivePubkey(pemBytes, "")
		if err != nil {
			t.Fatalf("%s: derivePubkey: %v", name, err)
		}
		if !strings.HasPrefix(pub, tc.want) {
			t.Errorf("%s: got %q, want prefix %q", name, pub, tc.want)
		}
	}
}

func TestCliArg(t *testing.T) {
	cases := map[string]string{
		"plain":         "plain",
		"has space":     `"has space"`,
		`has"quote`:     `"has\"quote"`,
		`both " and sp`: `"both \" and sp"`,
	}
	for input, want := range cases {
		if got := cliArg(input); got != want {
			t.Errorf("cliArg(%q) = %q, want %q", input, got, want)
		}
	}
}

func TestAttachmentKey(t *testing.T) {
	if got := attachmentKey("/Entry", "id_ed25519"); got != "/Entry\x00id_ed25519" {
		t.Fatalf("got %q", got)
	}
}

func TestStateKeyChangesWithOptions(t *testing.T) {
	base := options{
		output:           "out",
		identitiesDir:    "ids",
		allowedSigners:   "signers",
		gitIdentitiesDir: "git",
		agentSocket:      "sock",
	}
	key := stateKey(base, "fp")
	if stateKey(base, "fp") != key {
		t.Fatal("state key not stable for identical options")
	}
	for name, o := range map[string]options{
		"output":      {output: "other", identitiesDir: "ids", allowedSigners: "signers", gitIdentitiesDir: "git", agentSocket: "sock"},
		"agentSocket": {output: "out", identitiesDir: "ids", allowedSigners: "signers", gitIdentitiesDir: "git", agentSocket: "other"},
	} {
		if stateKey(o, "fp") == key {
			t.Errorf("%s: state key did not change", name)
		}
	}
}

// TestGenerateEndToEnd drives generate against a fake keepassxc-cli: it exports
// two entries from an XML fixture, derives their shared ed25519 key inside a
// single `open` session, and checks the generated artifacts plus the
// --if-changed short-circuit.
func TestGenerateEndToEnd(t *testing.T) {
	dir := t.TempDir()

	// Unencrypted ed25519 private key, used as the attachment.
	_, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	block, err := ssh.MarshalPrivateKey(priv, "")
	if err != nil {
		t.Fatal(err)
	}
	keyPath := filepath.Join(dir, "id_ed25519")
	if err := os.WriteFile(keyPath, pem.EncodeToMemory(block), 0o600); err != nil {
		t.Fatal(err)
	}

	// KeePass XML export fixture: two entries, both with the same attachment.
	xmlPath := filepath.Join(dir, "db.xml")
	const doc = `<KeePassFile><Root><Group><Name>Root</Name>` +
		`<Entry>` +
		`<String><Key>Title</Key><Value>workstation</Value></String>` +
		`<String><Key>Password</Key><Value></Value></String>` +
		`<String><Key>ssh_hosts</Key><Value>ws HostName=10.0.0.1 User=admin</Value></String>` +
		`<Binary><Key>id_ed25519</Key><Value Ref="0"/></Binary>` +
		`</Entry>` +
		`<Entry>` +
		`<String><Key>Title</Key><Value>github</Value></String>` +
		`<String><Key>Password</Key><Value></Value></String>` +
		`<String><Key>ssh_hosts</Key><Value>gh User=git HostName=ssh.github.com git.name=Miha git.email=me@example.com</Value></String>` +
		`<String><Key>ssh_sign</Key><Value>me@example.com</Value></String>` +
		`<Binary><Key>id_ed25519</Key><Value Ref="0"/></Binary>` +
		`</Entry>` +
		`</Group></Root></KeePassFile>`
	if err := os.WriteFile(xmlPath, []byte(doc), 0o600); err != nil {
		t.Fatal(err)
	}

	// Fake keepassxc-cli: `export`/`attachment-export` cat fixtures; `open`
	// replays attachment-export lines from stdin. Every call is logged.
	callLog := filepath.Join(dir, "calls")
	script := filepath.Join(dir, "keepassxc-cli")
	scriptBody := fmt.Sprintf(`#!/bin/sh
printf '%%s\n' "$*" >> %q
case "$1" in
export)
	cat %q
	;;
attachment-export)
	cat %q
	;;
open)
	while IFS= read -r line; do
		case "$line" in
		attachment-export*)
			set -- $line
			cat %q > "$4"
			;;
		esac
	done
	;;
esac
`, callLog, xmlPath, keyPath, keyPath)
	if err := os.WriteFile(script, []byte(scriptBody), 0o755); err != nil {
		t.Fatal(err)
	}

	// A dummy database file and a stale generated key.
	dbPath := filepath.Join(dir, "db.kdbx")
	if err := os.WriteFile(dbPath, []byte("fake"), 0o600); err != nil {
		t.Fatal(err)
	}
	identitiesDir := filepath.Join(dir, "identities")
	if err := os.MkdirAll(identitiesDir, 0o700); err != nil {
		t.Fatal(err)
	}
	stale := filepath.Join(identitiesDir, "stale-00000000.pub")
	if err := os.WriteFile(stale, []byte("stale"), 0o644); err != nil {
		t.Fatal(err)
	}

	output := filepath.Join(dir, "config")
	allowedSigners := filepath.Join(dir, "allowed_signers")
	gitIdentitiesDir := filepath.Join(dir, "git-identities")
	o := options{
		database:         dbPath,
		cli:              script,
		noPassword:       true,
		output:           output,
		identitiesDir:    identitiesDir,
		allowedSigners:   allowedSigners,
		stateFile:        filepath.Join(dir, "state"),
		gitIdentitiesDir: gitIdentitiesDir,
		ifChanged:        true,
	}

	if err := generate(o); err != nil {
		t.Fatalf("generate: %v", err)
	}

	config, err := os.ReadFile(output)
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{"Host ws", "Host gh", "IdentityFile"} {
		if !strings.Contains(string(config), want) {
			t.Errorf("config missing %q:\n%s", want, config)
		}
	}
	if fileExists(stale) {
		t.Error("stale .pub was not pruned")
	}
	signers, err := os.ReadFile(allowedSigners)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(signers), `me@example.com namespaces="git" ssh-ed25519 `) {
		t.Errorf("allowed_signers missing signer:\n%s", signers)
	}
	identity, err := os.ReadFile(filepath.Join(gitIdentitiesDir, "gh"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(identity), "email = me@example.com") {
		t.Errorf("git identity missing email:\n%s", identity)
	}

	// --if-changed must short-circuit before touching keepassxc-cli again.
	before, err := os.ReadFile(callLog)
	if err != nil {
		t.Fatal(err)
	}
	if err := generate(o); err != nil {
		t.Fatalf("second generate: %v", err)
	}
	after, err := os.ReadFile(callLog)
	if err != nil {
		t.Fatal(err)
	}
	if string(before) != string(after) {
		t.Fatalf("call log changed on unchanged database:\nbefore:\n%s\nafter:\n%s", before, after)
	}
}
