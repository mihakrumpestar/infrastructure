// Command remmina-config-gen generates Remmina profiles from a KeePassXC
// database.
//
// Every profile contains `password=.`; the real password is never used, logged,
// or written by this command. Instead the generated profile path is stored in
// the entry's `filename` custom attribute and `key=password` is set, so
// KeePassXC answers Remmina's Secret Service request for that path with the
// entry's password.
//
// Entries opt in with a custom string field `remmina_hosts` containing exactly
// one line of key=value options:
//
//	remmina_hosts:
//	  server=192.0.2.10 group=Lab quality=9
//
// `name` overrides the display name (default: entry title), `protocol`
// defaults to RDP, and `username` defaults to the entry's user name. Inline
// password keys are rejected.
package main

import (
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"keepass-config-gen/internal/gen"
	"keepass-config-gen/internal/keepass"
	"keepass-config-gen/internal/remmina"
	"keepass-config-gen/internal/tray"
)

const (
	defaultStateFile = "~/.local/state/remmina-config-gen/state"
	defaultLogFile   = "~/.local/state/remmina-config-gen/log"
	defaultPrefix    = "keepass_"
)

type options struct {
	keepass.Options
	OutputDir   string
	RemminaPref string
	Prefix      string
	StateFile   string
	LogFile     string
	IfChanged   bool
	Check       bool
	ToStdout    bool
	Tray        bool
}

func (o *options) applyDefaults() {
	if o.CLI == "" {
		o.CLI = keepass.DefaultCLI
	}
	if o.Prefix == "" {
		o.Prefix = defaultPrefix
	}
	if o.StateFile == "" {
		o.StateFile = defaultStateFile
	}
	if o.LogFile == "" {
		o.LogFile = defaultLogFile
	}
}

func fail(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "remmina-config-gen: "+format+"\n", args...)
	os.Exit(1)
}

func main() {
	var o options
	keepass.BindFlags(flag.CommandLine, &o.Options)
	flag.StringVar(&o.OutputDir, "output-dir", "", "Remmina profile directory (default: auto-detect)")
	flag.StringVar(&o.RemminaPref, "remmina-pref", "", "path to remmina.pref (default: auto-detect)")
	flag.StringVar(&o.Prefix, "prefix", defaultPrefix, "filename prefix for generated profiles")
	flag.StringVar(&o.StateFile, "state-file", defaultStateFile, "file recording the last-seen database fingerprint")
	flag.StringVar(&o.LogFile, "log-file", defaultLogFile, "file for the tray's last-run log")
	flag.BoolVar(&o.IfChanged, "if-changed", false, "skip regeneration if the database is unchanged since the last run")
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
	o.applyDefaults()
	// A tray refresh is explicit. Do not let --if-changed turn it into a no-op
	// when the database is unchanged but Remmina has rewritten a profile, and
	// never let the print/check modes suppress the refresh.
	o.IfChanged = false
	o.ToStdout = false
	o.Check = false
	if err := remmina.ValidatePrefix(o.Prefix); err != nil {
		fail("%v", err)
	}
	o.LogFile = keepass.Expand(o.LogFile)
	dataDir, _, _ := remmina.ResolveDataDir(o.OutputDir, o.RemminaPref)
	if abs, absErr := filepath.Abs(dataDir); absErr == nil {
		dataDir = abs
	}
	tray.Run(tray.Config{
		Title:     "remmina-config-gen",
		Refresh:   func() error { return generate(o) },
		OpenPath:  dataDir,
		OpenLabel: "Open profiles",
		LogFile:   o.LogFile,
	})
}

// generate is the tray/CLI entry point. It constructs the real Secret Service;
// tests call generateWith with a fake.
func generate(o options) error {
	return generateWith(o, nil)
}

// job is one profile whose inputs are fully validated. Nothing is written and
// no KeePassXC attribute is changed until every entry has produced a job.
type job struct {
	title   string
	uuid    string
	profile remmina.Profile
	path    string
}

