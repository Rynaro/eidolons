package store

import (
	"encoding/json"
	"errors"
	"fmt"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
	bolt "go.etcd.io/bbolt"
)

var deliveryBuckets = []string{
	"delivery_loops", "delivery_checkpoints", "delivery_obligations",
	"delivery_interventions", "delivery_events",
}

type deliveryReceipt struct {
	Version    int    `json:"schema_version"`
	Controller string `json:"controller"`
	Kind       string `json:"kind"`
	Typed      int    `json:"typed_version"`
}

func initializeDelivery(tx *bolt.Tx, id, kind string) error {
	for _, name := range deliveryBuckets {
		if _, e := tx.CreateBucketIfNotExists([]byte(name)); e != nil {
			return e
		}
	}
	return putJSON(tx.Bucket([]byte("meta")), "delivery_receipt", deliveryReceipt{
		Version: 1, Controller: id, Kind: kind, Typed: contract.DeliverySchemaVersion,
	})
}

func guardDelivery(tx *bolt.Tx) error {
	meta := tx.Bucket([]byte("meta"))
	raw := meta.Get([]byte("delivery_receipt"))
	missing := 0
	for _, name := range deliveryBuckets {
		if tx.Bucket([]byte(name)) == nil {
			missing++
		}
	}
	if raw == nil && missing == len(deliveryBuckets) {
		// Pre-V4-15 schema 2 stores remain openable; delivery APIs ensure namespaces.
		return nil
	}
	if raw == nil || missing != 0 {
		return errors.New("incomplete delivery namespaces; call delivery-enable")
	}
	var receipt deliveryReceipt
	if e := contract.StrictJSON(raw, &receipt); e != nil {
		return errors.New("invalid delivery receipt")
	}
	id := string(meta.Get([]byte("store_id")))
	if receipt.Version != 1 || receipt.Controller != id || receipt.Typed != contract.DeliverySchemaVersion {
		return errors.New("unsupported delivery receipt")
	}
	return nil
}

func (s *Store) deliveryReady(tx *bolt.Tx) error {
	for _, name := range deliveryBuckets {
		if tx.Bucket([]byte(name)) == nil {
			return errors.New("delivery namespaces required")
		}
	}
	if tx.Bucket([]byte("meta")).Get([]byte("delivery_receipt")) == nil {
		return errors.New("delivery namespaces required")
	}
	return nil
}

// EnsureDeliveryNamespaces adds typed delivery buckets under schema 2 without a schema bump.
func (s *Store) EnsureDeliveryNamespaces() error {
	return s.db.Update(func(tx *bolt.Tx) error {
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
		id := string(tx.Bucket([]byte("meta")).Get([]byte("store_id")))
		if raw := tx.Bucket([]byte("meta")).Get([]byte("delivery_receipt")); raw != nil {
			return guardDelivery(tx)
		}
		if e := initializeDelivery(tx, id, "ensure"); e != nil {
			return e
		}
		return guardDelivery(tx)
	})
}

func (s *Store) appendDeliveryEvent(tx *bolt.Tx, kind, subject, at string, detail any) error {
	payload := map[string]any{
		"kind": kind, "subject": subject, "recorded_at": at, "detail": detail,
	}
	raw, e := json.Marshal(payload)
	if e != nil {
		return e
	}
	key := fmt.Sprintf("%s/%s/%s", at, kind, subject)
	b := tx.Bucket([]byte("delivery_events"))
	if b.Get([]byte(key)) != nil {
		key = key + "/" + contract.Digest(raw)[:12]
	}
	return b.Put([]byte(key), raw)
}

// PersistDeliveryLoop stores or updates loop state.
func (s *Store) PersistDeliveryLoop(loop contract.DeliveryLoop) (contract.DeliveryLoop, error) {
	if e := loop.Validate(); e != nil {
		return loop, e
	}
	e := s.db.Update(func(tx *bolt.Tx) error {
		if e := s.deliveryReady(tx); e != nil {
			return e
		}
		b := tx.Bucket([]byte("delivery_loops"))
		raw, e := json.Marshal(loop)
		if e != nil {
			return e
		}
		if e := b.Put([]byte(loop.ID), raw); e != nil {
			return e
		}
		return s.appendDeliveryEvent(tx, "loop_persist", loop.ID, loop.UpdatedAt, map[string]any{
			"phase": loop.Phase, "status": loop.Status, "root": loop.RootID,
		})
	})
	return loop, e
}

// GetDeliveryLoop loads a loop by ID.
func (s *Store) GetDeliveryLoop(id string) (contract.DeliveryLoop, error) {
	var loop contract.DeliveryLoop
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.deliveryReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("delivery_loops")).Get([]byte(id))
		if raw == nil {
			return errors.New("delivery loop not found")
		}
		return contract.StrictJSON(raw, &loop)
	})
	return loop, e
}

// ListDeliveryLoops returns all loops (for status).
func (s *Store) ListDeliveryLoops() ([]contract.DeliveryLoop, error) {
	var out []contract.DeliveryLoop
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.deliveryReady(tx); e != nil {
			return e
		}
		return tx.Bucket([]byte("delivery_loops")).ForEach(func(_, v []byte) error {
			var loop contract.DeliveryLoop
			if e := contract.StrictJSON(v, &loop); e != nil {
				return e
			}
			out = append(out, loop)
			return nil
		})
	})
	return out, e
}

