package store

import (
	"encoding/hex"
	"errors"
	"reflect"
	"time"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
	bolt "go.etcd.io/bbolt"
)

// InspectPredecessor is an explicit migration-only read. Ordinary Inspect/Open
// never accept the predecessor and never create missing typed namespaces.
func InspectPredecessor(path string, timeout time.Duration) (Snapshot, error) {
	var snap Snapshot
	if e := regular(path); e != nil {
		return snap, e
	}
	opts, e := options(timeout, true)
	if e != nil {
		return snap, e
	}
	db, e := bolt.Open(path, 0600, opts)
	if e != nil {
		return snap, e
	}
	defer db.Close()
	e = db.View(func(tx *bolt.Tx) error { var e error; snap, e = predecessor(tx); return e })
	return snap, e
}
func predecessor(tx *bolt.Tx) (Snapshot, error) {
	snap, e := snapshotAt(tx, "1")
	if e != nil {
		return snap, e
	}
	for _, name := range policyBuckets {
		if tx.Bucket([]byte(name)) != nil {
			return snap, errors.New("predecessor has unexpected typed namespace")
		}
	}
	if tx.Bucket([]byte("meta")).Get([]byte("migration_receipt")) != nil {
		return snap, errors.New("predecessor has conflicting migration receipt")
	}
	for id, events := range snap.Legacy {
		seen := map[string]bool{}
		for _, event := range events {
			if event.ID == "" || seen[event.ID] || len(event.Raw) == 0 || event.Grade != "self-attested" {
				return snap, errors.New("invalid predecessor inventory")
			}
			seen[event.ID] = true
		}
		if !snap.Roots[id].Legacy && len(events) != 0 {
			return snap, errors.New("nonimported predecessor contains legacy events")
		}
	}
	e = tx.Bucket([]byte("operations")).ForEach(func(k, v []byte) error {
		if v != nil || tx.Bucket([]byte("roots")).Get(k) == nil {
			return errors.New("invalid predecessor operation root")
		}
		return tx.Bucket([]byte("operations")).Bucket(k).ForEach(func(key, value []byte) error {
			if len(key) == 0 || value == nil || len(value) != 64 {
				return errors.New("invalid predecessor operation digest")
			}
			_, e := hex.DecodeString(string(value))
			return e
		})
	})
	if e != nil {
		return snap, e
	}
	for _, name := range append([]string{"legacy"}, families...) {
		if e = tx.Bucket([]byte(name)).ForEach(func(k, v []byte) error {
			if tx.Bucket([]byte("roots")).Get(k) == nil {
				return errors.New("orphan predecessor inventory/history")
			}
			if name != "legacy" && v != nil {
				return errors.New("invalid predecessor family structure")
			}
			return nil
		}); e != nil {
			return snap, e
		}
	}
	return snap, nil
}

// validate runs while the shared DB write lock is held; controller callers
// retain every predecessor root's append lock and recheck filesystem proofs.
// It cannot mutate the transaction or create grants.
func Migrate(path string, timeout time.Duration, validate func(Snapshot) error) error {
	return migrate(path, timeout, validate, nil)
}
func migrate(path string, timeout time.Duration, validate func(Snapshot) error, cut func(string) error) error {
	if _, e := InspectPredecessor(path, timeout); e != nil {
		return e
	}
	if e := regular(path); e != nil {
		return e
	}
	opts, e := options(timeout, false)
	if e != nil {
		return e
	}
	db, e := bolt.Open(path, 0600, opts)
	if e != nil {
		return e
	}
	defer db.Close()
	return db.Update(func(tx *bolt.Tx) error {
		snap, e := predecessor(tx)
		if e != nil {
			return e
		}
		if validate != nil {
			if e = validate(snap); e != nil {
				return e
			}
		}
		if e = initializePolicy(tx, snap.StoreID, "migration"); e != nil {
			return e
		}
		if cut != nil {
			if e = cut("namespaces-written"); e != nil {
				return e
			}
		}
		if e = tx.Bucket([]byte("meta")).Put([]byte("schema"), []byte("2")); e != nil {
			return e
		}
		if cut != nil {
			if e = cut("version-written"); e != nil {
				return e
			}
		}
		if e = guard(tx); e != nil {
			return e
		}
		after, e := snapshot(tx)
		if e != nil {
			return e
		}
		if !reflect.DeepEqual(snap, after) {
			return errors.New("migration changed predecessor history")
		}
		return nil
	})
}

// Decode typed input independently from generic historical policy JSON.
func DecodePolicyPatch(raw []byte) (contract.PolicyPatch, error) {
	var p contract.PolicyPatch
	e := contract.StrictJSON(raw, &p)
	if e == nil {
		e = p.Validate()
	}
	return p, e
}
