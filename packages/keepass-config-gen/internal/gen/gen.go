// Package gen provides shared helpers for atomically writing generated files
// and pruning stale ones from generated directories.
package gen

import (
	"crypto/sha256"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// ErrChanged is returned by checks when the generated output would change.
var ErrChanged = errors.New("output would change")

// File is one generated file: its destination path and its content.
type File struct {
	Path    string
	Content string
}

// FileExists reports whether path is an existing regular file.
func FileExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && !info.IsDir()
}

// Within verifies that path is contained in dir. It rejects paths that escape
// dir through absolute paths or `..` components.
func Within(dir, path string) error {
	rel, err := filepath.Rel(dir, path)
	if err != nil {
		return fmt.Errorf("cannot compare %s with %s: %w", path, dir, err)
	}
	if rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) || filepath.IsAbs(rel) {
		return fmt.Errorf("%s is outside %s", path, dir)
	}
	return nil
}

// AtomicWrite writes content to path via a temporary file in the same
// directory, then renames it into place.
func AtomicWrite(path, content string, mode os.FileMode) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(filepath.Dir(path), ".keepass-config-gen-*")
	if err != nil {
		return err
	}
	defer func() { _ = os.Remove(tmp.Name()) }()
	if _, err := tmp.WriteString(content); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	if err := os.Chmod(tmp.Name(), mode); err != nil {
		return err
	}
	return os.Rename(tmp.Name(), path)
}

// PruneDir removes files with the given suffix that are no longer produced, so
// a generated directory always matches the current database.
func PruneDir(dir string, keep map[string]bool, suffix string) error {
	return PruneMatching(dir, keep, func(path string) bool {
		return strings.HasSuffix(filepath.Base(path), suffix)
	})
}

// Stale returns files in dir for which match reports true and that are not in
// keep. Directories and retained files are left untouched. A missing directory
// has no stale files.
func Stale(dir string, keep map[string]bool, match func(string) bool) ([]string, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, err
	}
	var stale []string
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		path := filepath.Join(dir, entry.Name())
		if keep[path] || !match(path) {
			continue
		}
		stale = append(stale, path)
	}
	return stale, nil
}

// PruneMatching removes files for which match reports true and that are not in
// keep. Directories and retained files are left untouched.
func PruneMatching(dir string, keep map[string]bool, match func(string) bool) error {
	stale, err := Stale(dir, keep, match)
	if err != nil {
		return err
	}
	for _, path := range stale {
		if err := os.Remove(path); err != nil {
			return err
		}
	}
	return nil
}

// StateKey folds the given parts into one stable value, so a change to any
// part forces regeneration.
func StateKey(parts ...string) string {
	sum := sha256.Sum256([]byte(strings.Join(parts, "\x00")))
	return fmt.Sprintf("%x", sum)
}
