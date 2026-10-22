// Package remmina generates Remmina connection profiles from KeePassXC entries.
//
// Passwords are never stored in a profile. Every generated profile contains
// `password=.` and KeePassXC supplies the real password over the Secret Service
// API, keyed by the entry's custom attributes.
package remmina

import (
	"bufio"
	"os"
	"path/filepath"
	"strings"

	"keepass-config-gen/internal/keepass"
)

const (
	prefSection = "remmina_pref"
	prefFile    = "remmina.pref"
	dataDirKey  = "datadir_path"
)

// ResolvePrefPath returns Remmina's preference file path. An explicit override
// wins, then $XDG_CONFIG_HOME, then ~/.config.
func ResolvePrefPath(prefOverride string) string {
	if prefOverride != "" {
		return filepath.Clean(keepass.Expand(prefOverride))
	}
	if xdg := os.Getenv("XDG_CONFIG_HOME"); filepath.IsAbs(xdg) {
		return filepath.Join(xdg, "remmina", prefFile)
	}
	if home, err := os.UserHomeDir(); err == nil {
		return filepath.Join(home, ".config", "remmina", prefFile)
	}
	return filepath.Join(".config", "remmina", prefFile)
}

// ResolveDataDir implements Remmina's datadir discovery:
//
//  1. an explicit output override,
//  2. datadir_path from remmina.pref when that directory exists,
//  3. ~/.remmina when it exists,
//  4. $XDG_DATA_HOME/remmina (default ~/.local/share/remmina).
//
// It never creates directories. The returned prefValue is the raw datadir_path
// preference, even when an override wins, so callers can fold it into
// change-detection state without reading the preference file twice.
func ResolveDataDir(outputOverride, prefOverride string) (dataDir, prefPath, prefValue string) {
	prefPath = ResolvePrefPath(prefOverride)
	// Remmina falls through to the next candidate when its preference file is
	// missing or unreadable, so any read or parse error means "no preference".
	prefValue, _ = readINIValue(prefPath, prefSection, dataDirKey)

	if outputOverride != "" {
		return filepath.Clean(keepass.Expand(outputOverride)), prefPath, prefValue
	}
	if prefValue != "" {
		candidate := filepath.Clean(keepass.Expand(prefValue))
		if info, statErr := os.Stat(candidate); statErr == nil && info.IsDir() {
			return candidate, prefPath, prefValue
		}
	}

	if home, homeErr := os.UserHomeDir(); homeErr == nil {
		candidate := filepath.Join(home, ".remmina")
		if info, statErr := os.Stat(candidate); statErr == nil && info.IsDir() {
			return candidate, prefPath, prefValue
		}
	}

	if xdg := os.Getenv("XDG_DATA_HOME"); filepath.IsAbs(xdg) {
		return filepath.Join(xdg, "remmina"), prefPath, prefValue
	}
	if home, homeErr := os.UserHomeDir(); homeErr == nil {
		return filepath.Join(home, ".local", "share", "remmina"), prefPath, prefValue
	}
	return filepath.Join(".local", "share", "remmina"), prefPath, prefValue
}

// readINIValue is a deliberately small line-based reader for Remmina's prefs.
// It understands section headers, blank lines, #/; comments, and key=value
// pairs; it does not need quoting, interpolation, or duplicate-section rules.
func readINIValue(path, section, key string) (string, error) {
	file, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer func() { _ = file.Close() }()

	scanner := bufio.NewScanner(file)
	inSection := false
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") || strings.HasPrefix(line, ";") {
			continue
		}
		if strings.HasPrefix(line, "[") && strings.HasSuffix(line, "]") {
			inSection = strings.TrimSpace(line[1:len(line)-1]) == section
			continue
		}
		if !inSection {
			continue
		}
		name, value, ok := strings.Cut(line, "=")
		if !ok || strings.TrimSpace(name) != key {
			continue
		}
		return strings.TrimSpace(value), nil
	}
	if err := scanner.Err(); err != nil {
		return "", err
	}
	return "", nil
}