// generateWith is generate with an injectable Secret Service.
func generateWith(o options, svc remmina.SecretService) error {
	o.applyDefaults()
	if o.Database == "" {
		return errors.New("--database is required")
	}
	if err := remmina.ValidatePrefix(o.Prefix); err != nil {
		return err
	}

	databasePath := keepass.Expand(o.Database)
	dataDir, prefPath, prefValue := remmina.ResolveDataDir(o.OutputDir, o.RemminaPref)
	var err error
	if dataDir, err = filepath.Abs(dataDir); err != nil {
		return fmt.Errorf("cannot resolve output directory: %w", err)
	}

	fingerprint, err := keepass.Fingerprint(databasePath)
	if err != nil {
		return fmt.Errorf("cannot stat database: %w", err)
	}
	key := gen.StateKey(fingerprint, databasePath, dataDir, o.Prefix, prefPath, prefValue)
	statePath := keepass.Expand(o.StateFile)

	// --print and --check are read-only views. Only a normal run may skip
	// because of --if-changed.
	writing := !o.ToStdout && !o.Check
	if o.IfChanged && writing && gen.Current(statePath, key) {
		return nil
	}

	password, err := o.Password()
	if err != nil {
		return err
	}
	raw, err := o.Run(password, "export", "-f", "xml", databasePath)
	if err != nil {
		return fmt.Errorf("cannot read database: %w", err)
	}
	// The XML export contains every entry password. This command never needs
	// one, so clear the raw buffer immediately, even when parsing fails.
	defer func() {
		for index := range raw {
			raw[index] = 0
		}
	}()
	entries, err := keepass.ParseXML(raw)
	if err != nil {
		return fmt.Errorf("cannot parse database export: %w", err)
	}
	for index := range entries {
		delete(entries[index].Fields, "Password")
		entries[index].Password = ""
	}

	// Phase 1: parse and render every entry before touching KeePassXC, so an
	// invalid later entry cannot leave earlier attributes modified.
	jobs := make([]job, 0, len(entries))
	seen := make(map[string]string, len(entries))
	for _, entry := range entries {
		if entry.Fields[remmina.FieldHosts] == "" {
			continue
		}
		profile, warnings, err := remmina.ParseHosts(entry)
		if err != nil {
			return err
		}
		for _, warning := range warnings {
			fmt.Fprintf(os.Stderr, "remmina-config-gen: warning: %s: %s\n", entry.Title, warning)
		}
		if err := remmina.ValidateUUID(entry.UUID); err != nil {
			return fmt.Errorf("%s: %w", entry.Title, err)
		}

		path, err := filepath.Abs(filepath.Join(dataDir, remmina.Filename(o.Prefix, entry)))
		if err != nil {
			return fmt.Errorf("cannot resolve profile path for %s: %w", entry.Title, err)
		}
		if err := gen.Within(dataDir, path); err != nil {
			return fmt.Errorf("profile path for %s: %w", entry.Title, err)
		}
		if previous, ok := seen[path]; ok {
			return fmt.Errorf(
				"entries %q and %q generate the same profile path %s", previous, entry.Title, path,
			)
		}
		seen[path] = entry.Title
		jobs = append(jobs, job{title: entry.Title, uuid: entry.UUID, profile: profile, path: path})
	}

	if o.ToStdout {
		for _, j := range jobs {
			fmt.Printf("# %s\n%s", filepath.Base(j.path), remmina.Render(j.profile))
		}
		return nil
	}

	// --check needs Secret Service visibility to avoid demanding profiles for
	// entries the user has not exposed. It stays read-only.
	if (writing || o.Check) && svc == nil {
		svc = remmina.NewDBusService()
	}

	if o.Check {
		var (
			files     []gen.File
			keep      = make(map[string]bool)
			invisible int
		)
		for _, j := range jobs {
			visible, err := svc.Visible(j.uuid)
			switch {
			case errors.Is(err, remmina.ErrUnavailable):
				// Without a Secret Service the visibility is unknown. Assume
				// the entry is visible so an offline --check still validates
				// the generated files instead of failing on the missing bus.
				fmt.Fprintf(
					os.Stderr,
					"remmina-config-gen: warning: %s: Secret Service unavailable; assuming entry is visible\n",
					j.title,
				)
				visible = true
			case err != nil:
				return fmt.Errorf("%s: cannot read Secret Service visibility: %w", j.title, err)
			}
			if !visible {
				// A normal run preserves an existing profile when an entry is
				// not exposed, so --check must not treat it as stale either.
				keep[j.path] = true
				invisible++
				continue
			}
			files = append(files, gen.File{Path: j.path, Content: remmina.Render(j.profile)})
			keep[j.path] = true
		}
		// A normal run disables pruning whenever any entry is invisible, so
		// --check must skip stale detection in exactly the same situation.
		return checkFiles(dataDir, o.Prefix, files, keep, invisible == 0)
	}

	// Invalidate state before touching KeePassXC. Secret Service updates are
	// not atomic across entries: if a later call fails, earlier attributes may
	// already be set. The missing state forces the next run to reconcile all
	// of them, but it cannot undo the already-applied attributes.
	if err := gen.RemoveState(statePath); err != nil {
		return fmt.Errorf("cannot invalidate state file: %w", err)
	}

	// Phase 2: apply every Secret Service update, then write the profiles.
	var (
		files   []gen.File
		keep    = make(map[string]bool)
		skipped int
	)
	for _, j := range jobs {
		if err := svc.SetProfile(j.uuid, j.path); err != nil {
			switch {
			case errors.Is(err, remmina.ErrLocked):
				return fmt.Errorf("KeePassXC Secret Service is locked; unlock KeePassXC and retry: %w", err)
			case errors.Is(err, remmina.ErrNotFound):
				fmt.Fprintf(
					os.Stderr,
					"remmina-config-gen: warning: skipped %s: entry is not in the exposed Secret Service group\n",
					j.title,
				)
				skipped++
				continue
			case errors.Is(err, remmina.ErrUnavailable):
				return fmt.Errorf(
					"KeePassXC Secret Service is unavailable; ensure KeePassXC is running with Secret Service enabled: %w",
					err,
				)
			default:
				return fmt.Errorf("%s: %w", j.title, err)
			}
		}
		files = append(files, gen.File{Path: j.path, Content: remmina.Render(j.profile)})
		keep[j.path] = true
	}

	// An incomplete run must not prune: an entry skipped now may have an older
	// profile whose title still applies.
	if err := writeFiles(dataDir, o.Prefix, files, keep, skipped == 0); err != nil {
		return err
	}

	if skipped == 0 {
		// Setting the custom attributes modifies the KeePassXC database. Use
		// the post-write fingerprint so a path-unit watch does not immediately
		// trigger a redundant second run.
		finalFingerprint, err := keepass.Fingerprint(databasePath)
		if err != nil {
			return fmt.Errorf("cannot stat database after generation: %w", err)
		}
		finalKey := gen.StateKey(finalFingerprint, databasePath, dataDir, o.Prefix, prefPath, prefValue)
		paths := make([]string, len(files))
		for index, file := range files {
			paths[index] = file.Path
		}
		if err := gen.WriteState(statePath, gen.State{Key: finalKey, Files: paths}); err != nil {
			return fmt.Errorf("cannot write state file: %w", err)
		}
	}

	if skipped > 0 {
		fmt.Fprintf(os.Stderr, "remmina-config-gen: wrote %d profiles (%d skipped)\n", len(files), skipped)
	} else {
		fmt.Fprintf(os.Stderr, "remmina-config-gen: wrote %d profiles\n", len(files))
	}
	return nil
}

