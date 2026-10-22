package main

import (
	"crypto/ecdsa"
	"crypto/ed25519"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/rsa"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"reflect"
	"slices"
	"strings"
	"testing"

	"golang.org/x/crypto/ssh"

	"keepass-config-gen/internal/gen"
	"keepass-config-gen/internal/keepass"
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

// TestDerivePubkeyPassphraseHandling guards the regression where an entry whose
// Password field is set for an unrelated reason (so a passphrase is supplied)
// but whose attached key is unencrypted was dropped: the passphrase parser
// rejects an unencrypted key, so the unencrypted parse must be attempted first.
func TestDerivePubkeyPassphraseHandling(t *testing.T) {
	_, key, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}

	plainBlock, err := ssh.MarshalPrivateKey(key, "")
	if err != nil {
		t.Fatal(err)
	}
	plainPEM := pem.EncodeToMemory(plainBlock)

	encBlock, err := ssh.MarshalPrivateKeyWithPassphrase(key, "", []byte("s3cret"))
	if err != nil {
		t.Fatal(err)
	}
	encPEM := pem.EncodeToMemory(encBlock)

	cases := []struct {
		name       string
		pem        []byte
		passphrase string
		wantErr    bool
	}{
		{"unencrypted/no passphrase", plainPEM, "", false},
		{"unencrypted/with passphrase", plainPEM, "irrelevant", false},
		{"encrypted/correct passphrase", encPEM, "s3cret", false},
		{"encrypted/wrong passphrase", encPEM, "nope", true},
		{"encrypted/no passphrase", encPEM, "", true},
	}
	for _, tc := range cases {
		pub, err := derivePubkey(tc.pem, tc.passphrase)
		if tc.wantErr {
			if err == nil {
				t.Errorf("%s: expected an error, got %q", tc.name, pub)
			}
			continue
		}
		if err != nil {
			t.Errorf("%s: %v", tc.name, err)
			continue
		}
		if !strings.HasPrefix(pub, "ssh-ed25519 ") {
			t.Errorf("%s: got %q", tc.name, pub)
		}
	}
}

