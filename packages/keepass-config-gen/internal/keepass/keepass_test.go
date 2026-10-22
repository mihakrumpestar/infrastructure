package keepass

import (
	"encoding/base64"
	"encoding/hex"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"slices"
	"testing"
)

func TestTokenizeHonoursQuotes(t *testing.T) {
	got := Tokenize(`host ProxyCommand="ssh -W %h:%p jump" User=root`)
	want := []string{"host", "ProxyCommand=ssh -W %h:%p jump", "User=root"}
	if !slices.Equal(got, want) {
		t.Fatalf("got %#v, want %#v", got, want)
	}
}

func TestSanitise(t *testing.T) {
	cases := map[string]string{
		"My Host.two": "My_Host.two",
		"":            "key",
		"***":         "key",
	}
	for input, want := range cases {
		if got := Sanitise(input); got != want {
			t.Errorf("Sanitise(%q) = %q, want %q", input, got, want)
		}
	}
}

func TestSplitList(t *testing.T) {
	got := SplitList("a@example.com, b@example.com\nc@example.com\n")
	want := []string{"a@example.com", "b@example.com", "c@example.com"}
	if !slices.Equal(got, want) {
		t.Fatalf("got %#v, want %#v", got, want)
	}
}

func TestFingerprintChanges(t *testing.T) {
	path := filepath.Join(t.TempDir(), "db.kdbx")
	if err := os.WriteFile(path, []byte("a"), 0o600); err != nil {
		t.Fatal(err)
	}
	first, err := Fingerprint(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte("bb"), 0o600); err != nil {
		t.Fatal(err)
	}
	second, err := Fingerprint(path)
	if err != nil {
		t.Fatal(err)
	}
	if first == second {
		t.Fatalf("fingerprint did not change: %q", first)
	}
}

