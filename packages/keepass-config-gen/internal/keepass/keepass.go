// Package keepass provides shared access to a KeePassXC database through
// keepassxc-cli. It handles unlocking, XML parsing, attachment export, and the
// small amount of text normalisation shared by config generators.
package keepass

import (
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/xml"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"unicode"
)

// Options describes how to reach and unlock a KeePassXC database.
type Options struct {
	Database        string
	CLI             string
	Keyfile         string
	Yubikey         string
	NoPassword      bool
	PasswordCommand string
	PasswordFile    string
	PasswordEnv     string
}

// DefaultCLI is the keepassxc-cli executable used when --keepassxc-cli is not
// given.
const DefaultCLI = "keepassxc-cli"

// BindFlags registers the credential and database flags shared by every
// generator. Command-specific flags stay in the caller.
func BindFlags(fs *flag.FlagSet, o *Options) {
	fs.StringVar(&o.Database, "database", "", "path to the .kdbx database")
	fs.StringVar(&o.CLI, "keepassxc-cli", DefaultCLI, "path to the keepassxc-cli binary")
	fs.StringVar(&o.Keyfile, "keyfile", "", "KeePassXC key file, if any")
	fs.StringVar(&o.Yubikey, "yubikey", "", "YubiKey/OnlyKey slot[:serial] for challenge-response")
	fs.BoolVar(&o.NoPassword, "no-password", false, "database has no master password")
	fs.StringVar(&o.PasswordCommand, "password-command", "", "command printing the master password")
	fs.StringVar(&o.PasswordFile, "password-file", "", "file containing the master password")
	fs.StringVar(&o.PasswordEnv, "password-env", "", "env var containing the master password")
}

// Entry is a parsed database entry.
type Entry struct {
	Path        string
	Title       string
	Username    string
	Password    string
	UUID        string
	Fields      map[string]string
	Attachments []string
}

var nonAlnum = regexp.MustCompile(`[^A-Za-z0-9._-]+`)

// Password returns the master password from the configured command, file, or
// environment variable, or an empty string when unlocking does not need one.
func (o Options) Password() (string, error) {
	switch {
	case o.PasswordCommand != "":
		out, err := exec.Command("sh", "-c", o.PasswordCommand).Output()
		if err != nil {
			return "", fmt.Errorf("password-command failed: %w", err)
		}
		return strings.TrimRight(string(out), "\n"), nil
	case o.PasswordFile != "":
		data, err := os.ReadFile(Expand(o.PasswordFile))
		if err != nil {
			return "", fmt.Errorf("cannot read password file: %w", err)
		}
		return strings.TrimRight(string(data), "\n"), nil
	case o.PasswordEnv != "":
		value, ok := os.LookupEnv(o.PasswordEnv)
		if !ok {
			return "", fmt.Errorf("environment variable %s is unset", o.PasswordEnv)
		}
		return value, nil
	}
	return "", nil
}

// CommonArgs are the per-command options. keepassxc-cli expects these AFTER the
// subcommand (e.g. `keepassxc-cli export -q -f xml <db>`), not before it. `-q` is
// deliberately omitted so authentication prompts and errors reach the caller.
func (o Options) CommonArgs() []string {
	var args []string
	if o.Keyfile != "" {
		args = append(args, "-k", Expand(o.Keyfile))
	}
	if o.Yubikey != "" {
		args = append(args, "-y", o.Yubikey)
	}
	if o.NoPassword {
		args = append(args, "--no-password")
	}
	return args
}

// Argv builds the keepassxc-cli argument vector as
// `<subcommand> <options> <args>`.
func (o Options) Argv(subcommand string, args ...string) []string {
	full := append([]string{subcommand}, o.CommonArgs()...)
	return append(full, args...)
}

// Run invokes `keepassxc-cli <subcommand> <options> <args>`.
func (o Options) Run(password, subcommand string, args ...string) ([]byte, error) {
	full := o.Argv(subcommand, args...)
	cmd := exec.Command(o.CLI, full...)
	// An empty password means no credential is available: inherit the terminal
	// so keepassxc-cli can prompt. Go otherwise connects the child to
	// /dev/null. Sending a blank line would only make it fail.
	switch {
	case o.NoPassword:
	case password != "":
		cmd.Stdin = strings.NewReader(password + "\n")
	default:
		cmd.Stdin = os.Stdin
	}
	var stderr strings.Builder
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("%s: %w: %s", strings.Join(full, " "), err, strings.TrimSpace(stderr.String()))
	}
	return out, nil
}

