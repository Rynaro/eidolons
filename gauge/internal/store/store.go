// Package store owns one controller-instance transaction boundary. It provides
// no account-wide guarantee across independent instances or devices.
package store

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"time"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
	bolt "go.etcd.io/bbolt"
)

var buckets = []string{"meta", "roots", "legacy", "history", "context", "knowledge", "policy", "operations"}
var families = []string{"history", "context", "knowledge", "policy"}

type Store struct {
	db               *bolt.DB
	authorizer       policyAuthorizer
	policyCut        func(string) error
	reservationFault reservationFaultState
}
type Snapshot struct {
	StoreID string                            `json:"store_id"`
	Roots   map[string]contract.Root          `json:"roots"`
	Legacy  map[string][]contract.LegacyEvent `json:"legacy"`
	Records map[string][]contract.Record      `json:"records"`
}

func regular(path string) error {
	info, e := os.Lstat(path)
	if e != nil {
		return e
	}
	if !info.Mode().IsRegular() {
		return errors.New("store must be a regular file, not a symlink")
	}
	return nil
}
func options(timeout time.Duration, readOnly bool) (*bolt.Options, error) {
	if timeout <= 0 || timeout > 300*time.Second {
		return nil, errors.New("store lock timeout must be positive and at most 300 seconds")
	}
	return &bolt.Options{Timeout: timeout, ReadOnly: readOnly}, nil
}

func guardBase(tx *bolt.Tx, version string) error {
	for _, name := range buckets {
		if tx.Bucket([]byte(name)) == nil {
			return fmt.Errorf("incomplete controller state: missing %s; explicit recovery required", name)
		}
	}
	meta := tx.Bucket([]byte("meta"))
	if !bytes.Equal(meta.Get([]byte("schema")), []byte(version)) {
		return errors.New("unsupported store schema or missing migration; state left unchanged")
	}
	if len(meta.Get([]byte("store_id"))) == 0 {
		return errors.New("missing controller identity")
	}
	return tx.Bucket([]byte("roots")).ForEach(func(k, v []byte) error {
		if v == nil {
			return errors.New("invalid root bucket")
		}
		var r contract.Root
		if e := json.Unmarshal(v, &r); e != nil {
			return e
		}
		if string(k) != r.ID {
			return errors.New("root identity/key mismatch")
		}
		return r.Validate()
	})
}

func guard(tx *bolt.Tx) error {
	if m := tx.Bucket([]byte("meta")); m != nil && bytes.Equal(m.Get([]byte("schema")), []byte("1")) {
		return errors.New("migration_required: explicitly migrate schema 1 to 2")
	}
	if e := guardBase(tx, "2"); e != nil {
		return e
	}
	if e := guardPolicy(tx); e != nil {
		return e
	}
	if e := guardObservation(tx); e != nil {
		return e
	}
	if e := guardInstrument(tx); e != nil {
		return e
	}
	if e := guardReservation(tx); e != nil {
		return e
	}
	if e := guardDispatch(tx); e != nil {
		return e
	}
	if e := guardCompiler(tx); e != nil {
		return e
	}
	if e := guardAcceptance(tx); e != nil {
		return e
	}
	if e := guardStatus(tx); e != nil {
		return e
	}
	if e := guardRamza(tx); e != nil {
		return e
	}
	if e := guardVivi(tx); e != nil {
		return e
	}
	return guardContext(tx)
}

// Create only creates a previously absent file. Failed initialization never
// truncates or replaces an existing database, legacy run or unknown file.
func Create(path, id string) error {
	if id == "" {
		return errors.New("store identity required")
	}
	f, e := os.OpenFile(path, os.O_RDWR|os.O_CREATE|os.O_EXCL, 0600)
	if e != nil {
		return e
	}
	if e = f.Close(); e != nil {
		return e
	}
	complete := false
	defer func() {
		if !complete {
			_ = os.Remove(path)
		}
	}()
	db, e := bolt.Open(path, 0600, &bolt.Options{Timeout: time.Second})
	if e != nil {
		return e
	}
	e = db.Update(func(tx *bolt.Tx) error {
		for _, name := range buckets {
			if _, e := tx.CreateBucket([]byte(name)); e != nil {
				return e
			}
		}
		meta := tx.Bucket([]byte("meta"))
		if e := meta.Put([]byte("schema"), []byte("2")); e != nil {
			return e
		}
		if e := meta.Put([]byte("store_id"), []byte(id)); e != nil {
			return e
		}
		if e := initializePolicy(tx, id, "new-store"); e != nil {
			return e
		}
		if e := initializeObservation(tx, id, "new-store"); e != nil {
			return e
		}
		if e := initializeInstrument(tx, id, "new-store"); e != nil {
			return e
		}
		if e := initializeReservation(tx, id, "new-store"); e != nil {
			return e
		}
		if e := initializeDispatch(tx, id, "new-store"); e != nil {
			return e
		}
		if e := initializeCompiler(tx, id, "new-store"); e != nil {
			return e
		}
		if e := initializeAcceptance(tx, id, "new-store"); e != nil {
			return e
		}
		if e := initializeDelivery(tx, id, "new-store"); e != nil {
			return e
		}
		if e := initializeEvaluation(tx, id, "new-store"); e != nil {
			return e
		}
		if e := initializeStatus(tx, id, "new-store"); e != nil {
			return e
		}
		if e := initializeRamza(tx, id, "new-store"); e != nil {
			return e
		}
		if e := initializeVivi(tx, id, "new-store"); e != nil {
			return e
		}
		return initializeContext(tx, id, "new-store")
	})
	closeErr := db.Close()
	if e != nil {
		return e
	}
	if closeErr != nil {
		return closeErr
	}
	dir, e := os.Open(filepath.Dir(path))
	if e != nil {
		return e
	}
	e = dir.Sync()
	_ = dir.Close()
	if e != nil {
		return e
	}
	complete = true
	return nil
}

