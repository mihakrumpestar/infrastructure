package secretservice

import (
	"errors"
	"strings"
	"testing"

	"github.com/godbus/dbus/v5"
)

// fakeBus is a scriptable Bus. Search and Items return the items registered for
// the queried collection; attributes come from current.
type fakeBus struct {
	collections []dbus.ObjectPath
	locked      map[dbus.ObjectPath]bool
	items       map[dbus.ObjectPath][]dbus.ObjectPath

	getErr    error
	lockErr   error
	searchErr error
	itemsErr  error
	attrsErr  error
	setErr    error

	queries    map[dbus.ObjectPath]map[string]string
	enumerated []dbus.ObjectPath
	current    map[dbus.ObjectPath]map[string]string
	set        map[dbus.ObjectPath]map[string]string
	setCalls   int
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

func (b *fakeBus) SearchItems(collection dbus.ObjectPath, attributes map[string]string) ([]dbus.ObjectPath, error) {
	if b.searchErr != nil {
		return nil, b.searchErr
	}
	if b.queries == nil {
		b.queries = make(map[dbus.ObjectPath]map[string]string)
	}
	b.queries[collection] = attributes
	return b.items[collection], nil
}

// Items returns every item of a collection and records the enumeration so
// tests can assert that locked collections were never touched.
func (b *fakeBus) Items(collection dbus.ObjectPath) ([]dbus.ObjectPath, error) {
	b.enumerated = append(b.enumerated, collection)
	if b.itemsErr != nil {
		return nil, b.itemsErr
	}
	return b.items[collection], nil
}

func (b *fakeBus) GetAttributes(item dbus.ObjectPath) (map[string]string, error) {
	if b.attrsErr != nil {
		return nil, b.attrsErr
	}
	return b.current[item], nil
}

func (b *fakeBus) SetAttributes(item dbus.ObjectPath, attributes map[string]string) error {
	b.setCalls++
	if b.setErr != nil {
		return b.setErr
	}
	if b.set == nil {
		b.set = make(map[dbus.ObjectPath]map[string]string)
	}
	b.set[item] = attributes
	return nil
}

func TestItemsEnumeratesUnlockedCollections(t *testing.T) {
	locked := dbus.ObjectPath("/locked")
	first := dbus.ObjectPath("/first")
	second := dbus.ObjectPath("/second")
	b := &fakeBus{
		collections: []dbus.ObjectPath{locked, first, second},
		locked:      map[dbus.ObjectPath]bool{locked: true},
		items: map[dbus.ObjectPath][]dbus.ObjectPath{
			locked: {dbus.ObjectPath("/locked/1")},
			first:  {dbus.ObjectPath("/first/1")},
			second: {dbus.ObjectPath("/second/1"), dbus.ObjectPath("/second/2")},
		},
		current: map[dbus.ObjectPath]map[string]string{
			dbus.ObjectPath("/first/1"):  {"service": "github.com", "account": "a"},
			dbus.ObjectPath("/second/1"): {"service": "gitlab.com"},
			dbus.ObjectPath("/second/2"): {"service": "github.com"},
		},
	}
	items, err := New(b).Items()
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != 3 {
		t.Fatalf("items = %#v, want 3", items)
	}
	if items[0].Attributes["service"] != "github.com" {
		t.Fatalf("attributes not populated: %#v", items[0])
	}
	for _, collection := range b.enumerated {
		if collection == locked {
			t.Fatal("locked collection was enumerated")
		}
	}
	if len(b.enumerated) != 2 {
		t.Fatalf("enumerated %v, want the two unlocked collections", b.enumerated)
	}
}

func TestItemsErrors(t *testing.T) {
	collection := dbus.ObjectPath("/c")
	locked := dbus.ObjectPath("/locked")

	t.Run("all locked", func(t *testing.T) {
		b := &fakeBus{collections: []dbus.ObjectPath{locked}, locked: map[dbus.ObjectPath]bool{locked: true}}
		if _, err := New(b).Items(); !errors.Is(err, ErrLocked) {
			t.Fatalf("error = %v, want ErrLocked", err)
		}
	})

	t.Run("empty unlocked with locked collection", func(t *testing.T) {
		b := &fakeBus{
			collections: []dbus.ObjectPath{collection, locked},
			locked:      map[dbus.ObjectPath]bool{locked: true},
		}
		if _, err := New(b).Items(); !errors.Is(err, ErrLocked) {
			t.Fatalf("error = %v, want ErrLocked", err)
		}
	})

	t.Run("no collections", func(t *testing.T) {
		if _, err := New(&fakeBus{}).Items(); !errors.Is(err, ErrUnavailable) {
			t.Fatalf("error = %v, want ErrUnavailable", err)
		}
	})

	t.Run("cannot list items", func(t *testing.T) {
		b := &fakeBus{collections: []dbus.ObjectPath{collection}, itemsErr: errors.New("denied")}
		_, err := New(b).Items()
		if err == nil || !strings.Contains(err.Error(), "cannot list items of collection") {
			t.Fatalf("error = %v", err)
		}
	})

	t.Run("cannot read attributes", func(t *testing.T) {
		b := &fakeBus{
			collections: []dbus.ObjectPath{collection},
			items:       map[dbus.ObjectPath][]dbus.ObjectPath{collection: {dbus.ObjectPath("/c/1")}},
			attrsErr:    errors.New("denied"),
		}
		_, err := New(b).Items()
		if err == nil || !strings.Contains(err.Error(), "cannot read attributes") {
			t.Fatalf("error = %v", err)
		}
	})
}

func TestSearchAggregatesUnlockedCollections(t *testing.T) {
	locked := dbus.ObjectPath("/locked")
	first := dbus.ObjectPath("/first")
	second := dbus.ObjectPath("/second")
	b := &fakeBus{
		collections: []dbus.ObjectPath{locked, first, second},
		locked:      map[dbus.ObjectPath]bool{locked: true},
		items: map[dbus.ObjectPath][]dbus.ObjectPath{
			locked: {dbus.ObjectPath("/locked/1")},
			first:  {dbus.ObjectPath("/first/1")},
			second: {dbus.ObjectPath("/second/1")},
		},
		current: map[dbus.ObjectPath]map[string]string{
			dbus.ObjectPath("/first/1"):  {"uuid": "a"},
			dbus.ObjectPath("/second/1"): {"uuid": "b"},
		},
	}
	items, err := New(b).Search(map[string]string{"uuid": "a"})
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != 2 {
		t.Fatalf("items = %#v, want 2 matches", items)
	}
	if items[0].Attributes["uuid"] != "a" || items[1].Attributes["uuid"] != "b" {
		t.Fatalf("attributes not populated: %#v", items)
	}
	if _, ok := b.queries[locked]; ok {
		t.Fatal("locked collection was searched")
	}
	if got := b.queries[first]["uuid"]; got != "a" {
		t.Fatalf("query attributes = %#v", b.queries[first])
	}
}

func TestSearchErrors(t *testing.T) {
	collection := dbus.ObjectPath("/c")
	locked := dbus.ObjectPath("/locked")
	lockedBus := func() *fakeBus {
		return &fakeBus{
			collections: []dbus.ObjectPath{collection, locked},
			locked:      map[dbus.ObjectPath]bool{locked: true},
		}
	}

	for _, tc := range []struct {
		name string
		bus  *fakeBus
		want error
	}{
		{"no collections", &fakeBus{}, ErrUnavailable},
		{"cannot list", &fakeBus{getErr: errors.New("no bus")}, ErrUnavailable},
		{"all locked", &fakeBus{collections: []dbus.ObjectPath{locked}, locked: map[dbus.ObjectPath]bool{locked: true}}, ErrLocked},
		{"match may hide in locked", lockedBus(), ErrLocked},
		{"no match", &fakeBus{collections: []dbus.ObjectPath{collection}}, ErrNotFound},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if _, err := New(tc.bus).Search(nil); !errors.Is(err, tc.want) {
				t.Fatalf("error = %v, want %v", err, tc.want)
			}
		})
	}

	t.Run("lock state failure", func(t *testing.T) {
		b := &fakeBus{collections: []dbus.ObjectPath{collection}, lockErr: errors.New("denied")}
		_, err := New(b).Search(nil)
		if err == nil || !strings.Contains(err.Error(), "lock state") {
			t.Fatalf("error = %v", err)
		}
	})

	t.Run("search failure", func(t *testing.T) {
		b := &fakeBus{collections: []dbus.ObjectPath{collection}, searchErr: errors.New("denied")}
		_, err := New(b).Search(nil)
		if err == nil || !strings.Contains(err.Error(), "cannot search collection") {
			t.Fatalf("error = %v", err)
		}
	})

	t.Run("attribute failure", func(t *testing.T) {
		b := &fakeBus{
			collections: []dbus.ObjectPath{collection},
			items:       map[dbus.ObjectPath][]dbus.ObjectPath{collection: {dbus.ObjectPath("/c/1")}},
			attrsErr:    errors.New("denied"),
		}
		_, err := New(b).Search(nil)
		if err == nil || !strings.Contains(err.Error(), "cannot read attributes") {
			t.Fatalf("error = %v", err)
		}
	})
}