// XML schema of `keepassxc-cli export -f xml` (KeePass 2.x format).
type xmlFile struct {
	Root struct {
		Groups []xmlGroup `xml:"Group"`
	} `xml:"Root"`
}

type xmlGroup struct {
	Name    string     `xml:"Name"`
	Groups  []xmlGroup `xml:"Group"`
	Entries []xmlEntry `xml:"Entry"`
}

type xmlEntry struct {
	UUID     string      `xml:"UUID"`
	Strings  []xmlString `xml:"String"`
	Binaries []xmlBinary `xml:"Binary"`
}

type xmlString struct {
	Key   string `xml:"Key"`
	Value string `xml:"Value"`
}

type xmlBinary struct {
	Key   string `xml:"Key"`
	Value struct {
		Ref int `xml:"Ref,attr"`
	} `xml:"Value"`
}

// ParseXML parses `keepassxc-cli export -f xml` into entries. Entry paths
// exclude the root group's own name, which is what keepassxc-cli expects.
func ParseXML(data []byte) ([]Entry, error) {
	var file xmlFile
	if err := xml.Unmarshal(data, &file); err != nil {
		return nil, err
	}

	var entries []Entry
	var walk func(group xmlGroup, prefix string)
	walk = func(group xmlGroup, prefix string) {
		for _, entry := range group.Entries {
			fields := make(map[string]string, len(entry.Strings))
			for _, s := range entry.Strings {
				fields[s.Key] = s.Value
			}
			// Older generators ignored unreadable UUIDs, and SSH does not
			// need one. Expose an empty UUID instead of failing the export;
			// Remmina rejects empty UUIDs explicitly.
			uuid, err := decodeUUID(entry.UUID)
			if err != nil {
				uuid = ""
			}
			var attachments []string
			for _, b := range entry.Binaries {
				if b.Key != "" {
					attachments = append(attachments, b.Key)
				}
			}
			entries = append(entries, Entry{
				// The root group's own name is not part of an entry path.
				Path:        prefix + "/" + fields["Title"],
				Title:       fields["Title"],
				Username:    fields["UserName"],
				Password:    fields["Password"],
				UUID:        uuid,
				Fields:      fields,
				Attachments: attachments,
			})
		}
		for _, sub := range group.Groups {
			walk(sub, prefix+"/"+sub.Name)
		}
	}
	for _, group := range file.Root.Groups {
		walk(group, "")
	}
	return entries, nil
}

// decodeUUID converts the base64 UUID element of a KeePass entry to hex.
func decodeUUID(value string) (string, error) {
	value = strings.TrimSpace(value)
	if value == "" {
		return "", nil
	}
	raw, err := base64.StdEncoding.DecodeString(value)
	if err != nil {
		raw, err = base64.RawStdEncoding.DecodeString(value)
	}
	if err != nil {
		return "", fmt.Errorf("invalid entry UUID %q: %w", value, err)
	}
	if len(raw) != 16 {
		return "", fmt.Errorf("invalid entry UUID %q: got %d bytes, want 16", value, len(raw))
	}
	return hex.EncodeToString(raw), nil
}

// AttachmentRequest identifies one attachment to fetch.
type AttachmentRequest struct {
	EntryPath string
	Name      string
}

// CollectAttachmentRequests lists every attachment of the given entries, so
// they can all be fetched under a single unlock. Callers decide which entries
// are relevant before calling it.
func CollectAttachmentRequests(entries []Entry) []AttachmentRequest {
	var requests []AttachmentRequest
	for _, entry := range entries {
		for _, name := range entry.Attachments {
			requests = append(requests, AttachmentRequest{EntryPath: entry.Path, Name: name})
		}
	}
	return requests
}

// AttachmentKey identifies an exported attachment in a result map.
func AttachmentKey(entryPath, name string) string {
	return entryPath + "\x00" + name
}

