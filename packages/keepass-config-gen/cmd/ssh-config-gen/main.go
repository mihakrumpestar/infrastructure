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
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"unicode"

	"golang.org/x/crypto/ssh"

	"keepass-config-gen/internal/gen"
	"keepass-config-gen/internal/keepass"
	"keepass-config-gen/internal/tray"
)

const (
	defaultOutput         = "~/.ssh/config.d/keepass.conf"
	defaultIdentities     = "~/.ssh/keepass-identities"
	defaultAllowedSigners = "~/.ssh/allowed_signers"
	defaultStateFile      = "~/.local/state/ssh-config-gen/db-state"
	defaultLogFile        = "~/.local/state/ssh-config-gen/log"
	defaultGitIdentities  = "~/.config/git/keepass-identities"

	fieldSSHHosts = "ssh_hosts"
	fieldSSHHost  = "ssh-host"
	fieldSSHSign  = "ssh_sign"
)

type options struct {
	keepass.Options
	Output           string
	IdentitiesDir    string
	AllowedSigners   string
	StateFile        string
	LogFile          string
	GitIdentitiesDir string
	AgentSocket      string
	IfChanged        bool
	Check            bool
	ToStdout         bool
	Tray             bool
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

// sshHosts returns the ssh_hosts field, falling back to the legacy ssh-host
// spelling.
func sshHosts(entry keepass.Entry) string {
	if v := entry.Fields[fieldSSHHosts]; v != "" {
		return v
	}
	return entry.Fields[fieldSSHHost]
}

// sshSign returns the ssh_sign field (signing principals).
func sshSign(entry keepass.Entry) string { return entry.Fields[fieldSSHSign] }

// relevantEntry reports whether the entry opts into generation at all.
func relevantEntry(entry keepass.Entry) bool {
	return sshHosts(entry) != "" || len(keepass.SplitList(sshSign(entry))) > 0
}

// relevantEntries filters parsed entries down to the ones that opt in.
func relevantEntries(entries []keepass.Entry) []keepass.Entry {
	var relevant []keepass.Entry
	for _, entry := range entries {
		if relevantEntry(entry) {
			relevant = append(relevant, entry)
		}
	}
	return relevant
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

// stateKey folds the database path, fingerprint, and effective output options
// into one value, so a change to any of them forces regeneration.
func stateKey(o options, fingerprint string) string {
	return gen.StateKey(
		keepass.Expand(o.Database),
		fingerprint,
		keepass.Expand(o.Output),
		keepass.Expand(o.IdentitiesDir),
		keepass.Expand(o.AllowedSigners),
		keepass.Expand(o.GitIdentitiesDir),
		o.AgentSocket,
	)
}

func parseHosts(value string) []hostEntry {
	var entries []hostEntry
	for _, line := range strings.Split(value, "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		fields := keepass.Tokenize(line)
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

// derivePubkey returns the OpenSSH public key line for a private key. An
// unencrypted key is parsed directly, and the passphrase is only tried when
// that fails. An entry's Password field is not necessarily the key's passphrase
// (it may be set for an unrelated reason), and ParseRawPrivateKeyWithPassphrase
// rejects an unencrypted key outright ("ssh: key is not password protected").
// ParseRawPrivateKey reports an encrypted key with a PassphraseMissingError
// before doing any crypto, so this order is both correct and cheap.
func derivePubkey(raw []byte, passphrase string) (string, error) {
	key, err := ssh.ParseRawPrivateKey(raw)
	if err != nil && passphrase != "" {
		key, err = ssh.ParseRawPrivateKeyWithPassphrase(raw, []byte(passphrase))
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
func deriveKey(o options, password string, entry keepass.Entry, attachments map[string][]byte) (string, error) {
	if len(entry.Attachments) == 0 {
		return "", fmt.Errorf("no attachment")
	}
	var lastErr error
	for _, name := range entry.Attachments {
		raw := attachments[keepass.AttachmentKey(entry.Path, name)]
		if raw == nil {
			if data, err := o.Run(password, "attachment-export", "--stdout", keepass.Expand(o.Database), entry.Path, name); err == nil {
				raw = data
			}
		}
		if raw == nil {
			lastErr = fmt.Errorf("attachment %q not exported", name)
			continue
		}
		pub, err := derivePubkey(raw, entry.Password)
		if err != nil {
			lastErr = err
			continue
		}
		return pub, nil
	}
	return "", lastErr
}

// generatedGitIdentity reports whether path holds a generated identity file.
func generatedGitIdentity(path string) bool {
	data, err := os.ReadFile(path)
	return err == nil && strings.HasPrefix(string(data), "[user]")
}

// pruneGeneratedGitIdentities removes stale generated identity files from dir,
// leaving any other file untouched.
func pruneGeneratedGitIdentities(dir string, keep map[string]bool) error {
	return gen.PruneMatching(dir, keep, generatedGitIdentity)
}

func main() {
	var o options
	keepass.BindFlags(flag.CommandLine, &o.Options)
	flag.StringVar(&o.Output, "output", defaultOutput, "config fragment to write")
	flag.StringVar(&o.IdentitiesDir, "identities-dir", defaultIdentities, "directory for .pub files")
	flag.StringVar(&o.AllowedSigners, "allowed-signers", defaultAllowedSigners, "allowed_signers file for SSH signing (empty to skip)")
	flag.StringVar(&o.StateFile, "state-file", defaultStateFile, "file recording the last-seen database fingerprint")
	flag.StringVar(&o.LogFile, "log-file", defaultLogFile, "file for the tray's last-run log")
	flag.StringVar(&o.GitIdentitiesDir, "git-identities-dir", defaultGitIdentities, "directory for generated git identity files (empty to skip)")
	flag.BoolVar(&o.IfChanged, "if-changed", false, "skip regeneration if the database is unchanged since the last run")
	flag.StringVar(&o.AgentSocket, "agent-socket", "", "emit IdentityAgent for this socket")
	flag.BoolVar(&o.Check, "check", false, "exit 1 if the output would change")
	flag.BoolVar(&o.ToStdout, "print", false, "write to stdout only")
	flag.BoolVar(&o.Tray, "tray", false, "run the system tray (regenerate on demand)")
	flag.Parse()

	if o.Tray {
		runTray(o)
		return
	}
	if err := generate(o); err != nil {
		if errors.Is(err, gen.ErrChanged) {
			os.Exit(1)
		}
		fail("%v", err)
	}
}

// runTray wires this generator into the generic tray.
func runTray(o options) {
	// A tray refresh is explicit. Do not let --if-changed turn it into a no-op
	// when the database is unchanged but a generated file was edited or lost,
	// and never let the print/check modes suppress the refresh.
	o.IfChanged = false
	o.ToStdout = false
	o.Check = false
	tray.Run(tray.Config{
		Title:     "ssh-config-gen",
		Refresh:   func() error { return generate(o) },
		OpenPath:  keepass.Expand(o.Output),
		OpenLabel: "Open config",
		LogFile:   keepass.Expand(o.LogFile),
	})
}

// generate reads the database and writes the config fragment, public keys, and
// allowed_signers file. It is shared by the CLI and the tray.
func generate(o options) error {
	if o.Database == "" {
		return errors.New("--database is required")
	}

	databasePath := keepass.Expand(o.Database)
	statePath := keepass.Expand(o.StateFile)
	outputPath := keepass.Expand(o.Output)
	allowedSignersPath := keepass.Expand(o.AllowedSigners)
	gitIncludePath := filepath.Join(keepass.Expand(o.GitIdentitiesDir), "include.conf")

	// Cheap change check: skip before invoking keepassxc-cli so an unrelated
	// directory event never triggers re-authentication. --print and --check are
	// explicit read-only views and must still run.
	fingerprint := ""
	if o.IfChanged && !o.ToStdout && !o.Check {
		fp, err := keepass.Fingerprint(databasePath)
		if err != nil {
			return fmt.Errorf("cannot stat database: %w", err)
		}
		fingerprint = stateKey(o, fp)
		if gen.Current(statePath, fingerprint) {
			return nil
		}
	}

	writing := !o.ToStdout && !o.Check
	if writing {
		// Invalidate state before reading or exporting anything. A failure
		// anywhere below leaves no state, so the next run retries instead of
		// trusting a run that never completed.
		if err := gen.RemoveState(statePath); err != nil {
			return fmt.Errorf("cannot invalidate state file: %w", err)
		}
	}

	password, err := o.Password()
	if err != nil {
		return err
	}

	raw, err := o.Run(password, "export", "-f", "xml", databasePath)
	if err != nil {
		return fmt.Errorf("cannot read database: %w", err)
	}
	entries, err := keepass.ParseXML(raw)
	if err != nil {
		return fmt.Errorf("cannot parse database export: %w", err)
	}
	entries = relevantEntries(entries)

	// Fetch every needed attachment under a single unlock, so the
	// challenge-response prompt is answered once rather than once per key.
	attachments := o.ExportAttachments(password, keepass.CollectAttachmentRequests(entries))

	text, allowedSignersText, pubkeys, gitIdentities, skipped, incomplete, hosts, signers := render(entries, attachments, password, o)

	for _, name := range skipped {
		fmt.Fprintf(os.Stderr, "ssh-config-gen: warning: skipped %s\n", name)
	}

	if o.ToStdout {
		fmt.Print(text)
		if allowedSignersText != "" {
			fmt.Print(allowedSignersText)
		}
		return nil
	}

	if o.Check {
		current, _ := os.ReadFile(outputPath)
		if string(current) != text {
			return gen.ErrChanged
		}
		if allowedSignersPath != "" && allowedSignersText != "" {
			currentSigners, _ := os.ReadFile(allowedSignersPath)
			if string(currentSigners) != allowedSignersText {
				return gen.ErrChanged
			}
		}
		for _, key := range pubkeys {
			if data, err := os.ReadFile(key.path); err != nil || string(data) != key.content {
				return gen.ErrChanged
			}
		}
		if o.GitIdentitiesDir != "" {
			for _, identity := range gitIdentities {
				if data, err := os.ReadFile(identity.path); err != nil || string(data) != identity.content {
					return gen.ErrChanged
				}
			}
			if data, err := os.ReadFile(gitIncludePath); err != nil || string(data) != gitInclude(gitIdentities) {
				return gen.ErrChanged
			}
		}
		if err := checkStale(o, pubkeys, gitIdentities); err != nil {
			return err
		}
		return nil
	}

	if err := writeGenerated(o, outputPath, text, allowedSignersPath, allowedSignersText, pubkeys, gitIdentities); err != nil {
		return err
	}
	if fingerprint != "" && !incomplete {
		files := stateFiles(o, outputPath, allowedSignersPath, pubkeys, gitIdentities)
		if err := gen.WriteState(statePath, gen.State{Key: fingerprint, Files: files}); err != nil {
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

// stateFiles lists every file a complete run produces, so --if-changed can
// verify all of them.
func stateFiles(o options, outputPath, allowedSignersPath string, pubkeys, gitIdentities []pubkeyFile) []string {
	files := []string{outputPath}
	if allowedSignersPath != "" {
		files = append(files, allowedSignersPath)
	}
	for _, key := range pubkeys {
		files = append(files, key.path)
	}
	for _, identity := range gitIdentities {
		files = append(files, identity.path)
	}
	if o.GitIdentitiesDir != "" {
		files = append(files, filepath.Join(keepass.Expand(o.GitIdentitiesDir), "include.conf"))
	}
	return files
}

// checkStale reports drift when a normal run would prune generated files.
func checkStale(o options, pubkeys, gitIdentities []pubkeyFile) error {
	keep := make(map[string]bool, len(pubkeys))
	for _, key := range pubkeys {
		keep[key.path] = true
	}
	stale, err := gen.Stale(keepass.Expand(o.IdentitiesDir), keep, func(path string) bool {
		return strings.HasSuffix(filepath.Base(path), ".pub")
	})
	if err != nil {
		return fmt.Errorf("cannot read identities dir: %w", err)
	}
	if len(stale) > 0 {
		return gen.ErrChanged
	}

	if o.GitIdentitiesDir == "" {
		return nil
	}
	gitIdentitiesDir := keepass.Expand(o.GitIdentitiesDir)
	keepGit := make(map[string]bool, len(gitIdentities)+1)
	for _, identity := range gitIdentities {
		keepGit[identity.path] = true
	}
	keepGit[filepath.Join(gitIdentitiesDir, "include.conf")] = true
	stale, err = gen.Stale(gitIdentitiesDir, keepGit, generatedGitIdentity)
	if err != nil {
		return fmt.Errorf("cannot read git identities dir: %w", err)
	}
	if len(stale) > 0 {
		return gen.ErrChanged
	}
	return nil
}

// render turns parsed entries and their fetched attachments into the config
// fragment, the allowed_signers content, the public-key files, and the git
// identity files. It also reports the number of host blocks and signers, any
// entries that had to be skipped, and whether a key was missing. Warnings that
// do not lose a key (such as a wildcard git alias) leave the run complete.
func render(entries []keepass.Entry, attachments map[string][]byte, password string, o options) (
	text, allowedSigners string,
	pubkeys, gitIdentities []pubkeyFile,
	skipped []string,
	incomplete bool,
	hosts, signers int,
) {
	identitiesDir := keepass.Expand(o.IdentitiesDir)

	var (
		blocks     [][]string
		signerList []string
	)

	for _, entry := range entries {
		principals := keepass.SplitList(sshSign(entry))
		hostsList := parseHosts(sshHosts(entry))

		pubkeyPath := ""
		pubkey := ""
		if pub, err := deriveKey(o, password, entry, attachments); err != nil {
			skipped = append(skipped, fmt.Sprintf("%s (%v)", entry.Title, err))
			incomplete = true
		} else {
			pubkey = pub
			path := filepath.Join(identitiesDir, keepass.Sanitise(entry.Title)+"-"+keepass.ShortHash(entry.Path)+".pub")
			pubkeyPath = path
			pubkeys = append(pubkeys, pubkeyFile{path: path, content: pub + "\n"})
		}

		for _, host := range hostsList {
			switch {
			case host.explicitIdentity():
				blocks = append(blocks, buildBlock(host, "", o.AgentSocket))
			case pubkeyPath == "":
				skipped = append(
					skipped,
					fmt.Sprintf("%s (host %s: no key derived)", entry.Title, strings.Join(host.patterns, ",")),
				)
				incomplete = true
				continue
			default:
				blocks = append(blocks, buildBlock(host, pubkeyPath, o.AgentSocket))
			}

			// A git identity is emitted for a signing entry (ssh_sign) whose
			// host line carries git.email.
			if host.gitEmail == "" || len(principals) == 0 || pubkey == "" {
				continue
			}
			name := host.patterns[0]
			if !validIdentityFilename(name) {
				skipped = append(
					skipped,
					fmt.Sprintf(
						"%s (host %s: git identity requires a safe filename)",
						entry.Title, name,
					),
				)
				continue
			}
			// git appends the remote host and command to core.sshCommand, so it
			// cannot select an SSH host. Identity selection is keyed on the
			// remote alias through the generated include.conf instead.
			gitIdentities = append(gitIdentities, pubkeyFile{
				path: filepath.Join(keepass.Expand(o.GitIdentitiesDir), name),
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
	builder.WriteString("# Source: " + o.Database + "\n")
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

	return text, allowedSigners, pubkeys, gitIdentities, skipped, incomplete, len(blocks), len(signerList)
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

// validIdentityFilename reports whether name is a safe literal host alias and
// single filename inside the git identities directory. It must not escape the
// directory, overwrite the generated include file, or make the includeIf
// pattern ambiguous.
func validIdentityFilename(name string) bool {
	if name == "" || name == "." || name == ".." || name == "include.conf" {
		return false
	}
	if filepath.Base(name) != name {
		return false
	}
	const forbidden = "/\\*?[]!:\"#; "
	for _, r := range name {
		if unicode.IsControl(r) || strings.ContainsRune(forbidden, r) {
			return false
		}
	}
	return true
}

// writeGenerated writes the config fragment, public keys, allowed_signers, and
// git identity files, pruning stale files from the generated directories.
func writeGenerated(o options, outputPath, text, allowedSignersPath, allowedSignersText string, pubkeys, gitIdentities []pubkeyFile) error {
	identitiesDir := keepass.Expand(o.IdentitiesDir)
	if err := os.MkdirAll(identitiesDir, 0o700); err != nil {
		return fmt.Errorf("cannot create identities dir: %w", err)
	}
	keep := make(map[string]bool, len(pubkeys))
	for _, key := range pubkeys {
		if err := gen.AtomicWrite(key.path, key.content, 0o644); err != nil {
			return fmt.Errorf("cannot write %s: %w", key.path, err)
		}
		keep[key.path] = true
	}
	if err := gen.PruneDir(identitiesDir, keep, ".pub"); err != nil {
		return fmt.Errorf("cannot prune identities dir: %w", err)
	}

	if o.GitIdentitiesDir != "" {
		gitIdentitiesDir := keepass.Expand(o.GitIdentitiesDir)
		if err := os.MkdirAll(gitIdentitiesDir, 0o755); err != nil {
			return fmt.Errorf("cannot create git identities dir: %w", err)
		}
		keepGit := make(map[string]bool, len(gitIdentities)+1)
		for _, identity := range gitIdentities {
			if err := gen.AtomicWrite(identity.path, identity.content, 0o644); err != nil {
				return fmt.Errorf("cannot write %s: %w", identity.path, err)
			}
			keepGit[identity.path] = true
		}
		includePath := filepath.Join(gitIdentitiesDir, "include.conf")
		if err := gen.AtomicWrite(includePath, gitInclude(gitIdentities), 0o644); err != nil {
			return fmt.Errorf("cannot write %s: %w", includePath, err)
		}
		keepGit[includePath] = true
		if err := pruneGeneratedGitIdentities(gitIdentitiesDir, keepGit); err != nil {
			return fmt.Errorf("cannot prune git identities dir: %w", err)
		}
	}

	if err := gen.AtomicWrite(outputPath, text, 0o644); err != nil {
		return fmt.Errorf("cannot write %s: %w", outputPath, err)
	}
	if allowedSignersPath != "" {
		if err := gen.AtomicWrite(allowedSignersPath, allowedSignersText, 0o644); err != nil {
			return fmt.Errorf("cannot write %s: %w", allowedSignersPath, err)
		}
	}
	return nil
}
