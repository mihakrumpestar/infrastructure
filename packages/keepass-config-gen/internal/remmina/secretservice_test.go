package remmina

import (
	"errors"
	"os"
	"strings"
	"testing"

	"github.com/godbus/dbus/v5"
)

type fakeBus struct {
	collections []dbus.ObjectPath
	locked      map[dbus.ObjectPath]bool
	items       map[dbus.ObjectPath][]dbus.ObjectPath

	getErr      error
	lockErr     error
	searchErr   error
	getAttrsErr error
	setErr      error

	searches map[dbus.ObjectPath]map[string]string
	current  map[dbus.ObjectPath]map[string]string
	attrs    map[dbus.ObjectPath]map[string]string
	setCalls int
}

func (b *fakeBus) GetCollections() ([]dbus.ObjectPath, error) {
	if b.getErr != nil {
		return nil, b.getErr
	}
	return b.collections, nil
}

func (b *fakeBus) IsLocked(collection dbus.ObjectPath) (bool, error) {
	if b.lockErr != nil {
		return false, b.lockErr
	}
	return b.locked[collection], nil
}

func (b *fakeBus) SearchItems(collection dbus.ObjectPath, query map[string]string) ([]dbus.ObjectPath, error) {
	if b.searchErr != nil {
		return nil, b.searchErr
	}
	if b.searches == nil {
		b.searches = make(map[dbus.ObjectPath]map[string]string)
	}
	b.searches[collection] = query
	return b.items[collection], nil
}

func (b *fakeBus) GetAttributes(item dbus.ObjectPath) (map[string]string, error) {
	if b.getAttrsErr != nil {
		return nil, b.getAttrsErr
	}
	return b.current[item], nil
}

func (b *fakeBus) SetAttributes(item dbus.ObjectPath, attributes map[string]string) error {
	b.setCalls++
	if b.setErr != nil {
		return b.setErr
	}
	if b.attrs == nil {
		b.attrs = make(map[dbus.ObjectPath]map[string]string)
	}
	b.attrs[item] = attributes
	return nil
}

func TestSetProfileSuccess(t *testing.T) {
	collection := dbus.ObjectPath("/org/freedesktop/secrets/collection/login")
	item := dbus.ObjectPath("/org/freedesktop/secrets/collection/login/1")
	b := &fakeBus{
		collections: []dbus.ObjectPath{collection},
		items:       map[dbus.ObjectPath][]dbus.ObjectPath{collection: {item}},
	}
	if err := setProfile(b, "0123456789abcdef", "/data/keepass_host-01234567.remmina"); err != nil {
		t.Fatal(err)
	}
	if got := b.searches[collection]["Uuid"]; got != "0123456789abcdef" {
		t.Fatalf("search UUID = %q", got)
	}
	want := map[string]string{
		"filename":   "/data/keepass_host-01234567.remmina",
		"key":        "password",
		"xdg:schema": "org.remmina.Password",
	}
	got := b.attrs[item]
	if got["filename"] != want["filename"] || got["key"] != want["key"] || got["xdg:schema"] != want["xdg:schema"] {
		t.Fatalf("attributes = %#v, want %#v", got, want)
	}
}

func TestSetProfileSkipsMatchingAttributes(t *testing.T) {
	collection := dbus.ObjectPath("/c")
	item := dbus.ObjectPath("/c/1")
	b := &fakeBus{
		collections: []dbus.ObjectPath{collection},
		items:       map[dbus.ObjectPath][]dbus.ObjectPath{collection: {item}},
		current: map[dbus.ObjectPath]map[string]string{
			item: {"filename": "/data/p.remmina", "key": "password", "xdg:schema": "org.remmina.Password"},
		},
	}
	if err := setProfile(b, "uuid", "/data/p.remmina"); err != nil {
		t.Fatal(err)
	}
	if b.setCalls != 0 {
		t.Fatalf("SetAttributes called %d times for unchanged attributes", b.setCalls)
	}
}