// Inspect never opens writable or creates a missing file.
func Inspect(path string, timeout time.Duration) (Snapshot, error) {
	var result Snapshot
	if e := regular(path); e != nil {
		return result, e
	}
	opts, e := options(timeout, true)
	if e != nil {
		return result, e
	}
	db, e := bolt.Open(path, 0600, opts)
	if e != nil {
		return result, e
	}
	defer db.Close()
	e = db.View(func(tx *bolt.Tx) error { var e error; result, e = snapshot(tx); return e })
	return result, e
}

// Open checks unsupported state read-only before requesting a write handle.
// The second guard closes the version race between the two lock acquisitions.
func Open(path string, timeout time.Duration) (*Store, error) {
	if _, e := Inspect(path, timeout); e != nil {
		return nil, e
	}
	if e := regular(path); e != nil {
		return nil, e
	}
	opts, e := options(timeout, false)
	if e != nil {
		return nil, e
	}
	db, e := bolt.Open(path, 0600, opts)
	if e != nil {
		return nil, e
	}
	if e = db.View(guard); e != nil {
		_ = db.Close()
		return nil, e
	}
	return &Store{db: db}, nil
}
func (s *Store) Close() error { return s.db.Close() }
func (s *Store) Snapshot() (Snapshot, error) {
	var result Snapshot
	e := s.db.View(func(tx *bolt.Tx) error { var e error; result, e = snapshot(tx); return e })
	return result, e
}

func snapshot(tx *bolt.Tx) (Snapshot, error) { return snapshotAt(tx, "2") }
func snapshotAt(tx *bolt.Tx, version string) (Snapshot, error) {
	result := Snapshot{Roots: map[string]contract.Root{}, Legacy: map[string][]contract.LegacyEvent{}, Records: map[string][]contract.Record{}}
	if e := func() error {
		if version == "1" {
			return guardBase(tx, "1")
		}
		return guard(tx)
	}(); e != nil {
		return result, e
	}
	result.StoreID = string(tx.Bucket([]byte("meta")).Get([]byte("store_id")))
	e := tx.Bucket([]byte("roots")).ForEach(func(k, v []byte) error {
		var r contract.Root
		if e := json.Unmarshal(v, &r); e != nil {
			return e
		}
		id := string(k)
		result.Roots[id] = r
		result.Records[id] = []contract.Record{}
		result.Legacy[id] = []contract.LegacyEvent{}
		legacy := tx.Bucket([]byte("legacy")).Get(k)
		if legacy == nil {
			return errors.New("incomplete import: legacy inventory missing")
		}
		var events []contract.LegacyEvent
		if e := json.Unmarshal(legacy, &events); e != nil {
			return e
		}
		result.Legacy[id] = events
		for _, family := range families {
			b := tx.Bucket([]byte(family)).Bucket(k)
			if b == nil {
				continue
			}
			if e := b.ForEach(func(key, value []byte) error {
				if value == nil {
					return errors.New("unexpected nested record bucket")
				}
				var rec contract.Record
				if e := json.Unmarshal(value, &rec); e != nil {
					return e
				}
				if e := rec.Validate(); e != nil {
					return e
				}
				if rec.Family != family || rec.ID != string(key) {
					return errors.New("record key/family mismatch")
				}
				result.Records[id] = append(result.Records[id], rec)
				return nil
			}); e != nil {
				return e
			}
		}
		return nil
	})
	return result, e
}

