package store

import (
	"encoding/json"
	"errors"
	"fmt"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
	bolt "go.etcd.io/bbolt"
)

// Context namespaces hold core-context manager state under schema 2.
// They never host indexed/recursive adapters (optional adapter out of scope).
var contextBuckets = []string{
	"context_sessions", "context_evidence", "context_memory",
	"context_navigation", "context_overhead", "context_features", "context_events",
}

type contextReceipt struct {
	Version    int    `json:"schema_version"`
	Controller string `json:"controller"`
	Kind       string `json:"kind"`
	Typed      int    `json:"typed_version"`
}

func initializeContext(tx *bolt.Tx, id, kind string) error {
	for _, name := range contextBuckets {
		if _, e := tx.CreateBucketIfNotExists([]byte(name)); e != nil {
			return e
		}
	}
	return putJSON(tx.Bucket([]byte("meta")), "context_receipt", contextReceipt{
		Version: 1, Controller: id, Kind: kind, Typed: contract.ContextSchemaVersion,
	})
}

func guardContext(tx *bolt.Tx) error {
	meta := tx.Bucket([]byte("meta"))
	raw := meta.Get([]byte("context_receipt"))
	missing := 0
	for _, name := range contextBuckets {
		if tx.Bucket([]byte(name)) == nil {
			missing++
		}
	}
	if raw == nil && missing == len(contextBuckets) {
		// Pre-V4-19 schema 2 stores remain openable; context APIs ensure namespaces.
		return nil
	}
	if raw == nil || missing != 0 {
		return errors.New("incomplete context namespaces; call context-enable")
	}
	var receipt contextReceipt
	if e := contract.StrictJSON(raw, &receipt); e != nil {
		return errors.New("invalid context receipt")
	}
	id := string(meta.Get([]byte("store_id")))
	if receipt.Version != 1 || receipt.Controller != id || receipt.Typed != contract.ContextSchemaVersion {
		return errors.New("unsupported context receipt")
	}
	return nil
}

func (s *Store) contextReady(tx *bolt.Tx) error {
	for _, name := range contextBuckets {
		if tx.Bucket([]byte(name)) == nil {
			return errors.New("context namespaces required")
		}
	}
	if tx.Bucket([]byte("meta")).Get([]byte("context_receipt")) == nil {
		return errors.New("context namespaces required")
	}
	return nil
}

// EnsureContextNamespaces adds typed context-manager buckets under schema 2 without a schema bump.
func (s *Store) EnsureContextNamespaces() error {
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := guardBase(tx, "2"); e != nil {
			return e
		}
		id := string(tx.Bucket([]byte("meta")).Get([]byte("store_id")))
		if raw := tx.Bucket([]byte("meta")).Get([]byte("context_receipt")); raw != nil {
			return guardContext(tx)
		}
		if e := initializeContext(tx, id, "ensure"); e != nil {
			return e
		}
		return guardContext(tx)
	})
}

func (s *Store) appendContextEvent(tx *bolt.Tx, kind, subject, at string, detail any) error {
	b := tx.Bucket([]byte("context_events"))
	if b == nil {
		return errors.New("context namespaces required")
	}
	seq, _ := b.NextSequence()
	payload := map[string]any{
		"seq": seq, "kind": kind, "subject": subject, "at": at, "detail": detail,
	}
	raw, e := json.Marshal(payload)
	if e != nil {
		return e
	}
	return b.Put([]byte(fmt.Sprintf("%020d", seq)), raw)
}

// PersistContextSession stores a core-context session envelope.
func (s *Store) PersistContextSession(sess contract.ContextSession) error {
	if e := sess.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.contextReady(tx); e != nil {
			return e
		}
		if e := putJSON(tx.Bucket([]byte("context_sessions")), sess.ID, sess); e != nil {
			return e
		}
		return s.appendContextEvent(tx, "session", sess.ID, sess.CreatedAt, map[string]any{
			"root_id": sess.RootID, "slice": sess.Slice, "optional_adapter": sess.OptionalAdapter,
		})
	})
}

