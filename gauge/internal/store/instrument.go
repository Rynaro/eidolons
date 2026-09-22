package store

import (
	"encoding/json"
	"errors"
	"fmt"
	"reflect"
	"sort"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
	bolt "go.etcd.io/bbolt"
)

var instrumentBuckets = []string{
	"capability_catalogue", "protocol_freezes", "attempt_records",
	"eligibility_records", "shadow_observations", "instrument_ordering",
}

type instrumentReceipt struct {
	Version    int    `json:"schema_version"`
	Controller string `json:"controller"`
	Kind       string `json:"kind"`
	Typed      int    `json:"typed_version"`
}

type orderingCounter struct {
	Next int64 `json:"next"`
}

func initializeInstrument(tx *bolt.Tx, id, kind string) error {
	for _, name := range instrumentBuckets {
		if _, e := tx.CreateBucketIfNotExists([]byte(name)); e != nil {
			return e
		}
	}
	if e := putJSON(tx.Bucket([]byte("meta")), "instrument_receipt", instrumentReceipt{
		Version: 1, Controller: id, Kind: kind, Typed: contract.InstrumentSchemaVersion,
	}); e != nil {
		return e
	}
	return putJSON(tx.Bucket([]byte("meta")), "instrument_ordering_counter", orderingCounter{Next: 1})
}

func guardInstrument(tx *bolt.Tx) error {
	meta := tx.Bucket([]byte("meta"))
	raw := meta.Get([]byte("instrument_receipt"))
	missing := 0
	for _, name := range instrumentBuckets {
		if tx.Bucket([]byte(name)) == nil {
			missing++
		}
	}
	if raw == nil && missing == len(instrumentBuckets) {
		// Pre-V4-09 schema 2 stores remain openable; instrument APIs ensure namespaces.
		return nil
	}
	if raw == nil || missing != 0 {
		return errors.New("incomplete instrument namespaces; call instrument-enable")
	}
	var receipt instrumentReceipt
	if e := contract.StrictJSON(raw, &receipt); e != nil {
		return errors.New("invalid instrument receipt")
	}
	id := string(meta.Get([]byte("store_id")))
	if receipt.Version != 1 || receipt.Controller != id || receipt.Typed != contract.InstrumentSchemaVersion {
		return errors.New("unsupported instrument receipt")
	}
	return nil
}

func (s *Store) instrumentReady(tx *bolt.Tx) error {
	for _, name := range instrumentBuckets {
		if tx.Bucket([]byte(name)) == nil {
			return errors.New("instrument namespaces required")
		}
	}
	if tx.Bucket([]byte("meta")).Get([]byte("instrument_receipt")) == nil {
		return errors.New("instrument namespaces required")
	}
	return nil
}

// EnsureInstrumentNamespaces adds typed instrument buckets under schema 2 without a schema bump.
func (s *Store) EnsureInstrumentNamespaces() error {
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
		id := string(tx.Bucket([]byte("meta")).Get([]byte("store_id")))
		if raw := tx.Bucket([]byte("meta")).Get([]byte("instrument_receipt")); raw != nil {
			return guardInstrument(tx)
		}
		if e := initializeInstrument(tx, id, "ensure"); e != nil {
			return e
		}
		return guardInstrument(tx)
	})
}

func (s *Store) appendOrdering(tx *bolt.Tx, kind, ref, digest, at string) (contract.OrderingEvent, error) {
	meta := tx.Bucket([]byte("meta"))
	var counter orderingCounter
	raw := meta.Get([]byte("instrument_ordering_counter"))
	if raw == nil {
		return contract.OrderingEvent{}, errors.New("missing instrument ordering counter")
	}
	if e := contract.StrictJSON(raw, &counter); e != nil {
		return contract.OrderingEvent{}, e
	}
	ev := contract.OrderingEvent{Seq: counter.Next, Kind: kind, Ref: ref, Digest: digest, RecordedAt: at}
	counter.Next++
	if e := putJSON(meta, "instrument_ordering_counter", counter); e != nil {
		return contract.OrderingEvent{}, e
	}
	key := fmt.Sprintf("%020d", ev.Seq)
	if e := putJSON(tx.Bucket([]byte("instrument_ordering")), key, ev); e != nil {
		return contract.OrderingEvent{}, e
	}
	return ev, nil
}

