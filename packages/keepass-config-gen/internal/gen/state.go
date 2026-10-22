package gen

import (
	"os"
	"strings"
)

// stateVersion marks the state file layout. Files without it (written by older
// versions) are treated as absent so the next run regenerates once.
const stateVersion = "v1"

// State records the inputs of the last complete run and the files it wrote.
type State struct {
	Key   string
	Files []string
}

// ReadState reads a versioned state file. It returns false when the file is
// missing or does not use the current format.
func ReadState(path string) (State, bool) {
	data, err := os.ReadFile(path)
	if err != nil {
		return State{}, false
	}
	lines := strings.Split(strings.TrimRight(string(data), "\n"), "\n")
	if len(lines) < 2 || lines[0] != stateVersion {
		return State{}, false
	}
	key := strings.TrimSpace(lines[1])
	if key == "" {
		return State{}, false
	}
	var files []string
	for _, line := range lines[2:] {
		if line = strings.TrimSpace(line); line != "" {
			files = append(files, line)
		}
	}
	return State{Key: key, Files: files}, true
}

// WriteState atomically writes a private versioned state file.
func WriteState(path string, state State) error {
	var builder strings.Builder
	builder.WriteString(stateVersion + "\n")
	builder.WriteString(state.Key + "\n")
	for _, file := range state.Files {
		builder.WriteString(file + "\n")
	}
	return AtomicWrite(path, builder.String(), 0o600)
}

// RemoveState deletes the state file so a failed run forces a retry. A missing
// file is not an error.
func RemoveState(path string) error {
	if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
		return err
	}
	return nil
}

// Current reports whether the state file belongs to key and every file it
// lists still exists. It deliberately checks existence, not content: --check or
// a tray refresh detects content drift.
func Current(path, key string) bool {
	state, ok := ReadState(path)
	if !ok || state.Key != key {
		return false
	}
	for _, file := range state.Files {
		if !FileExists(file) {
			return false
		}
	}
	return true
}
