// Command gh-config-gen keeps GitHub CLI account metadata in sync with the
// tokens already present in the Secret Service.
//
// `gh` decides which accounts exist by reading ~/.config/gh/hosts.yml; the
// token itself comes from the keyring, keyed by host and username. A machine
// that shares a KeePassXC database therefore holds valid tokens but still
// reports "not logged in", because the file never names the account. This
// command rebuilds hosts.yml from the keyring, so signing in once signs in on
// every machine the keyring reaches.
//
// It never reads or writes a token: the keyring is only enumerated for the
// `service` and `username` attributes. The active account is taken from the
// existing file, which already records it.
package main

import (
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"

	"keepass-config-gen/internal/gen"
	"keepass-config-gen/internal/ghauth"
	"keepass-config-gen/internal/keepass"
	"keepass-config-gen/internal/secretservice"
	"keepass-config-gen/internal/tray"
)

const (
	defaultOutput  = "~/.config/gh/hosts.yml"
	defaultLogFile = "~/.local/state/gh-config-gen/log"

	// gh keys each credential as ("gh:<host>", "<username>"), plus an extra
	// ("gh:<host>", "") slot holding the token of the active account.
	servicePrefix = "gh:"

	attributeService  = "service"
	attributeUsername = "username"
)

type options struct {
	Output   string
	LogFile  string
	Check    bool
	ToStdout bool
	Tray     bool
}

func (o *options) applyDefaults() {
	if o.Output == "" {
		o.Output = defaultOutput
	}
	if o.LogFile == "" {
		o.LogFile = defaultLogFile
	}
}

func fail(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "gh-config-gen: "+format+"\n", args...)
	os.Exit(1)
}

func warn(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "gh-config-gen: warning: "+format+"\n", args...)
}

func main() {
	var o options
	flag.StringVar(&o.Output, "output", defaultOutput, "gh hosts file to reconcile")
	flag.StringVar(&o.LogFile, "log-file", defaultLogFile, "file for the tray's last-run log")
	flag.BoolVar(&o.Check, "check", false, "exit 1 if the hosts file would change")
	flag.BoolVar(&o.ToStdout, "print", false, "write to stdout only")
	flag.BoolVar(&o.Tray, "tray", false, "run the system tray (reconcile on demand)")
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

func runTray(o options) {
	o.applyDefaults()
	// A tray refresh is explicit, so the read-only modes must not suppress it.
	o.ToStdout = false
	o.Check = false
	tray.Run(tray.Config{
		Title:     "gh-config-gen",
		Refresh:   func() error { return generate(o) },
		OpenPath:  filepath.Dir(keepass.Expand(o.Output)),
		OpenLabel: "Open gh config",
		LogFile:   keepass.Expand(o.LogFile),
	})
}

func generate(o options) error {
	return generateWith(o, enumerate)
}

// generateWith is generate with an injectable account source, so the whole
// pipeline is testable without a keyring.
func generateWith(o options, source func() ([]ghauth.Account, error)) error {
	o.applyDefaults()
	outputPath := keepass.Expand(o.Output)

	accounts, err := source()
	if err != nil {
		// A locked or absent keyring says nothing about the file on disk.
		// Leave it alone: rewriting it would log the user out for real. The
		// timer retries, so a slow KeePassXC start heals itself.
		warn("%v", err)
		return nil
	}

	existing, err := os.ReadFile(outputPath)
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		// The file holds account metadata only, so a missing one is normal.
		return fmt.Errorf("cannot read %s: %w", outputPath, err)
	}

	out, changed, guessed, err := ghauth.Reconcile(existing, accounts)
	if err != nil {
		return fmt.Errorf("cannot reconcile %s: %w", outputPath, err)
	}
	for _, host := range guessed {
		warn("%s has several accounts and no active one recorded; kept the first", host)
	}

	if o.ToStdout {
		fmt.Print(string(out))
		return nil
	}
	if o.Check {
		if changed {
			return gen.ErrChanged
		}
		return nil
	}
	if !changed {
		return nil
	}
	if err := gen.AtomicWrite(outputPath, string(out), 0o600); err != nil {
		return fmt.Errorf("cannot write %s: %w", outputPath, err)
	}

	counts := make(map[string]int)
	for _, account := range accounts {
		counts[account.Host]++
	}
	for _, host := range sortedKeys(counts) {
		fmt.Fprintf(os.Stderr, "gh-config-gen: %s: %d account(s)\n", host, counts[host])
	}
	return nil
}

// enumerate maps keyring items onto gh accounts.
func enumerate() ([]ghauth.Account, error) {
	svc, err := secretservice.Open()
	if err != nil {
		return nil, err
	}
	defer svc.Close()

	items, err := svc.Items()
	if err != nil {
		return nil, err
	}
	return accountsFromItems(items), nil
}

// accountsFromItems maps keyring items onto gh accounts. Only entries carrying
// gh's service prefix are considered, so unrelated credentials are ignored. The
// active slot (empty username) is not an account of its own: it duplicates an
// existing user, and which one is already recorded in hosts.yml.
func accountsFromItems(items []secretservice.Item) []ghauth.Account {
	users := make(map[string]map[string]bool)
	for _, item := range items {
		host, ok := strings.CutPrefix(item.Attributes[attributeService], servicePrefix)
		if !ok || host == "" || strings.ContainsAny(host, " \t\n") {
			continue
		}
		user := item.Attributes[attributeUsername]
		if user == "" {
			continue
		}
		if users[host] == nil {
			users[host] = make(map[string]bool)
		}
		users[host][user] = true
	}

	var accounts []ghauth.Account
	for _, host := range sortedKeys(users) {
		for _, user := range sortedKeys(users[host]) {
			accounts = append(accounts, ghauth.Account{Host: host, User: user})
		}
	}
	return accounts
}

func sortedKeys[V any](m map[string]V) []string {
	keys := make([]string, 0, len(m))
	for key := range m {
		keys = append(keys, key)
	}
	slices.Sort(keys)
	return keys
}
