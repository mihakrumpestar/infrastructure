package gen

import (
	"os"
	"path/filepath"
	"slices"
	"testing"
)

func TestPruneDir(t *testing.T) {
	dir := t.TempDir()
	keepPath := filepath.Join(dir, "keep-12345678.pub")
	stalePath := filepath.Join(dir, "stale-12345678.pub")
	otherPath := filepath.Join(dir, "notes.txt")
	for _, path := range []string{keepPath, stalePath, otherPath} {
		if err := os.WriteFile(path, []byte("x"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	if err := PruneDir(dir, map[string]bool{keepPath: true}, ".pub"); err != nil {
		t.Fatal(err)
	}
	if !FileExists(keepPath) {
		t.Error("kept .pub was removed")
	}
	if FileExists(stalePath) {
		t.Error("stale .pub was not removed")
	}
	if !FileExists(otherPath) {
		t.Error("non-.pub file was removed")
	}
}

func TestPruneMatching(t *testing.T) {
	dir := t.TempDir()
	keepPath := filepath.Join(dir, "keep")
	stalePath := filepath.Join(dir, "stale")
	otherPath := filepath.Join(dir, "other")
	for _, path := range []string{keepPath, stalePath, otherPath} {
		if err := os.WriteFile(path, []byte(filepath.Base(path)), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	if err := PruneMatching(dir, map[string]bool{keepPath: true}, func(path string) bool {
		data, err := os.ReadFile(path)
		return err == nil && string(data) != "other"
	}); err != nil {
		t.Fatal(err)
	}
	if !FileExists(keepPath) {
		t.Error("kept file was removed")
	}
	if FileExists(stalePath) {
		t.Error("stale matching file was not removed")
	}
	if !FileExists(otherPath) {
		t.Error("non-matching file was removed")
	}
}

func TestStateKey(t *testing.T) {
	key := StateKey("a", "b")
	if StateKey("a", "b") != key {
		t.Fatal("state key not stable")
	}
	if key == StateKey("a", "c") {
		t.Fatal("state key did not change")
	}
	if StateKey("ab", "c") == StateKey("a", "bc") {
		t.Fatal("state key parts were not separated")
	}
}

func TestAtomicWrite(t *testing.T) {
	path := filepath.Join(t.TempDir(), "nested", "file")
	if err := AtomicWrite(path, "content", 0o600); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if string(data) != "content" {
		t.Fatalf("got %q", data)
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Fatalf("mode = %v, want 0600", info.Mode().Perm())
	}
}

func TestStale(t *testing.T) {
	dir := t.TempDir()
	keepPath := filepath.Join(dir, "keep")
	stalePath := filepath.Join(dir, "stale")
	otherPath := filepath.Join(dir, "other")
	for _, path := range []string{keepPath, stalePath, otherPath} {
		if err := os.WriteFile(path, []byte(filepath.Base(path)), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	stale, err := Stale(dir, map[string]bool{keepPath: true}, func(path string) bool {
		return filepath.Base(path) != "other"
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(stale) != 1 || stale[0] != stalePath {
		t.Fatalf("stale = %v, want [%s]", stale, stalePath)
	}
	if !FileExists(stalePath) {
		t.Fatal("Stale removed a file")
	}
	missing, err := Stale(filepath.Join(dir, "missing"), nil, func(string) bool { return true })
	if err != nil || missing != nil {
		t.Fatalf("missing dir: stale=%v err=%v", missing, err)
	}
}

func TestStateRoundTrip(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "state")
	existing := filepath.Join(dir, "existing")
	if err := os.WriteFile(existing, []byte("x"), 0o600); err != nil {
		t.Fatal(err)
	}
	state := State{Key: "key", Files: []string{existing, filepath.Join(dir, "missing")}}
	if err := WriteState(path, state); err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Fatalf("mode = %v, want 0600", info.Mode().Perm())
	}
	got, ok := ReadState(path)
	if !ok {
		t.Fatal("ReadState did not recognise a written state")
	}
	if got.Key != state.Key || !slices.Equal(got.Files, state.Files) {
		t.Fatalf("state = %#v, want %#v", got, state)
	}
	if Current(path, "key") {
		t.Fatal("Current accepted a state with a missing file")
	}
	if err := os.WriteFile(state.Files[1], []byte("x"), 0o600); err != nil {
		t.Fatal(err)
	}
	if !Current(path, "key") {
		t.Fatal("Current rejected a complete state")
	}
	if Current(path, "other") {
		t.Fatal("Current accepted a different key")
	}
}

func TestRemoveState(t *testing.T) {
	path := filepath.Join(t.TempDir(), "state")
	if err := os.WriteFile(path, []byte("x"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := RemoveState(path); err != nil {
		t.Fatal(err)
	}
	if FileExists(path) {
		t.Fatal("RemoveState left the file in place")
	}
	if err := RemoveState(path); err != nil {
		t.Fatalf("RemoveState on a missing file: %v", err)
	}
}

func TestReadStateRejectsLegacyAndMissing(t *testing.T) {
	dir := t.TempDir()
	legacy := filepath.Join(dir, "legacy")
	if err := os.WriteFile(legacy, []byte("key\n/path\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, ok := ReadState(legacy); ok {
		t.Fatal("legacy state without a version marker was accepted")
	}
	if _, ok := ReadState(filepath.Join(dir, "missing")); ok {
		t.Fatal("missing state was accepted")
	}
}

func TestWithin(t *testing.T) {
	dir := t.TempDir()
	if err := Within(dir, filepath.Join(dir, "profile.remmina")); err != nil {
		t.Fatalf("contained path rejected: %v", err)
	}
	for _, path := range []string{
		filepath.Join(dir, "..", "escaped"),
		filepath.Join(dir, "sub", "..", "..", "escaped"),
		"/absolute",
	} {
		if err := Within(dir, path); err == nil {
			t.Errorf("Within accepted %q", path)
		}
	}
}