func TestArgvPlacesOptionsAfterSubcommand(t *testing.T) {
	o := Options{CLI: "keepassxc-cli", Yubikey: "2", NoPassword: true}
	got := o.Argv("export", "-f", "xml", "/db")
	want := []string{"export", "-y", "2", "--no-password", "-f", "xml", "/db"}
	if !slices.Equal(got, want) {
		t.Fatalf("got %#v, want %#v", got, want)
	}
	got = o.Argv("attachment-export", "--stdout", "/db", "/Entry", "id_ed25519")
	want = []string{"attachment-export", "-y", "2", "--no-password", "--stdout", "/db", "/Entry", "id_ed25519"}
	if !slices.Equal(got, want) {
		t.Fatalf("got %#v, want %#v", got, want)
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

	entries, err := ParseXML([]byte(doc))
	if err != nil {
		t.Fatal(err)
	}
	want := map[string]string{"top": "/top", "nested": "/Sub/nested"}
	if len(entries) != len(want) {
		t.Fatalf("got %d entries, want %d", len(entries), len(want))
	}
	for _, entry := range entries {
		if want[entry.Title] != entry.Path {
			t.Errorf("entry %q path = %q, want %q", entry.Title, entry.Path, want[entry.Title])
		}
	}
}

// TestParseXMLUUID guards that the base64 UUID element is exposed as hex.
func TestParseXMLUUID(t *testing.T) {
	raw := []byte{
		0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef,
		0xfe, 0xdc, 0xba, 0x98, 0x76, 0x54, 0x32, 0x10,
	}
	encoded := base64.StdEncoding.EncodeToString(raw)
	doc := `<KeePassFile><Root><Group><Name>Root</Name>` +
		`<Entry><UUID>` + encoded + `</UUID>` +
		`<String><Key>Title</Key><Value>entry</Value></String>` +
		`</Entry></Group></Root></KeePassFile>`

	entries, err := ParseXML([]byte(doc))
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 1 {
		t.Fatalf("got %d entries, want 1", len(entries))
	}
	if want := hex.EncodeToString(raw); entries[0].UUID != want {
		t.Fatalf("UUID = %q, want %q", entries[0].UUID, want)
	}
}

func TestCliArg(t *testing.T) {
	cases := map[string]struct {
		want string
		ok   bool
	}{
		"plain":            {"plain", true},
		"has space":        {`"has space"`, true},
		`has"quote`:        {`"has\"quote"`, true},
		`both " and sp`:    {`"both \" and sp"`, true},
		`a\b`:              {`"a\\b"`, true},
		"line\nbreak":      {"", false},
		"carriage\rreturn": {"", false},
		"nul\x00byte":      {"", false},
	}
	for input, tc := range cases {
		got, ok := cliArg(input)
		if got != tc.want || ok != tc.ok {
			t.Errorf("cliArg(%q) = (%q, %v), want (%q, %v)", input, got, ok, tc.want, tc.ok)
		}
	}
}

func TestAttachmentKey(t *testing.T) {
	if got := AttachmentKey("/Entry", "id_ed25519"); got != "/Entry\x00id_ed25519" {
		t.Fatalf("got %q", got)
	}
}

func TestCollectAttachmentRequests(t *testing.T) {
	entries := []Entry{
		{Path: "/a", Attachments: []string{"one", "two"}},
		{Path: "/b"},
		{Path: "/c", Attachments: []string{"three"}},
	}
	got := CollectAttachmentRequests(entries)
	want := []AttachmentRequest{
		{EntryPath: "/a", Name: "one"},
		{EntryPath: "/a", Name: "two"},
		{EntryPath: "/c", Name: "three"},
	}
	if !slices.Equal(got, want) {
		t.Fatalf("got %#v, want %#v", got, want)
	}
}

func TestParseXMLInvalidUUIDIsEmpty(t *testing.T) {
	const doc = `<KeePassFile><Root><Group><Name>Root</Name>` +
		`<Entry><UUID>!!!not-base64!!!</UUID>` +
		`<String><Key>Title</Key><Value>entry</Value></String>` +
		`</Entry></Group></Root></KeePassFile>`
	entries, err := ParseXML([]byte(doc))
	if err != nil {
		t.Fatalf("invalid UUID aborted the export: %v", err)
	}
	if len(entries) != 1 {
		t.Fatalf("got %d entries, want 1", len(entries))
	}
	if entries[0].UUID != "" {
		t.Fatalf("UUID = %q, want empty", entries[0].UUID)
	}
}

func TestParseXMLWrongLengthUUIDIsEmpty(t *testing.T) {
	encoded := base64.StdEncoding.EncodeToString([]byte{0x01, 0x02, 0x03, 0x04})
	doc := `<KeePassFile><Root><Group><Name>Root</Name>` +
		`<Entry><UUID>` + encoded + `</UUID>` +
		`<String><Key>Title</Key><Value>entry</Value></String>` +
		`</Entry></Group></Root></KeePassFile>`
	entries, err := ParseXML([]byte(doc))
	if err != nil {
		t.Fatalf("wrong-length UUID aborted the export: %v", err)
	}
	if len(entries) != 1 {
		t.Fatalf("got %d entries, want 1", len(entries))
	}
	if entries[0].UUID != "" {
		t.Fatalf("UUID = %q, want empty", entries[0].UUID)
	}
}

func TestRunInheritsStdinWithoutPassword(t *testing.T) {
	dir := t.TempDir()
	script := filepath.Join(dir, "keepassxc-cli")
	body := "#!/bin/sh\nif read line; then echo \"read:$line\"; else echo eof; fi\n"
	if err := os.WriteFile(script, []byte(body), 0o755); err != nil {
		t.Fatal(err)
	}

	reader, writer, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	original := os.Stdin
	os.Stdin = reader
	t.Cleanup(func() {
		os.Stdin = original
		_ = reader.Close()
	})
	if _, err := io.WriteString(writer, "typed-secret\n"); err != nil {
		t.Fatal(err)
	}
	if err := writer.Close(); err != nil {
		t.Fatal(err)
	}

	o := Options{CLI: script}
	out, err := o.Run("", "export", "-f", "xml", "/db")
	if err != nil {
		t.Fatal(err)
	}
	if string(out) != "read:typed-secret\n" {
		t.Fatalf("stdin = %q, want the inherited line", out)
	}
}

func TestExportAttachmentsEmptyPasswordFallsBack(t *testing.T) {
	dir := t.TempDir()
	marker := filepath.Join(dir, "ran")
	script := filepath.Join(dir, "keepassxc-cli")
	body := fmt.Sprintf("#!/bin/sh\ntouch %q\n", marker)
	if err := os.WriteFile(script, []byte(body), 0o755); err != nil {
		t.Fatal(err)
	}

	o := Options{CLI: script, Database: "/db"}
	got := o.ExportAttachments("", []AttachmentRequest{{EntryPath: "/entry", Name: "key"}})
	if got != nil {
		t.Fatalf("empty password returned %#v, want nil", got)
	}
	if _, err := os.Stat(marker); !os.IsNotExist(err) {
		t.Fatalf("interactive export ran without a password: %v", err)
	}
}

func TestExportAttachmentsNoPassword(t *testing.T) {
	dir := t.TempDir()
	script := filepath.Join(dir, "keepassxc-cli")
	body := `#!/bin/sh
while IFS= read -r line; do
	case "$line" in
	attachment-export*)
		set -- $line
		printf 'payload' > "$4"
		;;
	esac
done
`
	if err := os.WriteFile(script, []byte(body), 0o755); err != nil {
		t.Fatal(err)
	}

	o := Options{CLI: script, Database: "/db", NoPassword: true}
	got := o.ExportAttachments("", []AttachmentRequest{{EntryPath: "/entry", Name: "key"}})
	if len(got) != 1 {
		t.Fatalf("exported %d attachments, want 1", len(got))
	}
	if string(got[AttachmentKey("/entry", "key")]) != "payload" {
		t.Fatalf("attachment = %q", got[AttachmentKey("/entry", "key")])
	}
}

func TestExportAttachmentsRejectsUnsafeArguments(t *testing.T) {
	dir := t.TempDir()
	marker := filepath.Join(dir, "ran")
	script := filepath.Join(dir, "keepassxc-cli")
	body := fmt.Sprintf("#!/bin/sh\ntouch %q\n", marker)
	if err := os.WriteFile(script, []byte(body), 0o755); err != nil {
		t.Fatal(err)
	}

	o := Options{CLI: script, Database: "/db", NoPassword: true}
	got := o.ExportAttachments("", []AttachmentRequest{{EntryPath: "/entry", Name: "bad\nname"}})
	if got != nil {
		t.Fatalf("unsafe argument returned %#v, want nil", got)
	}
	if _, err := os.Stat(marker); !os.IsNotExist(err) {
		t.Fatalf("session ran with an unrepresentable argument: %v", err)
	}
}

func TestBindFlags(t *testing.T) {
	var o Options
	fs := flag.NewFlagSet("test", flag.ContinueOnError)
	BindFlags(fs, &o)
	if err := fs.Parse([]string{
		"--database", "/db", "--keepassxc-cli", "/bin/cli", "--keyfile", "/key",
		"--yubikey", "2:1", "--no-password", "--password-command", "cmd",
		"--password-file", "/pass", "--password-env", "PASS",
	}); err != nil {
		t.Fatal(err)
	}
	want := Options{
		Database: "/db", CLI: "/bin/cli", Keyfile: "/key", Yubikey: "2:1",
		NoPassword: true, PasswordCommand: "cmd", PasswordFile: "/pass", PasswordEnv: "PASS",
	}
	if o != want {
		t.Fatalf("options = %#v, want %#v", o, want)
	}
}
