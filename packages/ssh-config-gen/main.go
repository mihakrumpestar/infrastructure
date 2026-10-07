// Command ssh-config-gen generates an OpenSSH client config fragment and an
// allowed_signers file from a KeePassXC database. KeePassXC stays the single
// source of truth.
//
// The database is read through keepassxc-cli, which supports password, key
// file, and YubiKey/OnlyKey challenge-response unlocking. Entry metadata and
// custom fields come from `keepassxc-cli export -f xml`; private-key
// attachments are fetched individually with `attachment-export` because the
// XML export omits KDBX4 binaries.
//
// Entries opt in with a custom string field `ssh_hosts` (one host per line)
// and/or `ssh_sign` (signing principals). `ssh_hosts` lines are a Host
// pattern (or comma-separated patterns) followed by optional `Directive=Value`
// pairs, using OpenSSH directive names:
//
//	ssh_hosts:
//	  workstation HostName=192.0.2.10 Port=2200 User=admin
//	  git.example.com,git-alt HostName=git.example.com Port=443 User=git
//	  *.prod.example.com User=deploy ProxyJump=bastion
//	ssh_sign:
//	  me@example.com
//
// The public key is derived from the entry's private-key attachment and
// written next to the config so IdentityFile can select it from the
// ssh-agent. Private key material is never written to disk. If a line sets
// IdentityFile explicitly, that is used and no key is derived.
package main

import (
	"crypto/sha256"
	"encoding/xml"
	"errors"
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

	"golang.org/x/crypto/ssh"
)

const (
	defaultOutput         = "~/.ssh/config.d/keepass.conf"
	defaultIdentities     = "~/.ssh/keepass-identities"
	defaultAllowedSigners = "~/.ssh/allowed_signers"
	defaultStateFile      = "~/.local/state/ssh-config-gen/db-state"
	defaultLogFile        = "~/.local/state/ssh-config-gen/log"
	defaultGitIdentities  = "~/.config/git/keepass-identities"
	defaultCli            = "keepassxc-cli"

	fieldSSHHosts = "ssh_hosts"
	fieldSSHHost  = "ssh-host"
	fieldSSHSign  = "ssh_sign"
	fieldTitle    = "Title"
	fieldPassword = "Password"
)

var (
	nonAlnum   = regexp.MustCompile(`[^A-Za-z0-9._-]+`)
	errChanged = errors.New("output would change")
)

type options struct {
	database         string
	cli              string
	keyfile          string
	yubikey          string
	noPassword       bool
	passwordCommand  string
	passwordFile     string
	passwordEnv      string
	output           string
	identitiesDir    string
	allowedSigners   string
	stateFile        string
	logFile          string
	gitIdentitiesDir string
	agentSocket      string
	ifChanged        bool
	check            bool
	toStdout         bool
	tray             bool
}

// hostEntry is one line of the ssh_hosts field. gitName/gitEmail come from the
// non-OpenSSH `git.name` / `git.email` keys on that line and drive a per-line
// git identity file.
type hostEntry struct {
	patterns []string
	options  [][2]string
	gitName  string
	gitEmail string
}

func (h hostEntry) explicitIdentity() bool {
	for _, option := range h.options {
		if strings.EqualFold(option[0], "identityfile") {
			return true
		}
	}
	return false
}

// vaultEntry is a parsed database entry.
type vaultEntry struct {
	path        string
	title       string
	password    string
	fields      map[string]string
	attachments []string
}

// sshHosts returns the ssh_hosts field, falling back to the legacy ssh-host
// spelling.
func (e vaultEntry) sshHosts() string {
	if v := e.fields[fieldSSHHosts]; v != "" {
		return v
	}
	return e.fields[fieldSSHHost]
}

// sshSign returns the ssh_sign field (signing principals).
func (e vaultEntry) sshSign() string { return e.fields[fieldSSHSign] }

// relevant reports whether the entry opts into generation at all.
func (e vaultEntry) relevant() bool {
	return e.sshHosts() != "" || len(splitList(e.sshSign())) > 0
}