func TestFindOne(t *testing.T) {
	collection := dbus.ObjectPath("/c")
	item := dbus.ObjectPath("/c/1")
	b := &fakeBus{
		collections: []dbus.ObjectPath{collection},
		items:       map[dbus.ObjectPath][]dbus.ObjectPath{collection: {item}},
	}
	got, err := New(b).FindOne(map[string]string{"uuid": "x"})
	if err != nil {
		t.Fatal(err)
	}
	if got.Path != item {
		t.Fatalf("path = %s, want %s", got.Path, item)
	}

	single := dbus.ObjectPath("/one")
	second := dbus.ObjectPath("/two")
	multiple := &fakeBus{
		collections: []dbus.ObjectPath{single, second},
		items: map[dbus.ObjectPath][]dbus.ObjectPath{
			single: {dbus.ObjectPath("/one/1")},
			second: {dbus.ObjectPath("/two/1")},
		},
	}
	_, err = New(multiple).FindOne(nil)
	if err == nil || !strings.Contains(err.Error(), "2 matches") {
		t.Fatalf("error = %v, want a 2-match error", err)
	}

	if _, err := New(&fakeBus{}).FindOne(nil); !errors.Is(err, ErrUnavailable) {
		t.Fatalf("error = %v, want ErrUnavailable", err)
	}
}

func TestSetAttributes(t *testing.T) {
	item := dbus.ObjectPath("/c/1")
	b := &fakeBus{}
	attributes := map[string]string{"key": "password"}
	if err := New(b).SetAttributes(item, attributes); err != nil {
		t.Fatal(err)
	}
	if b.set[item]["key"] != "password" {
		t.Fatalf("attributes = %#v", b.set[item])
	}

	b.setErr = errors.New("denied")
	if err := New(b).SetAttributes(item, attributes); err == nil {
		t.Fatal("SetAttributes ignored the bus error")
	}
}

// Close must never nil-panic and must be a no-op for an injected bus.
func TestCloseInjectedBus(t *testing.T) {
	b := &fakeBus{}
	client := New(b)
	client.Close()
	if _, err := client.Search(nil); !errors.Is(err, ErrUnavailable) {
		t.Fatalf("client unusable after Close: %v", err)
	}
}
