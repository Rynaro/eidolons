package store

import (
	"encoding/json"
	"errors"
	"fmt"
	"reflect"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
	bolt "go.etcd.io/bbolt"
)

// Roster namespaces hold need-based specialist adoption profiles and routing fixtures.
var rosterBuckets = []string{
	"roster_profiles", "roster_assignments", "roster_controls",
	"roster_compat", "roster_isolation", "roster_benefits",
	"roster_registries", "roster_events",
}

type rosterReceipt struct {
	Version    int    `json:"schema_version"`
	Controller string `json:"controller"`
	Kind       string `json:"kind"`
	Typed      int    `json:"typed_version"`
}

func initializeRoster(tx *bolt.Tx, id, kind string) error {
	for _, name := range rosterBuckets {
		if _, e := tx.CreateBucketIfNotExists([]byte(name)); e != nil {
			return e
		}
	}
	return putJSON(tx.Bucket([]byte("meta")), "roster_receipt", rosterReceipt{
		Version: 1, Controller: id, Kind: kind, Typed: contract.RosterSchemaVersion,
	})
}

func guardRoster(tx *bolt.Tx) error {
	meta := tx.Bucket([]byte("meta"))
	raw := meta.Get([]byte("roster_receipt"))
	missing := 0
	for _, name := range rosterBuckets {
		if tx.Bucket([]byte(name)) == nil {
			missing++
		}
	}
	if raw == nil && missing == len(rosterBuckets) {
		// Pre-V4-18 schema 2 stores remain openable; roster APIs ensure namespaces.
		return nil
	}
	if raw == nil || missing != 0 {
		return errors.New("incomplete roster namespaces; call roster-enable")
	}
	var receipt rosterReceipt
	if e := contract.StrictJSON(raw, &receipt); e != nil {
		return errors.New("invalid roster receipt")
	}
	id := string(meta.Get([]byte("store_id")))
	if receipt.Version != 1 || receipt.Controller != id || receipt.Typed != contract.RosterSchemaVersion {
		return errors.New("unsupported roster receipt")
	}
	return nil
}

func (s *Store) rosterReady(tx *bolt.Tx) error {
	for _, name := range rosterBuckets {
		if tx.Bucket([]byte(name)) == nil {
			return errors.New("roster namespaces required")
		}
	}
	if tx.Bucket([]byte("meta")).Get([]byte("roster_receipt")) == nil {
		return errors.New("roster namespaces required")
	}
	return nil
}

// EnsureRosterNamespaces adds typed roster-adoption buckets under schema 2.
func (s *Store) EnsureRosterNamespaces() error {
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := guardBase(tx, "2"); e != nil {
			return e
		}
		id := string(tx.Bucket([]byte("meta")).Get([]byte("store_id")))
		if raw := tx.Bucket([]byte("meta")).Get([]byte("roster_receipt")); raw != nil {
			return guardRoster(tx)
		}
		if e := initializeRoster(tx, id, "ensure"); e != nil {
			return e
		}
		return guardRoster(tx)
	})
}

func (s *Store) appendRosterEvent(tx *bolt.Tx, kind, subject, at string, detail any) error {
	b := tx.Bucket([]byte("roster_events"))
	if b == nil {
		return errors.New("roster namespaces required")
	}
	seq, _ := b.NextSequence()
	payload := map[string]any{
		"seq": seq, "kind": kind, "subject": subject, "at": at, "detail": detail,
	}
	raw, e := json.Marshal(payload)
	if e != nil {
		return e
	}
	key := fmt.Sprintf("%020d/%s/%s", seq, kind, subject)
	return b.Put([]byte(key), raw)
}

func (s *Store) PutRosterProfile(p contract.SpecialistProfile) error {
	if e := p.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.rosterReady(tx); e != nil {
			return e
		}
		b := tx.Bucket([]byte("roster_profiles"))
		if prev := b.Get([]byte(p.ID)); prev != nil {
			var existing contract.SpecialistProfile
			if e := contract.StrictJSON(prev, &existing); e != nil {
				return e
			}
			if !reflect.DeepEqual(existing, p) {
				return errors.New("roster profile identity conflict")
			}
			return nil
		}
		if e := putJSON(b, p.ID, p); e != nil {
			return e
		}
		return s.appendRosterEvent(tx, "profile", p.ID, p.RecordedAt, map[string]any{
			"producer": p.ProducerVersion, "consumer": p.ConsumerVersion,
		})
	})
}

func (s *Store) GetRosterProfile(id string) (contract.SpecialistProfile, error) {
	var p contract.SpecialistProfile
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.rosterReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("roster_profiles")).Get([]byte(id))
		if raw == nil {
			return errors.New("unknown roster profile")
		}
		return contract.StrictJSON(raw, &p)
	})
	return p, e
}