// PersistObligation stores a validated obligation.
func (s *Store) PersistObligation(loopID string, o contract.ObligationRecord) error {
	if e := o.Validate(); e != nil {
		return e
	}
	if o.Digest == "" {
		raw, _ := json.Marshal(o)
		o.Digest = contract.Digest(raw)
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.deliveryReady(tx); e != nil {
			return e
		}
		key := loopID + "/" + o.ID
		raw, e := json.Marshal(o)
		if e != nil {
			return e
		}
		return tx.Bucket([]byte("delivery_obligations")).Put([]byte(key), raw)
	})
}

// ListObligations returns obligations for a loop.
func (s *Store) ListObligations(loopID string) ([]contract.ObligationRecord, error) {
	var out []contract.ObligationRecord
	prefix := []byte(loopID + "/")
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.deliveryReady(tx); e != nil {
			return e
		}
		c := tx.Bucket([]byte("delivery_obligations")).Cursor()
		for k, v := c.Seek(prefix); k != nil && len(k) >= len(prefix) && string(k[:len(prefix)]) == string(prefix); k, v = c.Next() {
			var o contract.ObligationRecord
			if e := contract.StrictJSON(v, &o); e != nil {
				return e
			}
			out = append(out, o)
		}
		return nil
	})
	return out, e
}

// PersistIntervention stores an intervention record.
func (s *Store) PersistIntervention(i contract.InterventionRecord) error {
	if e := i.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.deliveryReady(tx); e != nil {
			return e
		}
		raw, e := json.Marshal(i)
		if e != nil {
			return e
		}
		if e := tx.Bucket([]byte("delivery_interventions")).Put([]byte(i.ID), raw); e != nil {
			return e
		}
		return s.appendDeliveryEvent(tx, "intervention", i.ID, i.RecordedAt, map[string]any{
			"kind": i.Kind, "routine": i.Routine, "loop": i.LoopID,
		})
	})
}

// ListInterventions returns interventions for a loop.
func (s *Store) ListInterventions(loopID string) ([]contract.InterventionRecord, error) {
	var out []contract.InterventionRecord
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.deliveryReady(tx); e != nil {
			return e
		}
		return tx.Bucket([]byte("delivery_interventions")).ForEach(func(_, v []byte) error {
			var i contract.InterventionRecord
			if e := contract.StrictJSON(v, &i); e != nil {
				return e
			}
			if i.LoopID == loopID {
				out = append(out, i)
			}
			return nil
		})
	})
	return out, e
}

// PersistCheckpoint stores a portable checkpoint.
func (s *Store) PersistCheckpoint(c contract.DeliveryCheckpoint) (contract.DeliveryCheckpoint, error) {
	if c.PayloadDigest == "" {
		c.PayloadDigest = contract.CheckpointPayloadDigest(c)
	}
	if e := c.Validate(); e != nil {
		return c, e
	}
	e := s.db.Update(func(tx *bolt.Tx) error {
		if e := s.deliveryReady(tx); e != nil {
			return e
		}
		raw, e := json.Marshal(c)
		if e != nil {
			return e
		}
		if e := tx.Bucket([]byte("delivery_checkpoints")).Put([]byte(c.ID), raw); e != nil {
			return e
		}
		return s.appendDeliveryEvent(tx, "checkpoint", c.ID, c.RecordedAt, map[string]any{
			"loop": c.LoopID, "phase": c.Phase,
		})
	})
	return c, e
}

// GetCheckpoint loads a checkpoint by ID.
func (s *Store) GetCheckpoint(id string) (contract.DeliveryCheckpoint, error) {
	var c contract.DeliveryCheckpoint
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.deliveryReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("delivery_checkpoints")).Get([]byte(id))
		if raw == nil {
			return errors.New("checkpoint not found")
		}
		return contract.StrictJSON(raw, &c)
	})
	return c, e
}

// TamperCheckpointPayload overwrites stored payload digest for fixture R06 tests.
func (s *Store) TamperCheckpointPayload(id, bogusDigest string) error {
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.deliveryReady(tx); e != nil {
			return e
		}
		b := tx.Bucket([]byte("delivery_checkpoints"))
		raw := b.Get([]byte(id))
		if raw == nil {
			return errors.New("checkpoint not found")
		}
		var c contract.DeliveryCheckpoint
		if e := contract.StrictJSON(raw, &c); e != nil {
			return e
		}
		c.PayloadDigest = bogusDigest
		out, e := json.Marshal(c)
		if e != nil {
			return e
		}
		return b.Put([]byte(id), out)
	})
}

// ChangeCheckpointCriteria mutates criteria digest for R06 changed-criteria fixture.
// Recomputes payload digest so the limitation is criteria drift, not payload tamper.
func (s *Store) ChangeCheckpointCriteria(id, newCriteria string) error {
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.deliveryReady(tx); e != nil {
			return e
		}
		b := tx.Bucket([]byte("delivery_checkpoints"))
		raw := b.Get([]byte(id))
		if raw == nil {
			return errors.New("checkpoint not found")
		}
		var c contract.DeliveryCheckpoint
		if e := contract.StrictJSON(raw, &c); e != nil {
			return e
		}
		c.CriteriaDigest = newCriteria
		c.Limitation = nil
		c.PayloadDigest = ""
		c.PayloadDigest = contract.CheckpointPayloadDigest(c)
		out, e := json.Marshal(c)
		if e != nil {
			return e
		}
		return b.Put([]byte(id), out)
	})
}