func (s *Store) PutCapability(t contract.CapabilityTuple, recordedAt string) (contract.OrderingEvent, error) {
	digest, e := t.IdentityDigest()
	if e != nil {
		return contract.OrderingEvent{}, e
	}
	t.Digest = digest
	if e = t.Validate(); e != nil {
		return contract.OrderingEvent{}, e
	}
	var ev contract.OrderingEvent
	err := s.db.Update(func(tx *bolt.Tx) error {
		if e := s.instrumentReady(tx); e != nil {
			return e
		}
		b := tx.Bucket([]byte("capability_catalogue"))
		if prev := b.Get([]byte(t.ID)); prev != nil {
			var existing contract.CapabilityTuple
			if e := contract.StrictJSON(prev, &existing); e != nil {
				return e
			}
			if !reflect.DeepEqual(existing, t) {
				return errors.New("capability identity conflict")
			}
			return nil
		}
		if e := putJSON(b, t.ID, t); e != nil {
			return e
		}
		var err error
		ev, err = s.appendOrdering(tx, contract.OrderCatalogue, t.ID, digest, recordedAt)
		return err
	})
	return ev, err
}

func (s *Store) GetCapability(id string) (contract.CapabilityTuple, error) {
	var t contract.CapabilityTuple
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.instrumentReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("capability_catalogue")).Get([]byte(id))
		if raw == nil {
			return errors.New("unknown capability tuple")
		}
		return contract.StrictJSON(raw, &t)
	})
	return t, e
}

func (s *Store) InvalidateCapability(id, recordedAt string) error {
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.instrumentReady(tx); e != nil {
			return e
		}
		b := tx.Bucket([]byte("capability_catalogue"))
		raw := b.Get([]byte(id))
		if raw == nil {
			return errors.New("unknown capability tuple")
		}
		var t contract.CapabilityTuple
		if e := contract.StrictJSON(raw, &t); e != nil {
			return e
		}
		t.Qualification = contract.QualificationInvalidated
		t.Digest = ""
		if e := putJSON(b, id, t); e != nil {
			return e
		}
		_, e := s.appendOrdering(tx, "invalidate", id, "", recordedAt)
		return e
	})
}

func (s *Store) FreezeProtocol(p contract.FrozenProtocol, recordedAt string) (contract.OrderingEvent, error) {
	digest, e := p.CanonicalHash()
	if e != nil {
		return contract.OrderingEvent{}, e
	}
	p.CanonicalDigest = digest
	var ev contract.OrderingEvent
	err := s.db.Update(func(tx *bolt.Tx) error {
		if e := s.instrumentReady(tx); e != nil {
			return e
		}
		b := tx.Bucket([]byte("protocol_freezes"))
		if prev := b.Get([]byte(p.ID)); prev != nil {
			var existing contract.FrozenProtocol
			if e := contract.StrictJSON(prev, &existing); e != nil {
				return e
			}
			if !reflect.DeepEqual(existing, p) {
				return errors.New("protocol identity conflict")
			}
			return nil
		}
		if e := putJSON(b, p.ID, p); e != nil {
			return e
		}
		var err error
		ev, err = s.appendOrdering(tx, contract.OrderFreeze, p.ID, digest, recordedAt)
		return err
	})
	return ev, err
}

func (s *Store) GetProtocol(id string) (contract.FrozenProtocol, error) {
	var p contract.FrozenProtocol
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.instrumentReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("protocol_freezes")).Get([]byte(id))
		if raw == nil {
			return errors.New("unknown protocol")
		}
		return contract.StrictJSON(raw, &p)
	})
	return p, e
}

func (s *Store) PutAttempt(r contract.AttemptRecord, recordedAt string) (contract.OrderingEvent, error) {
	if e := r.Validate(); e != nil {
		return contract.OrderingEvent{}, e
	}
	var ev contract.OrderingEvent
	err := s.db.Update(func(tx *bolt.Tx) error {
		if e := s.instrumentReady(tx); e != nil {
			return e
		}
		protoRaw := tx.Bucket([]byte("protocol_freezes")).Get([]byte(r.ProtocolID))
		if protoRaw == nil {
			return errors.New("attempt requires previously frozen protocol")
		}
		var proto contract.FrozenProtocol
		if e := contract.StrictJSON(protoRaw, &proto); e != nil {
			return e
		}
		if proto.CanonicalDigest != r.ProtocolDigest {
			return errors.New("attempt protocol digest mismatch")
		}
		// Ordering: freeze must precede outcome/dispatch for this protocol.
		freezeSeq := int64(-1)
		_ = tx.Bucket([]byte("instrument_ordering")).ForEach(func(_, v []byte) error {
			var o contract.OrderingEvent
			if e := contract.StrictJSON(v, &o); e != nil {
				return e
			}
			if o.Kind == contract.OrderFreeze && o.Ref == r.ProtocolID {
				freezeSeq = o.Seq
			}
			return nil
		})
		if freezeSeq < 0 {
			return errors.New("protocol freeze ordering missing")
		}
		b := tx.Bucket([]byte("attempt_records"))
		key := r.ProtocolID + "/" + r.ArmID + "/" + r.ID
		if prev := b.Get([]byte(key)); prev != nil {
			var existing contract.AttemptRecord
			if e := contract.StrictJSON(prev, &existing); e != nil {
				return e
			}
			rawNew, _ := json.Marshal(r)
			rawOld, _ := json.Marshal(existing)
			if string(rawNew) != string(rawOld) {
				return errors.New("attempt identity conflict")
			}
			return nil
		}
		if e := putJSON(b, key, r); e != nil {
			return e
		}
		var err error
		ev, err = s.appendOrdering(tx, contract.OrderOutcome, key, r.ProtocolDigest, recordedAt)
		if err != nil {
			return err
		}
		if ev.Seq <= freezeSeq {
			return errors.New("outcome ordering must follow freeze")
		}
		return nil
	})
	return ev, err
}

