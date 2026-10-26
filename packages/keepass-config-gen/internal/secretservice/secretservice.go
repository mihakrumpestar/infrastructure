// Package secretservice is the Secret Service (org.freedesktop.secrets) D-Bus
// subset needed to find items by attribute, read their attributes, and update
// them. Locked collections are never searched, so lookups never trigger an
// unlock prompt.
package secretservice

import (
	"errors"
	"fmt"

	"github.com/godbus/dbus/v5"
)

var (
	// ErrLocked means every collection is locked. The user must unlock the
	// keyring and retry.
	ErrLocked = errors.New("Secret Service is locked; unlock the keyring and retry")
	// ErrNotFound means no unlocked collection contains a matching item.
	ErrNotFound = errors.New("item not found in the Secret Service")
	// ErrUnavailable means the bus or Secret Service is not usable.
	ErrUnavailable = errors.New("Secret Service is unavailable")
)

const (
	serviceName     = "org.freedesktop.secrets"
	servicePath     = dbus.ObjectPath("/org/freedesktop/secrets")
	serviceIface    = "org.freedesktop.Secret.Service"
	collectionIface = "org.freedesktop.Secret.Collection"
	itemIface       = "org.freedesktop.Secret.Item"
)

// Bus is the D-Bus subset the client needs. Injectable so tests use a fake.
// Secrets are deliberately absent: reading one can prompt on a locked
// collection, so this package stays metadata-only.
type Bus interface {
	GetCollections() ([]dbus.ObjectPath, error)
	IsLocked(dbus.ObjectPath) (bool, error)
	SearchItems(dbus.ObjectPath, map[string]string) ([]dbus.ObjectPath, error)
	Items(dbus.ObjectPath) ([]dbus.ObjectPath, error)
	GetAttributes(dbus.ObjectPath) (map[string]string, error)
	SetAttributes(dbus.ObjectPath, map[string]string) error
}

// Item is a matching Secret Service item. Attributes is populated for every
// match returned by Search.
type Item struct {
	Path       dbus.ObjectPath
	Attributes map[string]string
}

// Client talks to one Secret Service bus. Close releases it.
type Client struct {
	bus   Bus
	close func()
}

// New wraps a caller-supplied bus. Close is a no-op because the caller owns it.
func New(b Bus) *Client {
	return &Client{bus: b, close: func() {}}
}

// OpenBus connects to the session bus and returns it with its release func.
func OpenBus() (Bus, func(), error) {
	conn, err := dbus.ConnectSessionBus()
	if err != nil {
		return nil, nil, err
	}
	return &sessionBus{conn: conn}, func() { _ = conn.Close() }, nil
}

// Open connects to the session bus.
func Open() (*Client, error) {
	b, closeBus, err := OpenBus()
	if err != nil {
		return nil, fmt.Errorf("%w: cannot connect to the session bus: %v", ErrUnavailable, err)
	}
	return &Client{bus: b, close: closeBus}, nil
}

// Close releases the underlying bus connection.
func (c *Client) Close() {
	if c.close != nil {
		c.close()
	}
}

// unlocked returns the collections that can be read, plus whether any locked
// collection was seen. Locked collections are never queried, so an item lookup
// never triggers an unlock prompt.
func (c *Client) unlocked() ([]dbus.ObjectPath, bool, error) {
	collections, err := c.bus.GetCollections()
	if err != nil {
		return nil, false, fmt.Errorf("%w: cannot list collections: %v", ErrUnavailable, err)
	}
	if len(collections) == 0 {
		return nil, false, ErrUnavailable
	}

	var unlocked []dbus.ObjectPath
	lockedSeen := false
	for _, collection := range collections {
		locked, err := c.bus.IsLocked(collection)
		if err != nil {
			return nil, false, fmt.Errorf("cannot read lock state of collection %s: %w", collection, err)
		}
		if locked {
			lockedSeen = true
			continue
		}
		unlocked = append(unlocked, collection)
	}
	if len(unlocked) == 0 {
		return nil, false, ErrLocked
	}
	return unlocked, lockedSeen, nil
}

// resolve reads the attributes of every path, which is all the metadata a
// caller gets without touching the stored secret.
func (c *Client) resolve(paths []dbus.ObjectPath) ([]Item, error) {
	items := make([]Item, 0, len(paths))
	for _, path := range paths {
		attributes, err := c.bus.GetAttributes(path)
		if err != nil {
			return nil, fmt.Errorf("cannot read attributes on item %s: %w", path, err)
		}
		items = append(items, Item{Path: path, Attributes: attributes})
	}
	return items, nil
}