// Stage publishes the complete frozen legacy inventory in one transaction.
func (s *Store) Stage(root contract.Root, events []contract.LegacyEvent) error {
	if e := root.Validate(); e != nil {
		return e
	}
	if root.Phase != "staged" {
		return errors.New("new root must be staged")
	}
	if events == nil {
		events = []contract.LegacyEvent{}
	}
	ids := map[string]bool{}
	for _, event := range events {
		if event.ID == "" || ids[event.ID] || len(event.Raw) == 0 || event.Grade != "self-attested" {
			return errors.New("invalid imported event identity/grade")
		}
		ids[event.ID] = true
	}
	raw, e := json.Marshal(root)
	if e != nil {
		return e
	}
	inventory, e := json.Marshal(events)
	if e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := guard(tx); e != nil {
			return e
		}
		roots := tx.Bucket([]byte("roots"))
		key := []byte(root.ID)
		if old := roots.Get(key); old != nil {
			if bytes.Equal(old, raw) && bytes.Equal(tx.Bucket([]byte("legacy")).Get(key), inventory) {
				return nil
			}
			return errors.New("root/import identity conflict")
		}
		if e := roots.Put(key, raw); e != nil {
			return e
		}
		return tx.Bucket([]byte("legacy")).Put(key, inventory)
	})
}

func getRoot(tx *bolt.Tx, id string) (contract.Root, error) {
	var r contract.Root
	data := tx.Bucket([]byte("roots")).Get([]byte(id))
	if data == nil {
		return r, errors.New("unknown execution root")
	}
	e := json.Unmarshal(data, &r)
	return r, e
}
func putRoot(tx *bolt.Tx, r contract.Root) error {
	if e := r.Validate(); e != nil {
		return e
	}
	raw, e := json.Marshal(r)
	if e != nil {
		return e
	}
	return tx.Bucket([]byte("roots")).Put([]byte(r.ID), raw)
}

func (s *Store) Activate(id, generation, inventory string) error {
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := guard(tx); e != nil {
			return e
		}
		r, e := getRoot(tx, id)
		if e != nil {
			return e
		}
		if r.Generation != generation || r.Inventory != inventory {
			return errors.New("promotion identity mismatch")
		}
		r.Phase = "active"
		return putRoot(tx, r)
	})
}

type Tx struct {
	tx   *bolt.Tx
	root contract.Root
}

func (s *Store) Update(id, generation string, fn func(*Tx) error) error {
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := guard(tx); e != nil {
			return e
		}
		r, e := getRoot(tx, id)
		if e != nil {
			return e
		}
		if r.Phase != "active" || r.Generation != generation {
			return errors.New("execution authority unavailable")
		}
		return fn(&Tx{tx: tx, root: r})
	})
}

func (t *Tx) Root() contract.Root {
	raw, _ := json.Marshal(t.root)
	var r contract.Root
	_ = json.Unmarshal(raw, &r)
	return r
}
func (t *Tx) SetRoot(r contract.Root) error {
	if r.ID != t.root.ID || r.Generation != t.root.Generation || r.Inventory != t.root.Inventory || r.Phase != t.root.Phase {
		return errors.New("mutation cannot replace root authority")
	}
	if e := putRoot(t.tx, r); e != nil {
		return e
	}
	t.root = r
	return nil
}

func (t *Tx) Put(r contract.Record) error {
	if e := r.Validate(); e != nil {
		return e
	}
	b, e := t.tx.Bucket([]byte(r.Family)).CreateBucketIfNotExists([]byte(t.root.ID))
	if e != nil {
		return e
	}
	raw, e := json.Marshal(r)
	if e != nil {
		return e
	}
	if old := b.Get([]byte(r.ID)); old != nil {
		var previous contract.Record
		if e := json.Unmarshal(old, &previous); e != nil {
			return e
		}
		if !reflect.DeepEqual(previous, r) {
			return errors.New("immutable record identity conflict")
		}
		return nil
	}
	return b.Put([]byte(r.ID), raw)
}

// Once lives in the same transaction as every dependent update. A callback
// error rolls it back too, allowing a clean retry after any rejected mutation.
func (t *Tx) Once(id string, payload []byte) (bool, error) {
	if id == "" {
		return false, errors.New("operation identity required")
	}
	b, e := t.tx.Bucket([]byte("operations")).CreateBucketIfNotExists([]byte(t.root.ID))
	if e != nil {
		return false, e
	}
	key := []byte(id)
	digest := []byte(contract.Digest(payload))
	if old := b.Get(key); old != nil {
		if !bytes.Equal(old, digest) {
			return false, errors.New("operation identity conflict")
		}
		return false, nil
	}
	if e = b.Put(key, digest); e != nil {
		return false, e
	}
	return true, nil
}