func (s *Store) ListAttempts(protocolID, armID string) ([]contract.AttemptRecord, error) {
	var out []contract.AttemptRecord
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.instrumentReady(tx); e != nil {
			return e
		}
		prefix := protocolID + "/"
		if armID != "" {
			prefix = protocolID + "/" + armID + "/"
		}
		return tx.Bucket([]byte("attempt_records")).ForEach(func(k, v []byte) error {
			if !hasPrefix(string(k), prefix) {
				return nil
			}
			var r contract.AttemptRecord
			if e := contract.StrictJSON(v, &r); e != nil {
				return e
			}
			out = append(out, r)
			return nil
		})
	})
	sort.Slice(out, func(i, j int) bool { return out[i].ID < out[j].ID })
	return out, e
}

func (s *Store) PutEligibility(e contract.ArmEligibility) error {
	if err := e.Validate(); err != nil {
		return err
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if err := s.instrumentReady(tx); err != nil {
			return err
		}
		b := tx.Bucket([]byte("eligibility_records"))
		key := e.ProtocolID + "/" + e.ArmID + "/" + e.ID
		if prev := b.Get([]byte(key)); prev != nil {
			var existing contract.ArmEligibility
			if err := contract.StrictJSON(prev, &existing); err != nil {
				return err
			}
			if !reflect.DeepEqual(existing, e) {
				return errors.New("eligibility identity conflict")
			}
			return nil
		}
		if err := putJSON(b, key, e); err != nil {
			return err
		}
		_, err := s.appendOrdering(tx, contract.OrderEligibility, key, "", e.RecordedAt)
		return err
	})
}

func (s *Store) ListEligibility(protocolID string) ([]contract.ArmEligibility, error) {
	var out []contract.ArmEligibility
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.instrumentReady(tx); e != nil {
			return e
		}
		prefix := protocolID + "/"
		return tx.Bucket([]byte("eligibility_records")).ForEach(func(k, v []byte) error {
			if !hasPrefix(string(k), prefix) {
				return nil
			}
			var el contract.ArmEligibility
			if e := contract.StrictJSON(v, &el); e != nil {
				return e
			}
			out = append(out, el)
			return nil
		})
	})
	sort.Slice(out, func(i, j int) bool { return out[i].ID < out[j].ID })
	return out, e
}

func (s *Store) PutShadow(obs contract.ShadowObservation) error {
	if e := obs.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.instrumentReady(tx); e != nil {
			return e
		}
		b := tx.Bucket([]byte("shadow_observations"))
		if prev := b.Get([]byte(obs.ID)); prev != nil {
			var existing contract.ShadowObservation
			if e := contract.StrictJSON(prev, &existing); e != nil {
				return e
			}
			if !reflect.DeepEqual(existing, obs) {
				return errors.New("shadow identity conflict")
			}
			return nil
		}
		return putJSON(b, obs.ID, obs)
	})
}

func (s *Store) ListOrdering() ([]contract.OrderingEvent, error) {
	var out []contract.OrderingEvent
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.instrumentReady(tx); e != nil {
			return e
		}
		return tx.Bucket([]byte("instrument_ordering")).ForEach(func(_, v []byte) error {
			var ev contract.OrderingEvent
			if e := contract.StrictJSON(v, &ev); e != nil {
				return e
			}
			out = append(out, ev)
			return nil
		})
	})
	sort.Slice(out, func(i, j int) bool { return out[i].Seq < out[j].Seq })
	return out, e
}

func (s *Store) RecordDispatch(protocolID, digest, recordedAt string) (contract.OrderingEvent, error) {
	var ev contract.OrderingEvent
	err := s.db.Update(func(tx *bolt.Tx) error {
		if e := s.instrumentReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("protocol_freezes")).Get([]byte(protocolID))
		if raw == nil {
			return errors.New("dispatch requires previously frozen protocol")
		}
		var proto contract.FrozenProtocol
		if e := contract.StrictJSON(raw, &proto); e != nil {
			return e
		}
		if proto.CanonicalDigest != digest {
			return errors.New("dispatch protocol digest mismatch")
		}
		var err error
		ev, err = s.appendOrdering(tx, contract.OrderDispatch, protocolID, digest, recordedAt)
		return err
	})
	return ev, err
}