// Search returns matching items from unlocked collections only. If every
// collection is locked it returns ErrLocked; no collections at all, or a bus
// that cannot be listed, is ErrUnavailable.
func (c *Client) Search(attributes map[string]string) ([]Item, error) {
	collections, lockedSeen, err := c.unlocked()
	if err != nil {
		return nil, err
	}

	var items []Item
	for _, collection := range collections {
		paths, err := c.bus.SearchItems(collection, attributes)
		if err != nil {
			return nil, fmt.Errorf("cannot search collection %s: %w", collection, err)
		}
		found, err := c.resolve(paths)
		if err != nil {
			return nil, err
		}
		items = append(items, found...)
	}

	switch {
	case len(items) > 0:
		return items, nil
	case lockedSeen:
		return nil, ErrLocked
	default:
		return nil, ErrNotFound
	}
}

// Items enumerates every item in every unlocked collection. It exists because
// SearchItems requires every supplied attribute to match, so a prefix lookup
// has to scan instead. Only metadata is read, never the secret. An empty result
// with a locked collection present is ErrLocked, not "no items".
func (c *Client) Items() ([]Item, error) {
	collections, lockedSeen, err := c.unlocked()
	if err != nil {
		return nil, err
	}

	var items []Item
	for _, collection := range collections {
		paths, err := c.bus.Items(collection)
		if err != nil {
			return nil, fmt.Errorf("cannot list items of collection %s: %w", collection, err)
		}
		found, err := c.resolve(paths)
		if err != nil {
			return nil, err
		}
		items = append(items, found...)
	}
	if len(items) == 0 && lockedSeen {
		return nil, ErrLocked
	}
	return items, nil
}

// FindOne is Search restricted to exactly one match. A locked collection with
// unknown contents still wins over "not found".
func (c *Client) FindOne(attributes map[string]string) (Item, error) {
	items, err := c.Search(attributes)
	if err != nil {
		return Item{}, err
	}
	if len(items) > 1 {
		return Item{}, fmt.Errorf("multiple Secret Service items match the query (%d matches)", len(items))
	}
	return items[0], nil
}

// SetAttributes replaces the attributes of an item.
func (c *Client) SetAttributes(path dbus.ObjectPath, attributes map[string]string) error {
	return c.bus.SetAttributes(path, attributes)
}

type sessionBus struct {
	conn *dbus.Conn
}

func (b *sessionBus) GetCollections() ([]dbus.ObjectPath, error) {
	object := b.conn.Object(serviceName, servicePath)
	var variant dbus.Variant
	if err := object.Call(
		"org.freedesktop.DBus.Properties.Get", 0, serviceIface, "Collections",
	).Store(&variant); err != nil {
		return nil, err
	}
	paths, ok := variant.Value().([]dbus.ObjectPath)
	if !ok {
		return nil, fmt.Errorf("unexpected Collections property type %T", variant.Value())
	}
	return paths, nil
}

func (b *sessionBus) IsLocked(path dbus.ObjectPath) (bool, error) {
	object := b.conn.Object(serviceName, path)
	var variant dbus.Variant
	if err := object.Call(
		"org.freedesktop.DBus.Properties.Get", 0, collectionIface, "Locked",
	).Store(&variant); err != nil {
		return false, err
	}
	locked, ok := variant.Value().(bool)
	if !ok {
		return false, fmt.Errorf("unexpected Locked property type %T", variant.Value())
	}
	return locked, nil
}

func (b *sessionBus) SearchItems(collection dbus.ObjectPath, attributes map[string]string) ([]dbus.ObjectPath, error) {
	object := b.conn.Object(serviceName, collection)
	var paths []dbus.ObjectPath
	if err := object.Call(
		collectionIface+".SearchItems", 0, attributes,
	).Store(&paths); err != nil {
		return nil, err
	}
	return paths, nil
}

func (b *sessionBus) Items(collection dbus.ObjectPath) ([]dbus.ObjectPath, error) {
	object := b.conn.Object(serviceName, collection)
	var variant dbus.Variant
	if err := object.Call(
		"org.freedesktop.DBus.Properties.Get", 0, collectionIface, "Items",
	).Store(&variant); err != nil {
		return nil, err
	}
	paths, ok := variant.Value().([]dbus.ObjectPath)
	if !ok {
		return nil, fmt.Errorf("unexpected Items property type %T", variant.Value())
	}
	return paths, nil
}

func (b *sessionBus) GetAttributes(item dbus.ObjectPath) (map[string]string, error) {
	object := b.conn.Object(serviceName, item)
	var variant dbus.Variant
	if err := object.Call(
		"org.freedesktop.DBus.Properties.Get", 0, itemIface, "Attributes",
	).Store(&variant); err != nil {
		return nil, err
	}
	attributes, ok := variant.Value().(map[string]string)
	if !ok {
		return nil, fmt.Errorf("unexpected Attributes property type %T", variant.Value())
	}
	return attributes, nil
}

func (b *sessionBus) SetAttributes(item dbus.ObjectPath, attributes map[string]string) error {
	object := b.conn.Object(serviceName, item)
	return object.Call(itemIface+".SetAttributes", 0, attributes).Err
}
