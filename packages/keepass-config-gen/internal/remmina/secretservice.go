package remmina

import (
	"errors"
	"fmt"

	"keepass-config-gen/internal/secretservice"
)

// Err aliases keep errors.Is working for callers that match on remmina errors.
var (
	ErrLocked      = secretservice.ErrLocked
	ErrNotFound    = secretservice.ErrNotFound
	ErrUnavailable = secretservice.ErrUnavailable
)

const (
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

// DBusService is the real SecretService implementation. dial is replaceable in
// tests so a fake bus can be exercised through the public SetProfile path.
type DBusService struct {
	dial func() (secretservice.Bus, func(), error)
}

// NewDBusService returns a service backed by a fresh session-bus connection for
// each update.
func NewDBusService() *DBusService {
	return &DBusService{}
}

// connect dials a bus and wraps it in a client. The returned func releases the
// connection. dial defaults to the session bus.
func (s *DBusService) connect() (*secretservice.Client, func(), error) {
	dial := s.dial
	if dial == nil {
		dial = secretservice.OpenBus
	}
	b, closeBus, err := dial()
	if err != nil {
		return nil, nil, fmt.Errorf("%w: cannot connect to the session bus: %v", ErrUnavailable, err)
	}
	return secretservice.New(b), closeBus, nil
}

// SetProfile marks the entry with the profile path and tells KeePassXC to use
// the entry password for it.
func (s *DBusService) SetProfile(entryUUID, filename string) error {
	client, closeClient, err := s.connect()
	if err != nil {
		return err
	}
	defer closeClient()
	return setProfile(client, entryUUID, filename)
}

// Visible reports whether the entry is exposed through the Secret Service. A
// missing entry is not an error; locked or unusable services are.
func (s *DBusService) Visible(entryUUID string) (bool, error) {
	client, closeClient, err := s.connect()
	if err != nil {
		return false, err
	}
	defer closeClient()
	return visible(client, entryUUID)
}

// uuidQuery is the attribute query KeePassXC exposes each entry UUID under.
func uuidQuery(entryUUID string) map[string]string {
	return map[string]string{"Uuid": entryUUID}
}

func visible(client *secretservice.Client, entryUUID string) (bool, error) {
	_, err := client.FindOne(uuidQuery(entryUUID))
	switch {
	case err == nil:
		return true, nil
	case errors.Is(err, ErrNotFound):
		return false, nil
	default:
		return false, err
	}
}

func setProfile(client *secretservice.Client, entryUUID, filename string) error {
	item, err := client.FindOne(uuidQuery(entryUUID))
	if err != nil {
		return err
	}
	attributes := map[string]string{
		"filename":      filename,
		"key":           "password",
		schemaAttribute: remminaSchema,
	}
	// Writing identical attributes would mark the database modified and can
	// retrigger a path unit watch, so skip the write when it is a no-op.
	current := item.Attributes
	if current["filename"] == attributes["filename"] &&
		current["key"] == attributes["key"] &&
		current[schemaAttribute] == attributes[schemaAttribute] {
		return nil
	}
	if err := client.SetAttributes(item.Path, attributes); err != nil {
		return fmt.Errorf("cannot set attributes on item %s: %w", item.Path, err)
	}
	return nil
}