// PersistEvidenceArtifact stores reusable evidence metadata (R01).
func (s *Store) PersistEvidenceArtifact(ev contract.EvidenceArtifact) error {
	if e := ev.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.contextReady(tx); e != nil {
			return e
		}
		if e := putJSON(tx.Bucket([]byte("context_evidence")), ev.ID, ev); e != nil {
			return e
		}
		return s.appendContextEvent(tx, "evidence", ev.ID, "", map[string]any{
			"source_ref": ev.SourceRef, "present": ev.Present,
		})
	})
}

// GetEvidenceArtifact loads stored evidence.
func (s *Store) GetEvidenceArtifact(id string) (contract.EvidenceArtifact, error) {
	var out contract.EvidenceArtifact
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.contextReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("context_evidence")).Get([]byte(id))
		if raw == nil {
			return errors.New("evidence not found")
		}
		return contract.StrictJSON(raw, &out)
	})
	return out, e
}

// PersistMemoryItem stores optional scoped memory (never authoritative).
func (s *Store) PersistMemoryItem(item contract.MemoryItem) error {
	if e := item.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.contextReady(tx); e != nil {
			return e
		}
		if e := putJSON(tx.Bucket([]byte("context_memory")), item.ID, item); e != nil {
			return e
		}
		return s.appendContextEvent(tx, "memory", item.ID, "", map[string]any{
			"project_scope": item.ProjectScope, "revision": item.Revision, "deleted": item.Deleted,
		})
	})
}

// PersistNavigationRecord stores discovery/retrieval/cited-use classification (R10).
func (s *Store) PersistNavigationRecord(rec contract.NavigationRecord) error {
	if e := rec.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.contextReady(tx); e != nil {
			return e
		}
		key := rec.EvidenceID + ":" + rec.Kind
		if e := putJSON(tx.Bucket([]byte("context_navigation")), key, rec); e != nil {
			return e
		}
		return s.appendContextEvent(tx, "navigation", key, "", map[string]any{
			"kind": rec.Kind, "counted_as_use": rec.CountedAsUse,
		})
	})
}

// PersistOverheadReport stores a distinguished overhead measurement (R07).
func (s *Store) PersistOverheadReport(sessionID string, rep contract.OverheadReport) error {
	if e := rep.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.contextReady(tx); e != nil {
			return e
		}
		if e := putJSON(tx.Bucket([]byte("context_overhead")), sessionID, rep); e != nil {
			return e
		}
		return s.appendContextEvent(tx, "overhead", sessionID, "", map[string]any{
			"host_visible": rep.HostVisibleBytes, "source_file": rep.SourceFileBytes,
			"estimated_tokens": rep.EstimatedTokens,
		})
	})
}

// PersistFeatureApplicability records R11/R12 N/A when indexed/recursive features are absent.
func (s *Store) PersistFeatureApplicability(f contract.FeatureApplicability) error {
	if e := f.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.contextReady(tx); e != nil {
			return e
		}
		if e := putJSON(tx.Bucket([]byte("context_features")), f.RequirementID, f); e != nil {
			return e
		}
		return s.appendContextEvent(tx, "feature_na", f.RequirementID, "", map[string]any{
			"feature": f.Feature, "applicability": f.Applicability, "optional_adapter": f.OptionalAdapter,
		})
	})
}

// GetFeatureApplicability loads a recorded N/A feature condition.
func (s *Store) GetFeatureApplicability(reqID string) (contract.FeatureApplicability, error) {
	var out contract.FeatureApplicability
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.contextReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("context_features")).Get([]byte(reqID))
		if raw == nil {
			return errors.New("feature applicability not found")
		}
		return contract.StrictJSON(raw, &out)
	})
	return out, e
}
