// Package ghauth reconciles the identity metadata in gh's hosts.yml with the
// accounts discovered in the Secret Service.
//
// The package is pure: no D-Bus, no file system. The caller discovers accounts,
// decides whether to write, and owns atomic replacement of the file. No token is
// minted or resolved here; inline tokens already present in the document are
// carried over verbatim because gh reads them as live credentials.
package ghauth

import (
	"bytes"
	"fmt"
	"slices"

	"gopkg.in/yaml.v3"
)

const (
	// fileIndent matches the indentation gh writes itself.
	fileIndent = 4
	keyUser    = "user"
	keyUsers   = "users"
	keyToken   = "oauth_token"
)

// Account is one gh account found in the Secret Service.
//
// No active flag: resolving gh's active slot would mean reading its secret over
// D-Bus, which can prompt on a locked keyring. The existing user key in hosts.yml
// is the only active hint this package trusts.
type Account struct {
	Host string // e.g. "github.com"
	User string // non-empty keyring username
}

// Reconcile merges discovered accounts into an existing hosts.yml document.
// Existing bytes may be nil or empty. It returns the new document, whether it
// differs from the input, and the sorted, deduplicated hosts where the user key
// had to be guessed.
//
// Only hosts present in accounts are rewritten; every other key is carried over
// verbatim. Users holding an inline oauth_token survive as live credentials and
// take part in user selection. An empty or unusable account list never
// synthesises a document. Malformed input yields an error and no output, so the
// caller can keep the file untouched.
func Reconcile(existing []byte, accounts []Account) (out []byte, changed bool, guessed []string, err error) {
	byHost := group(accounts)
	if len(byHost) == 0 {
		return existing, false, nil, nil
	}
	doc, err := parse(existing)
	if err != nil {
		return nil, false, nil, err
	}

	for _, host := range hosts(byHost) {
		entry, entryErr := doc.entry(host)
		if entryErr != nil {
			return nil, false, nil, entryErr
		}

		inline := inlineUsers(entry)
		candidates := union(byHost[host], sortedKeys(inline))
		user, clear := pickUser(lookup(entry, keyUser), candidates)
		if !clear {
			guessed = append(guessed, host)
		}
		set(entry, keyUser, scalarNode(user))
		set(entry, keyUsers, usersNode(candidates, inline))
		set(doc.root, host, entry)
	}

	out, err = encode(doc)
	if err != nil {
		return nil, false, nil, err
	}
	return out, !bytes.Equal(out, existing), normalise(guessed), nil
}

// group folds accounts into one sorted, deduplicated user list per host.
// Incomplete records and duplicate users are dropped.
func group(accounts []Account) map[string][]string {
	byHost := map[string][]string{}
	for _, account := range accounts {
		if account.Host == "" || account.User == "" {
			continue
		}
		byHost[account.Host] = append(byHost[account.Host], account.User)
	}
	for host, users := range byHost {
		byHost[host] = normalise(users)
	}
	return byHost
}

// hosts returns the host names in stable order.
func hosts(byHost map[string][]string) []string {
	names := make([]string, 0, len(byHost))
	for host := range byHost {
		names = append(names, host)
	}
	slices.Sort(names)
	return names
}

// pickUser chooses the user key for a host and reports whether the choice was
// unambiguous. Precedence: the existing user when still discovered, the only
// candidate, then the lexicographically first candidate.
func pickUser(existing *yaml.Node, candidates []string) (user string, clear bool) {
	if existing != nil && isValue(existing) && slices.Contains(candidates, existing.Value) {
		return existing.Value, true
	}
	return candidates[0], len(candidates) == 1
}

// document is a parsed hosts.yml root mapping.
type document struct {
	root *yaml.Node
}

// entry returns the mapping for host, creating a detached one when the host is
// absent or null-valued. Both cases mean the same to gh.
func (d *document) entry(host string) (*yaml.Node, error) {
	node := lookup(d.root, host)
	switch {
	case node == nil:
		return mappingNode(), nil
	case node.Kind == yaml.ScalarNode && !isValue(node):
		return mappingNode(), nil
	case node.Kind != yaml.MappingNode:
		return nil, fmt.Errorf("hosts.yml: host %q is not a mapping", host)
	}
	return node, nil
}

