package remmina

import (
	"errors"
	"fmt"

	"github.com/godbus/dbus/v5"
)

var (
	// ErrLocked means every collection is locked. The user must unlock
	// KeePassXC and retry.
	ErrLocked = errors.New("KeePassXC Secret Service is locked")
	// ErrNotFound means no exposed collection contains the entry. It is not an
	// error: the entry may simply not be shared through Secret Service.
	ErrNotFound = errors.New("entry not found in the exposed Secret Service group")
	// ErrUnavailable means the bus or Secret Service is not usable.
	ErrUnavailable = errors.New("KeePassXC Secret Service is unavailable")
)

const (
	secretServiceName = "org.freedesktop.secrets"
	secretServicePath = dbus.ObjectPath("/org/freedesktop/secrets")
	serviceIface      = "org.freedesktop.Secret.Service"
	collectionIface   = "org.freedesktop.Secret.Collection"
	itemIface         = "org.freedesktop.Secret.Item"

	// libsecret adds the schema name as the xdg:schema attribute. KeePassXC
	// matches every supplied attribute, so the entry must carry it or Remmina's
	// lookup returns nothing even though filename and key match.
	schemaAttribute = "xdg:schema"
	remminaSchema   = "org.remmina.Password"
)

// SecretService sets the attributes KeePassXC uses to resolve a profile path to
// an entry password. It never receives or returns the password itself.
type SecretService interface {
	SetProfile(entryUUID, filename string) error
	// Visible reports whether the entry is exposed through the Secret Service.
	// It is read-only and lets --check ignore entries the user has not shared.
	Visible(entryUUID string) (bool, error)
}

// bus is the small subset of D-Bus calls the attribute update needs. Keeping it
// separate makes the locking/search flow testable with a fake.
type bus interface {
	GetCollections() ([]dbus.ObjectPath, error)
	IsLocked(dbus.ObjectPath) (bool, error)
	SearchItems(dbus.ObjectPath, map[string]string) ([]dbus.ObjectPath, error)
	GetAttributes(dbus.ObjectPath) (map[string]string, error)
	SetAttributes(dbus.ObjectPath, map[string]string) error
}

// DBusService is the real SecretService implementation. dial is replaceable in
// tests so a fake bus can be exercised through the public SetProfile path.
type DBusService struct {
	dial func() (bus, func(), error)
}

// NewDBusService returns a service backed by a fresh session-bus connection for
// each update.
func NewDBusService() *DBusService {
	return &DBusService{dial: dialSessionBus}
}

// dialBus returns a bus connection, falling back to the session bus when no
// dialer was injected.
func (s *DBusService) dialBus() (bus, func(), error) {
	dial := s.dial
	if dial == nil {
		dial = dialSessionBus
	}
	b, closeBus, err := dial()
	if err != nil {
		return nil, nil, fmt.Errorf("%w: cannot connect to the session bus: %v", ErrUnavailable, err)
	}
	return b, closeBus, nil
}

// SetProfile marks the entry with the profile path and tells KeePassXC to use
// the entry password for it.
func (s *DBusService) SetProfile(entryUUID, filename string) error {
	b, closeBus, err := s.dialBus()
	if err != nil {
		return err
	}
	defer closeBus()
	return setProfile(b, entryUUID, filename)
}

// Visible reports whether the entry is exposed through the Secret Service. A
// missing entry is not an error; locked or unusable services are.
func (s *DBusService) Visible(entryUUID string) (bool, error) {
	b, closeBus, err := s.dialBus()
	if err != nil {
		return false, err
	}
	defer closeBus()
	return visible(b, entryUUID)
}

func visible(b bus, entryUUID string) (bool, error) {
	_, err := findItem(b, entryUUID)
	switch {
	case err == nil:
		return true, nil
	case errors.Is(err, ErrNotFound):
		return false, nil
	default:
		return false, err
	}
}

// findItem returns the single item matching entryUUID in an unlocked
// collection. If no unlocked collection contains it but some collection was
// locked, the answer is inconclusive and ErrLocked is returned.
func findItem(b bus, entryUUID string) (dbus.ObjectPath, error) {
	collections, err := b.GetCollections()
	if err != nil {
		return "", fmt.Errorf("%w: cannot list collections: %v", ErrUnavailable, err)
	}
	if len(collections) == 0 {
		return "", ErrUnavailable
	}

	var unlocked []dbus.ObjectPath
	lockedSeen := false
	for _, collection := range collections {
		locked, err := b.IsLocked(collection)
		if err != nil {
			return "", fmt.Errorf("cannot read lock state of collection %s: %w", collection, err)
		}
		if locked {
			lockedSeen = true
			continue
		}
		unlocked = append(unlocked, collection)
	}
	if len(unlocked) == 0 {
		return "", ErrLocked
	}

	query := map[string]string{"Uuid": entryUUID}
	var matches []dbus.ObjectPath
	for _, collection := range unlocked {
		items, err := b.SearchItems(collection, query)
		if err != nil {
			return "", fmt.Errorf("cannot search collection %s: %w", collection, err)
		}
		matches = append(matches, items...)
	}

	switch {
	case len(matches) > 1:
		return "", fmt.Errorf("multiple Secret Service items match UUID %s", entryUUID)
	case len(matches) == 1:
		return matches[0], nil
	case lockedSeen:
		return "", ErrLocked
	default:
		return "", ErrNotFound
	}
}

func setProfile(b bus, entryUUID, filename string) error {
	item, err := findItem(b, entryUUID)
	if err != nil {
		return err
	}
	attributes := map[string]string{
		"filename":      filename,
		"key":           "password",
		schemaAttribute: remminaSchema,
	}
	current, err := b.GetAttributes(item)
	if err != nil {
		return fmt.Errorf("cannot read attributes on item %s: %w", item, err)
	}
	// Writing identical attributes would mark the database modified and can
	// retrigger a path unit watch, so skip the write when it is a no-op.
	if current["filename"] == attributes["filename"] &&
		current["key"] == attributes["key"] &&
		current[schemaAttribute] == attributes[schemaAttribute] {
		return nil
	}
	if err := b.SetAttributes(item, attributes); err != nil {
		return fmt.Errorf("cannot set attributes on item %s: %w", item, err)
	}
	return nil
}

func dialSessionBus() (bus, func(), error) {
	conn, err := dbus.ConnectSessionBus()
	if err != nil {
		return nil, nil, err
	}
	return &sessionBus{conn: conn}, func() { _ = conn.Close() }, nil
}

type sessionBus struct {
	conn *dbus.Conn
}

func (b *sessionBus) GetCollections() ([]dbus.ObjectPath, error) {
	object := b.conn.Object(secretServiceName, secretServicePath)
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
	object := b.conn.Object(secretServiceName, path)
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
	object := b.conn.Object(secretServiceName, collection)
	var paths []dbus.ObjectPath
	if err := object.Call(
		"org.freedesktop.Secret.Collection.SearchItems", 0, attributes,
	).Store(&paths); err != nil {
		return nil, err
	}
	return paths, nil
}

func (b *sessionBus) GetAttributes(item dbus.ObjectPath) (map[string]string, error) {
	object := b.conn.Object(secretServiceName, item)
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
	object := b.conn.Object(secretServiceName, item)
	return object.Call("org.freedesktop.Secret.Item.SetAttributes", 0, attributes).Err
}