func TestSetProfileUpdatesChangedAttributes(t *testing.T) {
	collection := dbus.ObjectPath("/c")
	item := dbus.ObjectPath("/c/1")
	b := &fakeBus{
		collections: []dbus.ObjectPath{collection},
		items:       map[dbus.ObjectPath][]dbus.ObjectPath{collection: {item}},
		current: map[dbus.ObjectPath]map[string]string{
			item: {"filename": "/data/old.remmina", "key": "password", "xdg:schema": "org.remmina.Password"},
		},
	}
	if err := setProfile(b, "uuid", "/data/new.remmina"); err != nil {
		t.Fatal(err)
	}
	if b.attrs[item]["filename"] != "/data/new.remmina" {
		t.Fatalf("attributes = %#v", b.attrs[item])
	}
}

func TestSetProfileGetAttributesFailure(t *testing.T) {
	collection := dbus.ObjectPath("/c")
	item := dbus.ObjectPath("/c/1")
	b := &fakeBus{
		collections: []dbus.ObjectPath{collection},
		items:       map[dbus.ObjectPath][]dbus.ObjectPath{collection: {item}},
		getAttrsErr: errors.New("denied"),
	}
	err := setProfile(b, "uuid", "/data/p.remmina")
	if err == nil || !strings.Contains(err.Error(), "cannot read attributes") {
		t.Fatalf("error = %v", err)
	}
	if b.setCalls != 0 {
		t.Fatal("SetAttributes called after GetAttributes failed")
	}
}

func TestSetProfileLocked(t *testing.T) {
	collection := dbus.ObjectPath("/c")
	b := &fakeBus{
		collections: []dbus.ObjectPath{collection},
		locked:      map[dbus.ObjectPath]bool{collection: true},
	}
	if err := setProfile(b, "uuid", "/data/p.remmina"); !errors.Is(err, ErrLocked) {
		t.Fatalf("error = %v, want ErrLocked", err)
	}
	if len(b.attrs) != 0 {
		t.Fatal("attributes changed while locked")
	}
}

func TestSetProfileNotFound(t *testing.T) {
	collection := dbus.ObjectPath("/c")
	b := &fakeBus{collections: []dbus.ObjectPath{collection}}
	if err := setProfile(b, "uuid", "/data/p.remmina"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("error = %v, want ErrNotFound", err)
	}
}

func TestSetProfileSetAttributesFailure(t *testing.T) {
	collection := dbus.ObjectPath("/c")
	item := dbus.ObjectPath("/c/1")
	b := &fakeBus{
		collections: []dbus.ObjectPath{collection},
		items:       map[dbus.ObjectPath][]dbus.ObjectPath{collection: {item}},
		setErr:      errors.New("denied"),
	}
	err := setProfile(b, "uuid", "/data/p.remmina")
	if err == nil || !strings.Contains(err.Error(), "cannot set attributes") || !strings.Contains(err.Error(), "denied") {
		t.Fatalf("error = %v", err)
	}
	if errors.Is(err, ErrNotFound) || errors.Is(err, ErrLocked) {
		t.Fatalf("failure was misclassified: %v", err)
	}
}

func TestSetProfileUnavailable(t *testing.T) {
	if err := setProfile(&fakeBus{}, "uuid", "/data/p.remmina"); !errors.Is(err, ErrUnavailable) {
		t.Fatalf("empty collections: %v, want ErrUnavailable", err)
	}
	if err := setProfile(&fakeBus{getErr: errors.New("no bus")}, "uuid", "/data/p.remmina"); !errors.Is(err, ErrUnavailable) {
		t.Fatalf("get error: %v, want ErrUnavailable", err)
	}
}

func TestSetProfileUsesUnlockedCollection(t *testing.T) {
	locked := dbus.ObjectPath("/locked")
	unlocked := dbus.ObjectPath("/unlocked")
	item := dbus.ObjectPath("/unlocked/1")
	b := &fakeBus{
		collections: []dbus.ObjectPath{locked, unlocked},
		locked:      map[dbus.ObjectPath]bool{locked: true},
		items: map[dbus.ObjectPath][]dbus.ObjectPath{
			locked:   {dbus.ObjectPath("/locked/1")},
			unlocked: {item},
		},
	}
	if err := setProfile(b, "uuid", "/data/p.remmina"); err != nil {
		t.Fatal(err)
	}
	if _, ok := b.attrs[dbus.ObjectPath("/locked/1")]; ok {
		t.Fatal("attributes changed on a locked collection")
	}
	if b.attrs[item] == nil {
		t.Fatal("attributes not changed on the unlocked collection")
	}
}