// inlineUsers returns the users entries carrying a non-empty oauth_token, keyed
// by login. Their nodes are reused verbatim, so token bytes never round-trip.
func inlineUsers(entry *yaml.Node) map[string]*yaml.Node {
	preserved := map[string]*yaml.Node{}
	users := lookup(entry, keyUsers)
	if users == nil || users.Kind != yaml.MappingNode {
		return preserved
	}
	for i := 0; i+1 < len(users.Content); i += 2 {
		props := users.Content[i+1]
		token := lookup(props, keyToken)
		if token != nil && isValue(token) {
			preserved[users.Content[i].Value] = props
		}
	}
	return preserved
}

// usersNode renders the users mapping: null for keyring accounts, the original
// node for accounts that authenticate with an inline token.
func usersNode(candidates []string, inline map[string]*yaml.Node) *yaml.Node {
	node := &yaml.Node{Kind: yaml.MappingNode, Tag: "!!map"}
	for _, name := range candidates {
		value := inline[name]
		if value == nil {
			value = &yaml.Node{Kind: yaml.ScalarNode, Tag: "!!null", Value: "null"}
		}
		node.Content = append(node.Content, scalarNode(name), value)
	}
	return node
}

// lookup returns the value node for key in a mapping, or nil.
func lookup(node *yaml.Node, key string) *yaml.Node {
	if node == nil || node.Kind != yaml.MappingNode {
		return nil
	}
	for i := 0; i+1 < len(node.Content); i += 2 {
		if node.Content[i].Value == key {
			return node.Content[i+1]
		}
	}
	return nil
}

// set replaces key in a mapping, or appends it when absent.
func set(node *yaml.Node, key string, value *yaml.Node) {
	for i := 0; i+1 < len(node.Content); i += 2 {
		if node.Content[i].Value == key {
			node.Content[i+1] = value
			return
		}
	}
	node.Content = append(node.Content, scalarNode(key), value)
}

func mappingNode() *yaml.Node {
	return &yaml.Node{Kind: yaml.MappingNode, Tag: "!!map"}
}

func scalarNode(value string) *yaml.Node {
	return &yaml.Node{Kind: yaml.ScalarNode, Tag: "!!str", Value: value}
}

// isValue reports whether the node holds a real value rather than null.
func isValue(node *yaml.Node) bool {
	return node.Kind == yaml.ScalarNode && node.Tag != "!!null" && node.Value != ""
}

// parse decodes hosts.yml. Empty input is an empty document.
func parse(existing []byte) (*document, error) {
	if len(bytes.TrimSpace(existing)) == 0 {
		return &document{root: mappingNode()}, nil
	}
	var root yaml.Node
	if err := yaml.Unmarshal(existing, &root); err != nil {
		return nil, fmt.Errorf("parse hosts.yml: %w", err)
	}
	node := &root
	if node.Kind == yaml.DocumentNode {
		if len(node.Content) == 0 {
			return &document{root: mappingNode()}, nil
		}
		node = node.Content[0]
	}
	if node.Kind == yaml.ScalarNode && !isValue(node) {
		return &document{root: mappingNode()}, nil
	}
	if node.Kind != yaml.MappingNode {
		return nil, fmt.Errorf("parse hosts.yml: top level is not a mapping")
	}
	return &document{root: node}, nil
}

// encode renders the document with gh's indentation and one trailing newline,
// without a document separator.
func encode(doc *document) ([]byte, error) {
	var buf bytes.Buffer
	encoder := yaml.NewEncoder(&buf)
	encoder.SetIndent(fileIndent)
	if err := encoder.Encode(doc.root); err != nil {
		return nil, fmt.Errorf("encode hosts.yml: %w", err)
	}
	if err := encoder.Close(); err != nil {
		return nil, fmt.Errorf("encode hosts.yml: %w", err)
	}
	return buf.Bytes(), nil
}

// sortedKeys returns the map keys in order.
func sortedKeys[V any](values map[string]V) []string {
	names := make([]string, 0, len(values))
	for name := range values {
		names = append(names, name)
	}
	slices.Sort(names)
	return names
}

// union merges two name lists into a sorted, deduplicated one.
func union(a, b []string) []string {
	return normalise(append(slices.Clone(a), b...))
}

// normalise sorts and dedupes, keeping caller-facing lists deterministic.
func normalise(names []string) []string {
	slices.Sort(names)
	return slices.Compact(names)
}