// pubkeyFile is one generated file: a derived public key or a git identity.
type pubkeyFile struct {
	path    string
	content string
}

func fail(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "ssh-config-gen: "+format+"\n", args...)
	os.Exit(1)
}

func expand(path string) string {
	if path == "~" || strings.HasPrefix(path, "~/") {
		if home, err := os.UserHomeDir(); err == nil {
			return filepath.Join(home, strings.TrimPrefix(path[1:], "/"))
		}
	}
	return path
}

// dbFingerprint identifies the database by modification time and size without
// reading it, so an unchanged database needs no re-authentication.
func dbFingerprint(path string) (string, error) {
	info, err := os.Stat(path)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%d:%d", info.ModTime().UnixNano(), info.Size()), nil
}

func fileExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && !info.IsDir()
}

// stateKey folds the database fingerprint and the effective output options into
// one value, so a change to either forces regeneration.
func stateKey(o options, fingerprint string) string {
	sum := sha256.Sum256([]byte(strings.Join([]string{
		fingerprint,
		expand(o.output),
		expand(o.identitiesDir),
		expand(o.allowedSigners),
		expand(o.gitIdentitiesDir),
		o.agentSocket,
	}, "\x00")))
	return fmt.Sprintf("%x", sum)
}

func (o options) password() (string, error) {
	switch {
	case o.passwordCommand != "":
		out, err := exec.Command("sh", "-c", o.passwordCommand).Output()
		if err != nil {
			return "", fmt.Errorf("password-command failed: %w", err)
		}
		return strings.TrimRight(string(out), "\n"), nil
	case o.passwordFile != "":
		data, err := os.ReadFile(expand(o.passwordFile))
		if err != nil {
			return "", fmt.Errorf("cannot read password file: %w", err)
		}
		return strings.TrimRight(string(data), "\n"), nil
	case o.passwordEnv != "":
		value, ok := os.LookupEnv(o.passwordEnv)
		if !ok {
			return "", fmt.Errorf("environment variable %s is unset", o.passwordEnv)
		}
		return value, nil
	}
	return "", nil
}

// commonArgs are the per-command options. keepassxc-cli expects these AFTER the
// subcommand (e.g. `keepassxc-cli export -q -f xml <db>`), not before it. `-q` is
// deliberately omitted so authentication prompts and errors reach the caller.
func (o options) commonArgs() []string {
	var args []string
	if o.keyfile != "" {
		args = append(args, "-k", expand(o.keyfile))
	}
	if o.yubikey != "" {
		args = append(args, "-y", o.yubikey)
	}
	if o.noPassword {
		args = append(args, "--no-password")
	}
	return args
}

// argv builds the keepassxc-cli argument vector as
// `<subcommand> <options> <args>`.
func (o options) argv(subcommand string, args ...string) []string {
	full := append([]string{subcommand}, o.commonArgs()...)
	return append(full, args...)
}