func TestStateKeyChangesWithOptions(t *testing.T) {
	base := options{
		Options:          keepass.Options{Database: "db"},
		Output:           "out",
		IdentitiesDir:    "ids",
		AllowedSigners:   "signers",
		GitIdentitiesDir: "git",
		AgentSocket:      "sock",
	}
	key := stateKey(base, "fp")
	if stateKey(base, "fp") != key {
		t.Fatal("state key not stable for identical options")
	}
	for name, o := range map[string]options{
		"database":    {Options: keepass.Options{Database: "other"}, Output: "out", IdentitiesDir: "ids", AllowedSigners: "signers", GitIdentitiesDir: "git", AgentSocket: "sock"},
		"output":      {Options: keepass.Options{Database: "db"}, Output: "other", IdentitiesDir: "ids", AllowedSigners: "signers", GitIdentitiesDir: "git", AgentSocket: "sock"},
		"agentSocket": {Options: keepass.Options{Database: "db"}, Output: "out", IdentitiesDir: "ids", AllowedSigners: "signers", GitIdentitiesDir: "git", AgentSocket: "other"},
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

	// KeePass XML export fixture: three entries, all with the same attachment.
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
		`<Entry>` +
		`<String><Key>Title</Key><Value>wildcard</Value></String>` +
		`<String><Key>Password</Key><Value></Value></String>` +
		`<String><Key>ssh_hosts</Key><Value>*.example.com User=deploy git.name=W git.email=w@example.com</Value></String>` +
		`<String><Key>ssh_sign</Key><Value>w@example.com</Value></String>` +
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
		Options: keepass.Options{
			Database:   dbPath,
			CLI:        script,
			NoPassword: true,
		},
		Output:           output,
		IdentitiesDir:    identitiesDir,
		AllowedSigners:   allowedSigners,
		StateFile:        filepath.Join(dir, "state"),
		GitIdentitiesDir: gitIdentitiesDir,
		IfChanged:        true,
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
	if gen.FileExists(stale) {
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
	if strings.Contains(string(identity), "sshCommand") {
		t.Errorf("git identity must not set core.sshCommand:\n%s", identity)
	}
	include, err := os.ReadFile(filepath.Join(gitIdentitiesDir, "include.conf"))
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{
		`[includeIf "hasconfig:remote.*.url:*@gh:**/**"]`,
		`[includeIf "hasconfig:remote.*.url:*@gh:*"]`,
		"path = " + filepath.Join(gitIdentitiesDir, "gh"),
	} {
		if !strings.Contains(string(include), want) {
			t.Errorf("include.conf missing %q:\n%s", want, include)
		}
	}
	if gen.FileExists(filepath.Join(gitIdentitiesDir, "*.example.com")) {
		t.Error("git identity emitted for a wildcard host alias")
	}
	if strings.Contains(string(include), "*.example.com") {
		t.Errorf("include.conf references a wildcard alias:\n%s", include)
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
	if !gen.FileExists(filepath.Join(gitIdentitiesDir, "include.conf")) {
		t.Error("include.conf was removed by the --if-changed run")
	}

	state, err := os.ReadFile(o.StateFile)
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{
		"v1", output, allowedSigners,
		filepath.Join(gitIdentitiesDir, "gh"),
		filepath.Join(gitIdentitiesDir, "include.conf"),
	} {
		if !strings.Contains(string(state), want) {
			t.Errorf("state is missing %q:\n%s", want, state)
		}
	}
	for _, key := range []string{filepath.Join(identitiesDir, "workstation-")} {
		if !strings.Contains(string(state), key) {
			t.Errorf("state is missing pubkey %q:\n%s", key, state)
		}
	}

	// --check must detect a mutated generated identity.
	identityPath := filepath.Join(gitIdentitiesDir, "gh")
	if err := os.WriteFile(identityPath, []byte("[user]\n  name = Mutated\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	checkOpts := o
	checkOpts.IfChanged = false
	checkOpts.Check = true
	if err := generate(checkOpts); !errors.Is(err, gen.ErrChanged) {
		t.Fatalf("check with mutated identity: got %v, want errChanged", err)
	}

	// --if-changed must not bypass --check.
	checkIfChanged := checkOpts
	checkIfChanged.IfChanged = true
	if err := generate(checkIfChanged); !errors.Is(err, gen.ErrChanged) {
		t.Fatalf("--if-changed --check = %v, want errChanged", err)
	}

	// --if-changed must not bypass --print either.
	printOpts := o
	printOpts.ToStdout = true
	stdout, err := captureStdout(t, func() error { return generate(printOpts) })
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(stdout, "Host ws") {
		t.Fatalf("--if-changed --print produced no config:\n%s", stdout)
	}

	// Restore the mutated identity and verify stale generated files are drift.
	writeOpts := o
	writeOpts.IfChanged = false
	if err := generate(writeOpts); err != nil {
		t.Fatal(err)
	}
	stalePub := filepath.Join(identitiesDir, "stale-00000000.pub")
	if err := os.WriteFile(stalePub, []byte("stale"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := generate(checkOpts); !errors.Is(err, gen.ErrChanged) {
		t.Fatalf("check with stale .pub = %v, want errChanged", err)
	}
	if err := os.Remove(stalePub); err != nil {
		t.Fatal(err)
	}
	staleIdentity := filepath.Join(gitIdentitiesDir, "old")
	if err := os.WriteFile(staleIdentity, []byte("[user]\n  name = Old\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := generate(checkOpts); !errors.Is(err, gen.ErrChanged) {
		t.Fatalf("check with stale git identity = %v, want errChanged", err)
	}
}

func captureStdout(t *testing.T, fn func() error) (string, error) {
	t.Helper()
	original := os.Stdout
	reader, writer, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	os.Stdout = writer
	runErr := fn()
	if err := writer.Close(); err != nil {
		t.Fatal(err)
	}
	os.Stdout = original
	data, err := io.ReadAll(reader)
	if err != nil {
		t.Fatal(err)
	}
	_ = reader.Close()
	return string(data), runErr
}

func TestStateWrittenOnlyForCompleteRuns(t *testing.T) {
	const header = `<KeePassFile><Root><Group><Name>Root</Name>`
	const footer = `</Group></Root></KeePassFile>`

	t.Run("missing key leaves no state", func(t *testing.T) {
		dir := t.TempDir()
		xmlPath := filepath.Join(dir, "db.xml")
		doc := header +
			`<Entry><String><Key>Title</Key><Value>host</Value></String>` +
			`<String><Key>ssh_hosts</Key><Value>h User=u</Value></String></Entry>` +
			footer
		if err := os.WriteFile(xmlPath, []byte(doc), 0o600); err != nil {
			t.Fatal(err)
		}
		script := filepath.Join(dir, "keepassxc-cli")
		body := fmt.Sprintf("#!/bin/sh\ncase \"$1\" in\nexport) cat %q ;;\nesac\n", xmlPath)
		if err := os.WriteFile(script, []byte(body), 0o755); err != nil {
			t.Fatal(err)
		}
		dbPath := filepath.Join(dir, "db.kdbx")
		if err := os.WriteFile(dbPath, []byte("fake"), 0o600); err != nil {
			t.Fatal(err)
		}

		o := options{
			Options:       keepass.Options{Database: dbPath, CLI: script, NoPassword: true},
			Output:        filepath.Join(dir, "config"),
			IdentitiesDir: filepath.Join(dir, "identities"),
			StateFile:     filepath.Join(dir, "state"),
			IfChanged:     true,
		}
		if _, err := captureStderr(t, func() error { return generate(o) }); err != nil {
			t.Fatal(err)
		}
		if gen.FileExists(o.StateFile) {
			t.Fatal("a run with a missing key wrote state")
		}
	})

	t.Run("wildcard alias warning writes state", func(t *testing.T) {
		dir := t.TempDir()
		_, key, err := ed25519.GenerateKey(rand.Reader)
		if err != nil {
			t.Fatal(err)
		}
		block, err := ssh.MarshalPrivateKey(key, "")
		if err != nil {
			t.Fatal(err)
		}
		keyPath := filepath.Join(dir, "id_ed25519")
		if err := os.WriteFile(keyPath, pem.EncodeToMemory(block), 0o600); err != nil {
			t.Fatal(err)
		}
		xmlPath := filepath.Join(dir, "db.xml")
		doc := header +
			`<Entry><String><Key>Title</Key><Value>wildcard</Value></String>` +
			`<String><Key>ssh_hosts</Key><Value>*.example.com User=deploy git.name=W git.email=w@example.com</Value></String>` +
			`<String><Key>ssh_sign</Key><Value>w@example.com</Value></String>` +
			`<Binary><Key>id_ed25519</Key><Value Ref="0"/></Binary></Entry>` +
			footer
		if err := os.WriteFile(xmlPath, []byte(doc), 0o600); err != nil {
			t.Fatal(err)
		}
		script := filepath.Join(dir, "keepassxc-cli")
		body := fmt.Sprintf(`#!/bin/sh
case "$1" in
export) cat %q ;;
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
`, xmlPath, keyPath)
		if err := os.WriteFile(script, []byte(body), 0o755); err != nil {
			t.Fatal(err)
		}
		dbPath := filepath.Join(dir, "db.kdbx")
		if err := os.WriteFile(dbPath, []byte("fake"), 0o600); err != nil {
			t.Fatal(err)
		}

		o := options{
			Options:       keepass.Options{Database: dbPath, CLI: script, NoPassword: true},
			Output:        filepath.Join(dir, "config"),
			IdentitiesDir: filepath.Join(dir, "identities"),
			StateFile:     filepath.Join(dir, "state"),
			IfChanged:     true,
		}
		stderr, err := captureStderr(t, func() error { return generate(o) })
		if err != nil {
			t.Fatal(err)
		}
		if !strings.Contains(stderr, "safe filename") {
			t.Fatalf("wildcard warning missing:\n%s", stderr)
		}
		if !gen.FileExists(o.StateFile) {
			t.Fatal("a wildcard alias warning suppressed state")
		}
	})
}

func captureStderr(t *testing.T, fn func() error) (string, error) {
	t.Helper()
	original := os.Stderr
	reader, writer, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	os.Stderr = writer
	runErr := fn()
	if err := writer.Close(); err != nil {
		t.Fatal(err)
	}
	os.Stderr = original
	data, err := io.ReadAll(reader)
	if err != nil {
		t.Fatal(err)
	}
	_ = reader.Close()
	return string(data), runErr
}

func TestGitInclude(t *testing.T) {
	if got := gitInclude(nil); got != "# Generated by ssh-config-gen. Do not edit by hand.\n" {
		t.Fatalf("gitInclude(nil) = %q", got)
	}
	got := gitInclude([]pubkeyFile{{path: "/d/gh", content: "x"}})
	for _, want := range []string{
		`[includeIf "hasconfig:remote.*.url:*@gh:**/**"]`,
		`[includeIf "hasconfig:remote.*.url:*@gh:*"]`,
		"path = /d/gh",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("gitInclude missing %q:\n%s", want, got)
		}
	}
}

// TestRelevantEntries guards the filtering that keeps non-opted-in entries from
// triggering attachment exports.
func TestRelevantEntries(t *testing.T) {
	entries := []keepass.Entry{
		{Title: "host", Fields: map[string]string{"ssh_hosts": "a"}},
		{Title: "sign", Fields: map[string]string{"ssh_sign": "me@example.com"}},
		{Title: "legacy", Fields: map[string]string{"ssh-host": "b"}},
		{Title: "unrelated", Fields: map[string]string{"note": "x"}},
	}
	got := relevantEntries(entries)
	if len(got) != 3 {
		t.Fatalf("got %d relevant entries, want 3: %#v", len(got), got)
	}
	var titles []string
	for _, entry := range got {
		titles = append(titles, entry.Title)
	}
	if !slices.Equal(titles, []string{"host", "sign", "legacy"}) {
		t.Fatalf("got titles %v", titles)
	}
}

func TestValidIdentityFilename(t *testing.T) {
	valid := []string{"github", "git.example.com", "a-b_c"}
	for _, name := range valid {
		if !validIdentityFilename(name) {
			t.Errorf("validIdentityFilename(%q) rejected a safe name", name)
		}
	}
	invalid := []string{
		"", ".", "..", "../evil", "a/b", `a\b`, "include.conf", "*.example.com", "a b",
		`a"b`, "a#b", "a;b", "a\nb", "a\tb",
	}
	for _, name := range invalid {
		if validIdentityFilename(name) {
			t.Errorf("validIdentityFilename(%q) accepted an unsafe name", name)
		}
	}
}

func TestRenderSkipsUnsafeGitIdentityFilename(t *testing.T) {
	_, key, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	block, err := ssh.MarshalPrivateKey(key, "")
	if err != nil {
		t.Fatal(err)
	}
	entry := keepass.Entry{
		Path:        "/unsafe",
		Title:       "unsafe",
		Attachments: []string{"id_ed25519"},
		Fields: map[string]string{
			"ssh_hosts": "../evil User=git git.name=N git.email=e@example.com",
			"ssh_sign":  "me@example.com",
		},
	}
	attachments := map[string][]byte{
		keepass.AttachmentKey(entry.Path, "id_ed25519"): pem.EncodeToMemory(block),
	}
	_, _, pubkeys, identities, skipped, incomplete, _, _ := render(
		[]keepass.Entry{entry}, attachments, "", options{IdentitiesDir: t.TempDir()},
	)
	if len(pubkeys) != 1 {
		t.Fatalf("pubkeys = %v, want one derived key", pubkeys)
	}
	if len(identities) != 0 {
		t.Fatalf("unsafe identity filename was used: %v", identities)
	}
	if incomplete {
		t.Fatal("a wildcard alias warning marked the run incomplete")
	}
	found := false
	for _, warning := range skipped {
		if strings.Contains(warning, "safe filename") {
			found = true
		}
	}
	if !found {
		t.Fatalf("skipped = %v, want a safe filename warning", skipped)
	}
}