// managed reports whether a file is one this generator owns.
func managed(path, prefix string) bool {
	base := filepath.Base(path)
	return strings.HasPrefix(base, prefix) && strings.HasSuffix(base, ".remmina")
}

func checkFiles(dataDir, prefix string, files []gen.File, keep map[string]bool, prune bool) error {
	for _, file := range files {
		current, err := os.ReadFile(file.Path)
		if err != nil || string(current) != file.Content {
			return gen.ErrChanged
		}
	}
	if !prune {
		return nil
	}
	stale, err := gen.Stale(dataDir, keep, func(path string) bool {
		return managed(path, prefix)
	})
	if err != nil {
		return fmt.Errorf("cannot read output directory: %w", err)
	}
	if len(stale) > 0 {
		return gen.ErrChanged
	}
	return nil
}

func writeFiles(dataDir, prefix string, files []gen.File, keep map[string]bool, prune bool) error {
	if err := os.MkdirAll(dataDir, 0o750); err != nil {
		return fmt.Errorf("cannot create output directory: %w", err)
	}
	for _, file := range files {
		if err := gen.AtomicWrite(file.Path, file.Content, 0o600); err != nil {
			return fmt.Errorf("cannot write %s: %w", file.Path, err)
		}
	}
	if !prune {
		return nil
	}
	if err := gen.PruneMatching(dataDir, keep, func(path string) bool {
		return managed(path, prefix)
	}); err != nil {
		return fmt.Errorf("cannot prune output directory: %w", err)
	}
	return nil
}