// TestLiveSecretService exercises the real session bus. It is opt-in because it
// needs a running Secret Service provider. With KeePassXC locked it returns
// ErrLocked; with the database unlocked it returns ErrNotFound for a random
// UUID. Either proves the Service.Collections property lookup works.
func TestLiveSecretService(t *testing.T) {
	if os.Getenv("REMMINA_LIVE_TEST") == "" {
		t.Skip("set REMMINA_LIVE_TEST=1 to test the live session bus")
	}
	err := NewDBusService().SetProfile("00000000000000000000000000000000", "/tmp/keepass-none.remmina")
	if err == nil {
		t.Fatal("expected a lookup error for a random UUID")
	}
	if errors.Is(err, ErrUnavailable) {
		t.Fatalf("live Secret Service unavailable: %v", err)
	}
	if !errors.Is(err, ErrLocked) && !errors.Is(err, ErrNotFound) {
		t.Fatalf("unexpected live error: %v", err)
	}
}

func TestDBusServiceInjectedBus(t *testing.T) {
	collection := dbus.ObjectPath("/c")
	item := dbus.ObjectPath("/c/1")
	fake := &fakeBus{
		collections: []dbus.ObjectPath{collection},
		items:       map[dbus.ObjectPath][]dbus.ObjectPath{collection: {item}},
	}
	svc := &DBusService{dial: func() (bus, func(), error) {
		return fake, func() {}, nil
	}}
	if err := svc.SetProfile("uuid", "/data/p.remmina"); err != nil {
		t.Fatal(err)
	}
	if fake.attrs[item]["key"] != "password" {
		t.Fatalf("attributes = %#v", fake.attrs[item])
	}
}

func TestVisible(t *testing.T) {
	collection := dbus.ObjectPath("/c")
	item := dbus.ObjectPath("/c/1")
	b := &fakeBus{
		collections: []dbus.ObjectPath{collection},
		items:       map[dbus.ObjectPath][]dbus.ObjectPath{collection: {item}},
	}
	got, err := visible(b, "uuid")
	if err != nil {
		t.Fatal(err)
	}
	if !got {
		t.Fatal("visible returned false for a matching item")
	}

	missing, err := visible(&fakeBus{collections: []dbus.ObjectPath{collection}}, "uuid")
	if err != nil {
		t.Fatalf("missing entry: %v", err)
	}
	if missing {
		t.Fatal("visible returned true for a missing entry")
	}
}

func TestVisibleLockedWhenMatchMayBeHidden(t *testing.T) {
	locked := dbus.ObjectPath("/locked")
	unlocked := dbus.ObjectPath("/unlocked")
	b := &fakeBus{
		collections: []dbus.ObjectPath{locked, unlocked},
		locked:      map[dbus.ObjectPath]bool{locked: true},
	}
	if _, err := visible(b, "uuid"); !errors.Is(err, ErrLocked) {
		t.Fatalf("error = %v, want ErrLocked", err)
	}
	if _, err := findItem(b, "uuid"); !errors.Is(err, ErrLocked) {
		t.Fatalf("findItem error = %v, want ErrLocked", err)
	}
}

func TestFindItemRejectsMultipleMatches(t *testing.T) {
	first := dbus.ObjectPath("/first")
	second := dbus.ObjectPath("/second")
	b := &fakeBus{
		collections: []dbus.ObjectPath{first, second},
		items: map[dbus.ObjectPath][]dbus.ObjectPath{
			first:  {dbus.ObjectPath("/first/1")},
			second: {dbus.ObjectPath("/second/1")},
		},
	}
	if _, err := findItem(b, "uuid"); err == nil || !strings.Contains(err.Error(), "multiple") {
		t.Fatalf("findItem error = %v, want multiple-match error", err)
	}
	if _, err := visible(b, "uuid"); err == nil || !strings.Contains(err.Error(), "multiple") {
		t.Fatalf("visible error = %v, want multiple-match error", err)
	}
	if err := setProfile(b, "uuid", "/data/p.remmina"); err == nil || !strings.Contains(err.Error(), "multiple") {
		t.Fatalf("setProfile error = %v, want multiple-match error", err)
	}
}