// run invokes `keepassxc-cli <subcommand> <options> <args>`.
func (o options) run(password, subcommand string, args ...string) ([]byte, error) {
	full := o.argv(subcommand, args...)
	cmd := exec.Command(o.cli, full...)
	if !o.noPassword {
		cmd.Stdin = strings.NewReader(password + "\n")
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

func parseXML(data []byte) ([]vaultEntry, error) {
	var file xmlFile
	if err := xml.Unmarshal(data, &file); err != nil {
		return nil, err
	}

	var entries []vaultEntry
	var walk func(group xmlGroup, prefix string)
	walk = func(group xmlGroup, prefix string) {
		for _, entry := range group.Entries {
			fields := make(map[string]string, len(entry.Strings))
			for _, s := range entry.Strings {
				fields[s.Key] = s.Value
			}
			var attachments []string
			for _, b := range entry.Binaries {
				if b.Key != "" {
					attachments = append(attachments, b.Key)
				}
			}
			entries = append(entries, vaultEntry{
				// The root group's own name is not part of an entry path.
				path:        prefix + "/" + fields[fieldTitle],
				title:       fields[fieldTitle],
				password:    fields[fieldPassword],
				fields:      fields,
				attachments: attachments,
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

// tokenize splits a line on whitespace, honoring double quotes so option
// values may contain spaces (e.g. ProxyCommand="ssh -W %h:%p jump").
func tokenize(line string) []string {
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

func parseHosts(value string) []hostEntry {
	var entries []hostEntry
	for _, line := range strings.Split(value, "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		fields := tokenize(line)
		if len(fields) == 0 {
			continue
		}
		entry := hostEntry{}
		for _, pattern := range strings.Split(fields[0], ",") {
			if pattern = strings.TrimSpace(pattern); pattern != "" {
				entry.patterns = append(entry.patterns, pattern)
			}
		}
		for _, field := range fields[1:] {
			key, val, ok := strings.Cut(field, "=")
			if !ok {
				continue
			}
			switch key {
			case "git.name", "git-name":
				entry.gitName = val
			case "git.email", "git-email":
				entry.gitEmail = val
			default:
				entry.options = append(entry.options, [2]string{key, val})
			}
		}
		if len(entry.patterns) > 0 {
			entries = append(entries, entry)
		}
	}
	return entries
}

// splitList splits a comma- or newline-separated field into trimmed values.
func splitList(value string) []string {
	var out []string
	for _, part := range strings.FieldsFunc(value, func(r rune) bool { return r == ',' || r == '\n' }) {
		if trimmed := strings.TrimSpace(part); trimmed != "" {
			out = append(out, trimmed)
		}
	}
	return out
}

func derivePubkey(raw []byte, passphrase string) (string, error) {
	var (
		key any
		err error
	)
	if passphrase != "" {
		key, err = ssh.ParseRawPrivateKeyWithPassphrase(raw, []byte(passphrase))
	} else {
		key, err = ssh.ParseRawPrivateKey(raw)
	}
	if err != nil {
		return "", err
	}
	signer, err := ssh.NewSignerFromKey(key)
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(ssh.MarshalAuthorizedKey(signer.PublicKey()))), nil
}

func sanitise(name string) string {
	cleaned := strings.Trim(nonAlnum.ReplaceAllString(name, "_"), "_")
	if cleaned == "" {
		return "key"
	}
	return cleaned
}

// shortHash disambiguates derived file names, since distinct entry titles can
// sanitise to the same string.
func shortHash(value string) string {
	sum := sha256.Sum256([]byte(value))
	return fmt.Sprintf("%x", sum[:4])
}

func buildBlock(entry hostEntry, pubkeyPath, agentSocket string) []string {
	lines := []string{"Host " + strings.Join(entry.patterns, " ")}
	for _, option := range entry.options {
		lines = append(lines, "    "+option[0]+" "+option[1])
	}
	if pubkeyPath != "" {
		lines = append(lines, "    IdentityFile "+pubkeyPath)
	}
	if agentSocket != "" {
		lines = append(lines, "    IdentityAgent "+agentSocket)
	}
	lines = append(lines, "    IdentitiesOnly yes")
	return lines
}

// deriveKey returns the OpenSSH public key line for an entry, using the
// attachments fetched for it (keyed by entry path + attachment name) and
// falling back to a per-attachment export if the session missed one.
func deriveKey(o options, password string, entry vaultEntry, attachments map[string][]byte) (string, error) {
	if len(entry.attachments) == 0 {
		return "", fmt.Errorf("no attachment")
	}
	var lastErr error
	for _, name := range entry.attachments {
		raw := attachments[attachmentKey(entry.path, name)]
		if raw == nil {
			if data, err := o.run(password, "attachment-export", "--stdout", expand(o.database), entry.path, name); err == nil {
				raw = data
			}
		}
		if raw == nil {
			lastErr = fmt.Errorf("attachment %q not exported", name)
			continue
		}
		pub, err := derivePubkey(raw, entry.password)
		if err != nil {
			lastErr = err
			continue
		}
		return pub, nil
	}
	return "", lastErr
}

func attachmentKey(entryPath, name string) string {
	return entryPath + "\x00" + name
}

// attachmentRequest identifies one attachment to fetch.
type attachmentRequest struct {
	entry string
	name  string
}

// collectAttachmentRequests lists the attachments of every relevant entry, so
// they can all be fetched under a single unlock.
func collectAttachmentRequests(entries []vaultEntry) []attachmentRequest {
	var requests []attachmentRequest
	for _, entry := range entries {
		if !entry.relevant() {
			continue
		}
		for _, name := range entry.attachments {
			requests = append(requests, attachmentRequest{entry: entry.path, name: name})
		}
	}
	return requests
}

// exportAttachments unlocks the database once via `keepassxc-cli open` and
// exports every requested attachment inside that single session, so the user
// answers the challenge-response prompt once instead of once per key.
func (o options) exportAttachments(password string, requests []attachmentRequest) map[string][]byte {
	if len(requests) == 0 {
		return nil
	}
	dir, err := os.MkdirTemp("", "ssh-config-gen-attachments-")
	if err != nil {
		return nil
	}
	defer os.RemoveAll(dir)

	var script strings.Builder
	for i, req := range requests {
		fmt.Fprintf(
			&script,
			"attachment-export %s %s %s\n",
			cliArg(req.entry),
			cliArg(req.name),
			cliArg(filepath.Join(dir, strconv.Itoa(i))),
		)
	}
	script.WriteString("exit\n")

	args := append([]string{"open"}, o.commonArgs()...)
	args = append(args, expand(o.database))
	cmd := exec.Command(o.cli, args...)
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
	if !o.noPassword {
		_, _ = io.WriteString(stdin, password+"\n")
	}
	_, _ = io.WriteString(stdin, script.String())
	_ = stdin.Close()
	_ = cmd.Wait()

	result := make(map[string][]byte, len(requests))
	for i, req := range requests {
		if data, err := os.ReadFile(filepath.Join(dir, strconv.Itoa(i))); err == nil {
			result[attachmentKey(req.entry, req.name)] = data
		}
	}
	return result
}

// cliArg quotes an argument for keepassxc-cli's interactive line parser.
func cliArg(value string) string {
	if strings.ContainsAny(value, " \"") {
		return `"` + strings.ReplaceAll(value, `"`, `\"`) + `"`
	}
	return value
}

// pruneDir removes files with the given suffix that are no longer produced, so
// a generated directory always matches the current database.
func pruneDir(dir string, keep map[string]bool, suffix string) error {
	entries, err := os.ReadDir(dir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), suffix) {
			continue
		}
		path := filepath.Join(dir, entry.Name())
		if keep[path] {
			continue
		}
		if err := os.Remove(path); err != nil {
			return err
		}
	}
	return nil
}

// pruneGeneratedGitIdentities removes stale generated identity files (which
// start with "[user]") from dir, leaving any other file untouched.
func pruneGeneratedGitIdentities(dir string, keep map[string]bool) error {
	entries, err := os.ReadDir(dir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		path := filepath.Join(dir, entry.Name())
		if keep[path] {
			continue
		}
		data, err := os.ReadFile(path)
		if err != nil || !strings.HasPrefix(string(data), "[user]") {
			continue
		}
		if err := os.Remove(path); err != nil {
			return err
		}
	}
	return nil
}

func atomicWrite(path, content string) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(filepath.Dir(path), ".ssh-config-gen-*")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	if _, err := tmp.WriteString(content); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	if err := os.Chmod(tmp.Name(), 0o644); err != nil {
		return err
	}
	return os.Rename(tmp.Name(), path)
}

func main() {
	var o options
	flag.StringVar(&o.database, "database", "", "path to the .kdbx database")
	flag.StringVar(&o.cli, "keepassxc-cli", defaultCli, "path to the keepassxc-cli binary")
	flag.StringVar(&o.keyfile, "keyfile", "", "KeePassXC key file, if any")
	flag.StringVar(&o.yubikey, "yubikey", "", "YubiKey/OnlyKey slot[:serial] for challenge-response")
	flag.BoolVar(&o.noPassword, "no-password", false, "database has no master password")
	flag.StringVar(&o.passwordCommand, "password-command", "", "command printing the master password")
	flag.StringVar(&o.passwordFile, "password-file", "", "file containing the master password")
	flag.StringVar(&o.passwordEnv, "password-env", "", "env var containing the master password")
	flag.StringVar(&o.output, "output", defaultOutput, "config fragment to write")
	flag.StringVar(&o.identitiesDir, "identities-dir", defaultIdentities, "directory for .pub files")
	flag.StringVar(&o.allowedSigners, "allowed-signers", defaultAllowedSigners, "allowed_signers file for SSH signing (empty to skip)")
	flag.StringVar(&o.stateFile, "state-file", defaultStateFile, "file recording the last-seen database fingerprint")
	flag.StringVar(&o.logFile, "log-file", defaultLogFile, "file for the tray's last-run log")
	flag.StringVar(&o.gitIdentitiesDir, "git-identities-dir", defaultGitIdentities, "directory for generated git identity files (empty to skip)")
	flag.BoolVar(&o.ifChanged, "if-changed", false, "skip regeneration if the database is unchanged since the last run")
	flag.StringVar(&o.agentSocket, "agent-socket", "", "emit IdentityAgent for this socket")
	flag.BoolVar(&o.check, "check", false, "exit 1 if the output would change")
	flag.BoolVar(&o.toStdout, "print", false, "write to stdout only")
	flag.BoolVar(&o.tray, "tray", false, "run the system tray (regenerate on demand)")
	flag.Parse()

	if o.tray {
		runTray(o)
		return
	}
	if err := generate(o); err != nil {
		if errors.Is(err, errChanged) {
			os.Exit(1)
		}
		fail("%v", err)
	}
}

// generate reads the database and writes the config fragment, public keys, and
// allowed_signers file. It is shared by the CLI and the tray.
func generate(o options) error {
	if o.database == "" {
		return errors.New("--database is required")
	}

	databasePath := expand(o.database)
	statePath := expand(o.stateFile)
	outputPath := expand(o.output)
	allowedSignersPath := expand(o.allowedSigners)
	gitIncludePath := filepath.Join(expand(o.gitIdentitiesDir), "include.conf")

	// Cheap change check: skip before invoking keepassxc-cli so an unrelated
	// directory event never triggers re-authentication.
	fingerprint := ""
	if o.ifChanged {
		fp, err := dbFingerprint(databasePath)
		if err != nil {
			return fmt.Errorf("cannot stat database: %w", err)
		}
		fingerprint = stateKey(o, fp)
		if current, err := os.ReadFile(statePath); err == nil &&
			strings.TrimSpace(string(current)) == fingerprint &&
			fileExists(outputPath) &&
			(o.gitIdentitiesDir == "" || fileExists(gitIncludePath)) {
			return nil
		}
	}

	password, err := o.password()
	if err != nil {
		return err
	}

	raw, err := o.run(password, "export", "-f", "xml", databasePath)
	if err != nil {
		return fmt.Errorf("cannot read database: %w", err)
	}
	entries, err := parseXML(raw)
	if err != nil {
		return fmt.Errorf("cannot parse database export: %w", err)
	}

	// Fetch every needed attachment under a single unlock, so the
	// challenge-response prompt is answered once rather than once per key.
	attachments := o.exportAttachments(password, collectAttachmentRequests(entries))

	text, allowedSignersText, pubkeys, gitIdentities, skipped, hosts, signers := render(entries, attachments, password, o)

	for _, name := range skipped {
		fmt.Fprintf(os.Stderr, "ssh-config-gen: warning: skipped %s\n", name)
	}

	if o.toStdout {
		fmt.Print(text)
		if allowedSignersText != "" {
			fmt.Print(allowedSignersText)
		}
		return nil
	}

	if o.check {
		current, _ := os.ReadFile(outputPath)
		if string(current) != text {
			return errChanged
		}
		if allowedSignersPath != "" && allowedSignersText != "" {
			currentSigners, _ := os.ReadFile(allowedSignersPath)
			if string(currentSigners) != allowedSignersText {
				return errChanged
			}
		}
		for _, key := range pubkeys {
			if data, err := os.ReadFile(key.path); err != nil || string(data) != key.content {
				return errChanged
			}
		}
		if o.gitIdentitiesDir != "" {
			for _, identity := range gitIdentities {
				if data, err := os.ReadFile(identity.path); err != nil || string(data) != identity.content {
					return errChanged
				}
			}
			if data, err := os.ReadFile(gitIncludePath); err != nil || string(data) != gitInclude(gitIdentities) {
				return errChanged
			}
		}
		return nil
	}

	if err := writeGenerated(o, outputPath, text, allowedSignersPath, allowedSignersText, pubkeys, gitIdentities); err != nil {
		return err
	}
	if o.ifChanged && fingerprint != "" {
		if err := atomicWrite(statePath, fingerprint+"\n"); err != nil {
			return fmt.Errorf("cannot write state file: %w", err)
		}
	}
	fmt.Fprintf(
		os.Stderr,
		"ssh-config-gen: wrote %s (%d hosts, %d public keys, %d signers, %d git identities)\n",
		outputPath, hosts, len(pubkeys), signers, len(gitIdentities),
	)
	return nil
}

// render turns parsed entries and their fetched attachments into the config
// fragment, the allowed_signers content, the public-key files, and the git
// identity files. It also reports the number of host blocks and signers and any
// entries that had to be skipped.
func render(entries []vaultEntry, attachments map[string][]byte, password string, o options) (
	text, allowedSigners string,
	pubkeys, gitIdentities []pubkeyFile,
	skipped []string,
	hosts, signers int,
) {
	identitiesDir := expand(o.identitiesDir)

	var (
		blocks     [][]string
		signerList []string
	)

	for _, entry := range entries {
		if !entry.relevant() {
			continue
		}
		principals := splitList(entry.sshSign())
		hostsList := parseHosts(entry.sshHosts())

		pubkeyPath := ""
		pubkey := ""
		if pub, err := deriveKey(o, password, entry, attachments); err != nil {
			skipped = append(skipped, fmt.Sprintf("%s (%v)", entry.title, err))
		} else {
			pubkey = pub
			path := filepath.Join(identitiesDir, sanitise(entry.title)+"-"+shortHash(entry.path)+".pub")
			pubkeyPath = path
			pubkeys = append(pubkeys, pubkeyFile{path: path, content: pub + "\n"})
		}

		for _, host := range hostsList {
			switch {
			case host.explicitIdentity():
				blocks = append(blocks, buildBlock(host, "", o.agentSocket))
			case pubkeyPath == "":
				skipped = append(
					skipped,
					fmt.Sprintf("%s (host %s: no key derived)", entry.title, strings.Join(host.patterns, ",")),
				)
				continue
			default:
				blocks = append(blocks, buildBlock(host, pubkeyPath, o.agentSocket))
			}

			// A git identity is emitted for a signing entry (ssh_sign) whose
			// host line carries git.email.
			if host.gitEmail == "" || len(principals) == 0 || pubkey == "" {
				continue
			}
			name := host.patterns[0]
			if !literalHostAlias(name) {
				skipped = append(
					skipped,
					fmt.Sprintf("%s (host %s: git identity requires a literal host alias)", entry.title, name),
				)
				continue
			}
			// git appends the remote host and command to core.sshCommand, so it
			// cannot select an SSH host. Identity selection is keyed on the
			// remote alias through the generated include.conf instead.
			gitIdentities = append(gitIdentities, pubkeyFile{
				path: filepath.Join(expand(o.gitIdentitiesDir), name),
				content: fmt.Sprintf(
					"[user]\n  name = %s\n  email = %s\n  signingkey = %s\n",
					host.gitName,
					host.gitEmail,
					pubkey,
				),
			})
		}

		for _, principal := range principals {
			if pubkey != "" {
				signerList = append(signerList, fmt.Sprintf("%s namespaces=\"git\" %s", principal, pubkey))
			}
		}
	}

	var builder strings.Builder
	builder.WriteString("# Generated by ssh-config-gen. Do not edit by hand.\n")
	builder.WriteString("# Source: " + o.database + "\n")
	for _, block := range blocks {
		builder.WriteString("\n")
		for _, line := range block {
			builder.WriteString(line + "\n")
		}
	}
	text = builder.String()

	allowedSigners = "# Generated by ssh-config-gen. Do not edit by hand.\n"
	if len(signerList) > 0 {
		allowedSigners += strings.Join(signerList, "\n") + "\n"
	}

	return text, allowedSigners, pubkeys, gitIdentities, skipped, len(blocks), len(signerList)
}

// gitInclude renders the includeIf fragment that applies each generated git
// identity to repositories whose remote uses the matching SSH alias, e.g.
// git@github-personal:owner/repo.git. git appends the remote host to
// core.sshCommand, so the alias cannot be selected there; keying on the remote
// URL is the supported way. `*@` matches any SSH user, `**/**` matches two or
// more path components (e.g. owner/repo, group/sub/repo) and `*` covers a
// single component; an scp-like URL cannot use a lone `**` after `:` because
// the colon is not a path separator.
func gitInclude(identities []pubkeyFile) string {
	var b strings.Builder
	b.WriteString("# Generated by ssh-config-gen. Do not edit by hand.\n")
	for _, id := range identities {
		alias := filepath.Base(id.path)
		fmt.Fprintf(&b, "\n[includeIf \"hasconfig:remote.*.url:*@%s:**/**\"]\n    path = %s\n", alias, id.path)
		fmt.Fprintf(&b, "[includeIf \"hasconfig:remote.*.url:*@%s:*\"]\n    path = %s\n", alias, id.path)
	}
	return b.String()
}

// literalHostAlias reports whether name is a literal SSH host alias, i.e. not a
// wildcard pattern that would make a generated git identity ambiguous.
func literalHostAlias(name string) bool {
	return name != "" && !strings.ContainsAny(name, "*?[]!: \t")
}

// writeGenerated writes the config fragment, public keys, allowed_signers, and
// git identity files, pruning stale files from the generated directories.
func writeGenerated(o options, outputPath, text, allowedSignersPath, allowedSignersText string, pubkeys, gitIdentities []pubkeyFile) error {
	identitiesDir := expand(o.identitiesDir)
	if err := os.MkdirAll(identitiesDir, 0o700); err != nil {
		return fmt.Errorf("cannot create identities dir: %w", err)
	}
	keep := make(map[string]bool, len(pubkeys))
	for _, key := range pubkeys {
		if err := atomicWrite(key.path, key.content); err != nil {
			return fmt.Errorf("cannot write %s: %w", key.path, err)
		}
		keep[key.path] = true
	}
	if err := pruneDir(identitiesDir, keep, ".pub"); err != nil {
		return fmt.Errorf("cannot prune identities dir: %w", err)
	}

	if o.gitIdentitiesDir != "" {
		gitIdentitiesDir := expand(o.gitIdentitiesDir)
		if err := os.MkdirAll(gitIdentitiesDir, 0o755); err != nil {
			return fmt.Errorf("cannot create git identities dir: %w", err)
		}
		keepGit := make(map[string]bool, len(gitIdentities)+1)
		for _, identity := range gitIdentities {
			if err := atomicWrite(identity.path, identity.content); err != nil {
				return fmt.Errorf("cannot write %s: %w", identity.path, err)
			}
			keepGit[identity.path] = true
		}
		includePath := filepath.Join(gitIdentitiesDir, "include.conf")
		if err := atomicWrite(includePath, gitInclude(gitIdentities)); err != nil {
			return fmt.Errorf("cannot write %s: %w", includePath, err)
		}
		keepGit[includePath] = true
		if err := pruneGeneratedGitIdentities(gitIdentitiesDir, keepGit); err != nil {
			return fmt.Errorf("cannot prune git identities dir: %w", err)
		}
	}

	if err := atomicWrite(outputPath, text); err != nil {
		return fmt.Errorf("cannot write %s: %w", outputPath, err)
	}
	if allowedSignersPath != "" {
		if err := atomicWrite(allowedSignersPath, allowedSignersText); err != nil {
			return fmt.Errorf("cannot write %s: %w", allowedSignersPath, err)
		}
	}
	return nil
}