// ExportAttachments unlocks the database once via `keepassxc-cli open` and
// exports every requested attachment inside that single session, so the user
// answers the challenge-response prompt once instead of once per key.
//
// It requires a non-interactive credential (password, key file, YubiKey, or no
// password) because it drives the interactive command through a pipe. An empty
// password cannot prompt for input.
func (o Options) ExportAttachments(password string, requests []AttachmentRequest) map[string][]byte {
	if len(requests) == 0 {
		return nil
	}
	// Without a non-interactive password, fall through to the per-attachment
	// Run path, which inherits the terminal. Writing a blank line here would
	// consume the prompt with an empty password.
	if !o.NoPassword && password == "" {
		return nil
	}
	dir, err := os.MkdirTemp("", "keepass-config-gen-attachments-")
	if err != nil {
		return nil
	}
	defer func() { _ = os.RemoveAll(dir) }()

	var script strings.Builder
	for i, req := range requests {
		entryPath, ok := cliArg(req.EntryPath)
		if !ok {
			return nil
		}
		name, ok := cliArg(req.Name)
		if !ok {
			return nil
		}
		destination, ok := cliArg(filepath.Join(dir, strconv.Itoa(i)))
		if !ok {
			return nil
		}
		fmt.Fprintf(&script, "attachment-export %s %s %s\n", entryPath, name, destination)
	}
	script.WriteString("exit\n")

	args := append([]string{"open"}, o.CommonArgs()...)
	args = append(args, Expand(o.Database))
	cmd := exec.Command(o.CLI, args...)
	stdin, err := cmd.StdinPipe()
	if err != nil {
		return nil
	}
	var output strings.Builder
	cmd.Stdout = &output
	cmd.Stderr = &output
	if err := cmd.Start(); err != nil {
		return nil
	}
	if !o.NoPassword {
		_, _ = io.WriteString(stdin, password+"\n")
	}
	_, _ = io.WriteString(stdin, script.String())
	_ = stdin.Close()
	_ = cmd.Wait()

	result := make(map[string][]byte, len(requests))
	for i, req := range requests {
		if data, err := os.ReadFile(filepath.Join(dir, strconv.Itoa(i))); err == nil {
			result[AttachmentKey(req.EntryPath, req.Name)] = data
		}
	}
	return result
}

// cliArg quotes an argument for keepassxc-cli's interactive line parser. The
// parser is line-based, so NUL, CR, and LF cannot be represented. It reports
// false for such values so the caller can fall back to a direct invocation.
func cliArg(value string) (string, bool) {
	if strings.ContainsAny(value, "\x00\r\n") {
		return "", false
	}
	escaped := strings.NewReplacer(`\`, `\\`, `"`, `\"`).Replace(value)
	if strings.ContainsAny(value, " \t") || strings.ContainsAny(value, `\"`) {
		return `"` + escaped + `"`, true
	}
	return escaped, true
}

// Expand resolves a leading `~` or `~/` to the user's home directory.
func Expand(path string) string {
	if path == "~" || strings.HasPrefix(path, "~/") {
		if home, err := os.UserHomeDir(); err == nil {
			return filepath.Join(home, strings.TrimPrefix(path[1:], "/"))
		}
	}
	return path
}

// Fingerprint identifies the database by modification time and size without
// reading it, so an unchanged database needs no re-authentication.
func Fingerprint(path string) (string, error) {
	info, err := os.Stat(path)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%d:%d", info.ModTime().UnixNano(), info.Size()), nil
}

// Tokenize splits a line on whitespace, honoring double quotes so option
// values may contain spaces (e.g. ProxyCommand="ssh -W %h:%p jump").
func Tokenize(line string) []string {
	var (
		tokens  []string
		current strings.Builder
		quoted  bool
	)
	flush := func() {
		if current.Len() > 0 {
			tokens = append(tokens, current.String())
			current.Reset()
		}
	}
	for _, r := range line {
		switch {
		case r == '"':
			quoted = !quoted
		case unicode.IsSpace(r) && !quoted:
			flush()
		default:
			current.WriteRune(r)
		}
	}
	flush()
	return tokens
}

// SplitList splits a comma- or newline-separated field into trimmed values.
func SplitList(value string) []string {
	var out []string
	for _, part := range strings.FieldsFunc(value, func(r rune) bool { return r == ',' || r == '\n' }) {
		if trimmed := strings.TrimSpace(part); trimmed != "" {
			out = append(out, trimmed)
		}
	}
	return out
}

// Sanitise turns a name into a safe filename component.
func Sanitise(name string) string {
	cleaned := strings.Trim(nonAlnum.ReplaceAllString(name, "_"), "_")
	if cleaned == "" {
		return "key"
	}
	return cleaned
}

// ShortHash disambiguates derived file names, since distinct entry titles can
// sanitise to the same string.
func ShortHash(value string) string {
	sum := sha256.Sum256([]byte(value))
	return fmt.Sprintf("%x", sum[:4])
}
