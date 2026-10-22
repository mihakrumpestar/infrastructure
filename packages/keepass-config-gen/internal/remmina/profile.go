package remmina

import (
	"encoding/hex"
	"errors"
	"fmt"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"unicode"

	"keepass-config-gen/internal/keepass"
)

// FieldHosts is the custom entry field that opts an entry in to Remmina
// profile generation.
const FieldHosts = "remmina_hosts"

// Profile is one Remmina connection. Options holds the [remmina] keys other
// than the name, which has its own field.
type Profile struct {
	Name    string
	Options map[string]string
}

var (
	profileKey = regexp.MustCompile(`^[A-Za-z0-9_.-]+$`)

	// These keys would put a secret in the profile. KeePassXC must be the only
	// source of passwords, so they are rejected rather than silently dropped.
	// Remmina treats all of them as secret settings.
	inlineSecretKeys = map[string]bool{
		"password":              true,
		"ssh_password":          true,
		"gateway_password":      true,
		"ssh_tunnel_password":   true,
		"ssh_tunnel_passphrase": true,
	}
)

// isInlineSecret reports whether key is a Remmina secret setting. Matching is
// case-insensitive because Remmina's keys are.
func isInlineSecret(key string) bool {
	return inlineSecretKeys[strings.ToLower(key)]
}

// ValidatePrefix rejects a prefix that could escape the profile directory or
// create nested paths. An empty prefix is allowed and defaulted by the caller.
func ValidatePrefix(prefix string) error {
	if prefix == "" {
		return nil
	}
	for _, r := range prefix {
		if unicode.IsControl(r) {
			return fmt.Errorf("prefix %q contains a control character", prefix)
		}
	}
	if filepath.IsAbs(prefix) {
		return fmt.Errorf("prefix %q must be relative", prefix)
	}
	if strings.ContainsAny(prefix, `/\`) {
		return fmt.Errorf("prefix %q must not contain path separators", prefix)
	}
	if prefix == "." || prefix == ".." {
		return fmt.Errorf("prefix %q is not a filename component", prefix)
	}
	return nil
}

// ValidateUUID reports whether uuid is the 32-character hex form produced by
// keepass.ParseXML. Every mode needs it: the UUID is part of the profile
// filename and of the Secret Service lookup.
func ValidateUUID(uuid string) error {
	if uuid == "" {
		return errors.New("entry has no UUID; cannot build a Remmina profile")
	}
	if len(uuid) != 32 {
		return fmt.Errorf("entry UUID %q must be 32 hex characters", uuid)
	}
	if _, err := hex.DecodeString(uuid); err != nil {
		return fmt.Errorf("entry UUID %q is not valid hex: %w", uuid, err)
	}
	return nil
}

type profileLine struct {
	text   string
	number int
}

// ParseHosts parses an entry's remmina_hosts field. Exactly one non-comment
// line is allowed: the Secret Service filename attribute is single-valued, so
// one entry can only describe one profile.
func ParseHosts(entry keepass.Entry) (Profile, []string, error) {
	if strings.ContainsRune(entry.Title, 0) {
		return Profile{}, nil, fmt.Errorf("entry title contains NUL")
	}
	var lines []profileLine
	for index, line := range strings.Split(entry.Fields[FieldHosts], "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		lines = append(lines, profileLine{text: line, number: index + 1})
	}

	if len(lines) == 0 {
		return Profile{}, nil, fmt.Errorf("%s: remmina_hosts has no profile line", entry.Title)
	}
	if len(lines) > 1 {
		return Profile{}, nil, fmt.Errorf(
			"%s: remmina_hosts has %d profile lines, want exactly 1 (one profile per entry)",
			entry.Title, len(lines),
		)
	}

	line := lines[0]
	profile := Profile{
		Name:    entry.Title,
		Options: make(map[string]string),
	}

	var warnings []string
	for _, token := range keepass.Tokenize(line.text) {
		key, value, ok := strings.Cut(token, "=")
		if !ok || key == "" {
			warnings = append(warnings, fmt.Sprintf("line %d: invalid token %q", line.number, token))
			continue
		}
		if strings.ContainsRune(value, 0) {
			return Profile{}, nil, fmt.Errorf(
				"%s: line %d: value for %q contains NUL", entry.Title, line.number, key,
			)
		}
		if !profileKey.MatchString(key) {
			warnings = append(warnings, fmt.Sprintf("line %d: invalid key %q", line.number, key))
			continue
		}
		if isInlineSecret(key) {
			return Profile{}, nil, fmt.Errorf(
				"%s: inline %s is not allowed; KeePassXC provides the password over Secret Service",
				entry.Title, key,
			)
		}
		// Remmina keys are case-insensitive. Normalise before the reserved-key
		// checks so Protocol=VNC cannot bypass the default and leave two keys.
		key = strings.ToLower(key)
		if key == "name" {
			profile.Name = value
			continue
		}
		profile.Options[key] = value
	}

	if _, ok := profile.Options["protocol"]; !ok {
		profile.Options["protocol"] = "RDP"
	}
	if _, ok := profile.Options["username"]; !ok {
		profile.Options["username"] = entry.Username
	}
	if profile.Options["server"] == "" {
		return Profile{}, nil, fmt.Errorf(
			"%s: remmina_hosts line %d has no server", entry.Title, line.number,
		)
	}

	return profile, warnings, nil
}

// Filename builds a stable, collision-free profile filename. The full entry
// UUID disambiguates entries whose titles sanitise to the same slug.
func Filename(prefix string, entry keepass.Entry) string {
	slug := strings.ToLower(keepass.Sanitise(entry.Title))
	if entry.Title == "" || slug == "" {
		slug = "profile"
	}
	return prefix + slug + "-" + entry.UUID + ".remmina"
}

// Render serialises a profile as a GKeyFile fragment. The password is always
// the literal ".", which tells Remmina to ask Secret Service for the entry's
// password; any password value in the input is ignored.
func Render(profile Profile) string {
	var builder strings.Builder
	builder.WriteString("# Generated by remmina-config-gen. Do not edit by hand.\n")
	builder.WriteString("[remmina]\n")

	write := func(key, value string) {
		if strings.ContainsRune(value, 0) {
			return
		}
		builder.WriteString(key + "=" + escapeValue(value) + "\n")
	}

	write("name", profile.Name)
	for _, key := range []string{"protocol", "server", "username"} {
		if value, ok := profile.Options[key]; ok {
			write(key, value)
		}
	}
	builder.WriteString("password=.\n")

	keys := make([]string, 0, len(profile.Options))
	for key := range profile.Options {
		switch key {
		case "name", "protocol", "server", "username", "password":
			continue
		}
		if isInlineSecret(key) {
			continue
		}
		keys = append(keys, key)
	}
	slices.Sort(keys)
	for _, key := range keys {
		write(key, profile.Options[key])
	}

	return builder.String()
}

// escapeValue escapes a GKeyFile value. Leading and trailing spaces are
// written as \s so GLib does not trim them; NUL is rejected by the caller.
func escapeValue(value string) string {
	var builder strings.Builder
	for index, r := range value {
		switch r {
		case '\\':
			builder.WriteString(`\\`)
		case '\n':
			builder.WriteString(`\n`)
		case '\r':
			builder.WriteString(`\r`)
		case '\t':
			builder.WriteString(`\t`)
		case ' ':
			if index == 0 || index == len(value)-1 {
				builder.WriteString(`\s`)
			} else {
				builder.WriteByte(' ')
			}
		default:
			builder.WriteRune(r)
		}
	}
	return builder.String()
}