func (s *Store) ListRosterProfiles() ([]contract.SpecialistProfile, error) {
	var out []contract.SpecialistProfile
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.rosterReady(tx); e != nil {
			return e
		}
		b := tx.Bucket([]byte("roster_profiles"))
		return b.ForEach(func(k, v []byte) error {
			var p contract.SpecialistProfile
			if e := contract.StrictJSON(v, &p); e != nil {
				return e
			}
			out = append(out, p)
			return nil
		})
	})
	return out, e
}

func (s *Store) PutRosterAssignment(a contract.RosterRouteAssignment) error {
	if e := a.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.rosterReady(tx); e != nil {
			return e
		}
		b := tx.Bucket([]byte("roster_assignments"))
		if prev := b.Get([]byte(a.ID)); prev != nil {
			var existing contract.RosterRouteAssignment
			if e := contract.StrictJSON(prev, &existing); e != nil {
				return e
			}
			if !reflect.DeepEqual(existing, a) {
				return errors.New("roster assignment identity conflict")
			}
			return nil
		}
		if e := putJSON(b, a.ID, a); e != nil {
			return e
		}
		return s.appendRosterEvent(tx, "assignment", a.ID, a.RecordedAt, map[string]any{
			"form": a.ExecutionForm, "separated": a.SeparatedWorker, "boundary": a.BoundaryReason,
		})
	})
}

func (s *Store) GetRosterAssignment(id string) (contract.RosterRouteAssignment, error) {
	var a contract.RosterRouteAssignment
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.rosterReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("roster_assignments")).Get([]byte(id))
		if raw == nil {
			return errors.New("unknown roster assignment")
		}
		return contract.StrictJSON(raw, &a)
	})
	return a, e
}

func (s *Store) PutRosterControl(c contract.MethodologyControlRevision) error {
	if e := c.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.rosterReady(tx); e != nil {
			return e
		}
		b := tx.Bucket([]byte("roster_controls"))
		if e := putJSON(b, c.ID, c); e != nil {
			return e
		}
		return s.appendRosterEvent(tx, "control", c.ID, c.RecordedAt, map[string]any{
			"classification": c.Classification, "profile": c.ProfileID,
		})
	})
}

func (s *Store) PutRosterCompat(c contract.ProfileCompatibilityCheck) error {
	if e := c.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.rosterReady(tx); e != nil {
			return e
		}
		b := tx.Bucket([]byte("roster_compat"))
		if e := putJSON(b, c.ID, c); e != nil {
			return e
		}
		return s.appendRosterEvent(tx, "compat", c.ID, c.RecordedAt, map[string]any{
			"compatible": c.Compatible, "profile": c.ProfileID,
		})
	})
}

func (s *Store) PutRosterIsolation(c contract.IsolationContractCheck) error {
	if e := c.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.rosterReady(tx); e != nil {
			return e
		}
		b := tx.Bucket([]byte("roster_isolation"))
		if e := putJSON(b, c.ID, c); e != nil {
			return e
		}
		return s.appendRosterEvent(tx, "isolation", c.ID, c.RecordedAt, map[string]any{
			"accepted": c.Accepted, "form": c.ExecutionForm,
		})
	})
}

func (s *Store) PutRosterBenefit(b contract.BenefitEvidenceLabel) error {
	if e := b.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.rosterReady(tx); e != nil {
			return e
		}
		bucket := tx.Bucket([]byte("roster_benefits"))
		if e := putJSON(bucket, b.ID, b); e != nil {
			return e
		}
		return s.appendRosterEvent(tx, "benefit", b.ID, b.RecordedAt, map[string]any{
			"label": b.Label, "evidence_class": b.EvidenceClass,
		})
	})
}

func (s *Store) PutRosterRegistry(r contract.RosterAdoptionRegistry) error {
	if e := r.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.rosterReady(tx); e != nil {
			return e
		}
		b := tx.Bucket([]byte("roster_registries"))
		if prev := b.Get([]byte(r.ID)); prev != nil {
			var existing contract.RosterAdoptionRegistry
			if e := contract.StrictJSON(prev, &existing); e != nil {
				return e
			}
			if !reflect.DeepEqual(existing, r) {
				return errors.New("roster registry identity conflict")
			}
			return nil
		}
		if e := putJSON(b, r.ID, r); e != nil {
			return e
		}
		return s.appendRosterEvent(tx, "registry", r.ID, r.RecordedAt, map[string]any{
			"profiles": len(r.ProfileIDs), "covered": r.RequiredCovered,
		})
	})
}

func (s *Store) GetRosterRegistry(id string) (contract.RosterAdoptionRegistry, error) {
	var r contract.RosterAdoptionRegistry
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.rosterReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("roster_registries")).Get([]byte(id))
		if raw == nil {
			return errors.New("unknown roster registry")
		}
		return contract.StrictJSON(raw, &r)
	})
	return r, e
}
