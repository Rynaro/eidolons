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

var observationBuckets = []string{"usage_observations", "usage_corrections", "lineage_edges", "coverage_reports"}

type observationReceipt struct {
	Version    int    `json:"schema_version"`
	Controller string `json:"controller"`
	Kind       string `json:"kind"`
	Typed      int    `json:"typed_version"`
}

func initializeObservation(tx *bolt.Tx, id, kind string) error {
	for _, name := range observationBuckets {
		if _, e := tx.CreateBucketIfNotExists([]byte(name)); e != nil {
			return e
		}
	}
	return putJSON(tx.Bucket([]byte("meta")), "observation_receipt", observationReceipt{
		Version: 1, Controller: id, Kind: kind, Typed: contract.ObservationSchemaVersion,
	})
}

func guardObservation(tx *bolt.Tx) error {
	meta := tx.Bucket([]byte("meta"))
	raw := meta.Get([]byte("observation_receipt"))
	missing := 0
	for _, name := range observationBuckets {
		if tx.Bucket([]byte(name)) == nil {
			missing++
		}
	}
	if raw == nil && missing == len(observationBuckets) {
		// Pre-V4-08 schema 2 stores remain openable; observation APIs ensure namespaces.
		return nil
	}
	if raw == nil || missing != 0 {
		return errors.New("incomplete observation namespaces; call observation-enable")
	}
	var receipt observationReceipt
	if e := contract.StrictJSON(raw, &receipt); e != nil {
		return errors.New("invalid observation receipt")
	}
	id := string(meta.Get([]byte("store_id")))
	if receipt.Version != 1 || receipt.Controller != id || receipt.Typed != contract.ObservationSchemaVersion {
		return errors.New("unsupported observation receipt")
	}
	if e := tx.Bucket([]byte("usage_observations")).ForEach(func(k, v []byte) error {
		var o contract.UsageObservation
		if e := contract.StrictJSON(v, &o); e != nil {
			return e
		}
		if o.ID != string(k) && rootObservationKey(o.RootID, o.ID) != string(k) {
			return errors.New("observation identity mismatch")
		}
		return o.Validate()
	}); e != nil {
		return e
	}
	if e := tx.Bucket([]byte("usage_corrections")).ForEach(func(k, v []byte) error {
		var c contract.UsageCorrection
		if e := contract.StrictJSON(v, &c); e != nil {
			return e
		}
		if rootObservationKey(c.RootID, c.ID) != string(k) && c.ID != string(k) {
			return errors.New("correction identity mismatch")
		}
		return c.Validate()
	}); e != nil {
		return e
	}
	return tx.Bucket([]byte("lineage_edges")).ForEach(func(k, v []byte) error {
		var edge contract.LineageEdge
		if e := contract.StrictJSON(v, &edge); e != nil {
			return e
		}
		if rootObservationKey(edge.RootID, edge.ID) != string(k) && edge.ID != string(k) {
			return errors.New("lineage identity mismatch")
		}
		return edge.Validate()
	})
}

func rootObservationKey(root, id string) string {
	return root + "/" + id
}

func (s *Store) observationReady(tx *bolt.Tx) error {
	for _, name := range observationBuckets {
		if tx.Bucket([]byte(name)) == nil {
			return errors.New("observation namespaces required")
		}
	}
	if tx.Bucket([]byte("meta")).Get([]byte("observation_receipt")) == nil {
		return errors.New("observation namespaces required")
	}
	return nil
}

// EnsureObservationNamespaces adds typed observation buckets under schema 2 without a schema bump.
func (s *Store) EnsureObservationNamespaces() error {
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := guardBase(tx, "2"); e != nil {
			return e
		}
		if e := guardPolicy(tx); e != nil {
			return e
		}
		id := string(tx.Bucket([]byte("meta")).Get([]byte("store_id")))
		if raw := tx.Bucket([]byte("meta")).Get([]byte("observation_receipt")); raw != nil {
			return guardObservation(tx)
		}
		if e := initializeObservation(tx, id, "ensure"); e != nil {
			return e
		}
		return guardObservation(tx)
	})
}

func (s *Store) PutLineage(edge contract.LineageEdge) error {
	if e := edge.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.observationReady(tx); e != nil {
			return e
		}
		if tx.Bucket([]byte("roots")).Get([]byte(edge.RootID)) == nil {
			return errors.New("unknown root for lineage")
		}
		key := rootObservationKey(edge.RootID, edge.ID)
		b := tx.Bucket([]byte("lineage_edges"))
		if prev := b.Get([]byte(key)); prev != nil {
			var existing contract.LineageEdge
			if e := contract.StrictJSON(prev, &existing); e != nil {
				return e
			}
			if !reflect.DeepEqual(existing, edge) {
				return errors.New("lineage identity conflict")
			}
			return nil
		}
		return putJSON(b, key, edge)
	})
}

func (s *Store) PutUsageObservation(o contract.UsageObservation) error {
	if e := o.Validate(); e != nil {
		return scrubErr(e)
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.observationReady(tx); e != nil {
			return e
		}
		if tx.Bucket([]byte("roots")).Get([]byte(o.RootID)) == nil {
			return errors.New("unknown root for observation")
		}
		key := rootObservationKey(o.RootID, o.ID)
		b := tx.Bucket([]byte("usage_observations"))
		if prev := b.Get([]byte(key)); prev != nil {
			var existing contract.UsageObservation
			if e := contract.StrictJSON(prev, &existing); e != nil {
				return e
			}
			raw, e := json.Marshal(o)
			if e != nil {
				return e
			}
			prevRaw, e := json.Marshal(existing)
			if e != nil {
				return e
			}
			if !reflect.DeepEqual(existing, o) && string(raw) != string(prevRaw) {
				return errors.New("observation identity conflict")
			}
			return nil
		}
		return putJSON(b, key, o)
	})
}

func (s *Store) PutUsageCorrection(c contract.UsageCorrection) error {
	if e := c.Validate(); e != nil {
		return scrubErr(e)
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.observationReady(tx); e != nil {
			return e
		}
		if tx.Bucket([]byte("roots")).Get([]byte(c.RootID)) == nil {
			return errors.New("unknown root for correction")
		}
		obsKey := rootObservationKey(c.RootID, c.TargetID)
		if tx.Bucket([]byte("usage_observations")).Get([]byte(obsKey)) == nil {
			// Pending: store correction but it contributes nothing until target exists.
			// Still persist so the pending state is identifiable.
		}
		key := rootObservationKey(c.RootID, c.ID)
		b := tx.Bucket([]byte("usage_corrections"))
		if prev := b.Get([]byte(key)); prev != nil {
			var existing contract.UsageCorrection
			if e := contract.StrictJSON(prev, &existing); e != nil {
				return e
			}
			if !reflect.DeepEqual(existing, c) {
				return errors.New("correction identity conflict")
			}
			return nil
		}
		// Reject forks: another correction already targets same revision with different ID.
		if e := b.ForEach(func(_, v []byte) error {
			var other contract.UsageCorrection
			if e := contract.StrictJSON(v, &other); e != nil {
				return e
			}
			if other.RootID == c.RootID && other.TargetID == c.TargetID && other.TargetRevision == c.TargetRevision && other.ID != c.ID {
				if other.NewAmount != c.NewAmount || other.ReplacementRev != c.ReplacementRev {
					return errors.New("correction fork rejected")
				}
			}
			return nil
		}); e != nil {
			return e
		}
		return putJSON(b, key, c)
	})
}

func (s *Store) ListUsageObservations(root string) ([]contract.UsageObservation, error) {
	var out []contract.UsageObservation
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.observationReady(tx); e != nil {
			return e
		}
		prefix := root + "/"
		return tx.Bucket([]byte("usage_observations")).ForEach(func(k, v []byte) error {
			if !hasPrefix(string(k), prefix) {
				return nil
			}
			var o contract.UsageObservation
			if e := contract.StrictJSON(v, &o); e != nil {
				return e
			}
			out = append(out, o)
			return nil
		})
	})
	sort.Slice(out, func(i, j int) bool { return out[i].ID < out[j].ID })
	return out, e
}

func (s *Store) ListUsageCorrections(root string) ([]contract.UsageCorrection, error) {
	var out []contract.UsageCorrection
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.observationReady(tx); e != nil {
			return e
		}
		prefix := root + "/"
		return tx.Bucket([]byte("usage_corrections")).ForEach(func(k, v []byte) error {
			if !hasPrefix(string(k), prefix) {
				return nil
			}
			var c contract.UsageCorrection
			if e := contract.StrictJSON(v, &c); e != nil {
				return e
			}
			out = append(out, c)
			return nil
		})
	})
	sort.Slice(out, func(i, j int) bool { return out[i].ID < out[j].ID })
	return out, e
}

func (s *Store) ListLineage(root string) ([]contract.LineageEdge, error) {
	var out []contract.LineageEdge
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.observationReady(tx); e != nil {
			return e
		}
		prefix := root + "/"
		return tx.Bucket([]byte("lineage_edges")).ForEach(func(k, v []byte) error {
			if !hasPrefix(string(k), prefix) {
				return nil
			}
			var edge contract.LineageEdge
			if e := contract.StrictJSON(v, &edge); e != nil {
				return e
			}
			out = append(out, edge)
			return nil
		})
	})
	sort.Slice(out, func(i, j int) bool { return out[i].ID < out[j].ID })
	return out, e
}

func (s *Store) SummarizeUsage(root string, stream contract.StreamIdentity) (contract.UsageSummary, error) {
	var summary contract.UsageSummary
	obs, e := s.ListUsageObservations(root)
	if e != nil {
		return summary, e
	}
	corr, e := s.ListUsageCorrections(root)
	if e != nil {
		return summary, e
	}
	filtered := []contract.UsageObservation{}
	ids := []string{}
	reqModel, obsModel := "", ""
	coverage := contract.DefaultCoverage()
	seenDim := map[string]bool{}
	for _, o := range obs {
		if o.Stream.Key() != stream.Key() {
			continue
		}
		filtered = append(filtered, o)
		ids = append(ids, o.ID)
		if o.RequestedModel != "" {
			reqModel = o.RequestedModel
		}
		if o.ObservedModel != "" {
			obsModel = o.ObservedModel
		}
		markCoverage(coverage, o.Stream.Dimension, contract.CoverageKnown)
		seenDim[o.Stream.Dimension] = true
	}
	_ = seenDim
	cids := []string{}
	fcorr := []contract.UsageCorrection{}
	for _, c := range corr {
		if c.Stream.Key() != stream.Key() {
			continue
		}
		fcorr = append(fcorr, c)
		cids = append(cids, c.ID)
	}
	result := contract.ReconcileObservations(filtered, fcorr)
	summary = contract.UsageSummary{
		RootID: root, Stream: stream, State: result.State, Total: result.Total, TotalKnown: result.TotalKnown,
		HistoricalSnapshot: result.HistoricalSnapshot, ChildBreakdown: result.ChildBreakdown,
		PendingTargets: result.PendingTargets, RuleVersion: result.RuleVersion,
		Coverage: coverage, RequestedModel: reqModel, ObservedModel: obsModel,
		Observations: ids, Corrections: cids,
	}
	if obsModel == "" && reqModel != "" {
		summary.ObservedModel = ""
	}
	return summary, nil
}

func (s *Store) ExportUsage(root string) (contract.UsageExport, error) {
	var exp contract.UsageExport
	obs, e := s.ListUsageObservations(root)
	if e != nil {
		return exp, e
	}
	corr, e := s.ListUsageCorrections(root)
	if e != nil {
		return exp, e
	}
	lineage, e := s.ListLineage(root)
	if e != nil {
		return exp, e
	}
	// Strip non-retained detail and never include raw private fields (already allowlisted).
	safeObs := make([]contract.UsageObservation, 0, len(obs))
	for _, o := range obs {
		if !o.DetailRetained {
			o.Metadata = nil
		}
		safeObs = append(safeObs, o)
	}
	route := ""
	for _, edge := range lineage {
		if edge.Role == contract.LineageRoute && edge.RouteDigest != "" {
			route = edge.RouteDigest
		}
	}
	streams := map[string]contract.StreamIdentity{}
	for _, o := range obs {
		streams[o.Stream.Key()] = o.Stream
	}
	summaries := []contract.UsageSummary{}
	keys := make([]string, 0, len(streams))
	for k := range streams {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		sum, e := s.SummarizeUsage(root, streams[k])
		if e != nil {
			return exp, e
		}
		summaries = append(summaries, sum)
	}
	exp = contract.UsageExport{RootID: root, RouteDigest: route, Lineage: lineage, Observations: safeObs, Corrections: corr, Summaries: summaries}
	return exp, nil
}

func (s *Store) RetainUsage(root string) error {
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.observationReady(tx); e != nil {
			return e
		}
		prefix := root + "/"
		b := tx.Bucket([]byte("usage_observations"))
		return b.ForEach(func(k, v []byte) error {
			if !hasPrefix(string(k), prefix) {
				return nil
			}
			var o contract.UsageObservation
			if e := contract.StrictJSON(v, &o); e != nil {
				return e
			}
			o.Metadata = nil
			o.DetailRetained = false
			return putJSON(b, string(k), o)
		})
	})
}

func markCoverage(coverage []contract.CoverageDimension, dimension, status string) {
	mapped := dimension
	switch dimension {
	case "tokens", "inference", "uncached_input", "cached_input", "output":
		mapped = contract.DimInference
	case "transfer", "context", "tool":
		mapped = contract.DimTransfer
	case "environment", "compute":
		mapped = contract.DimEnvironment
	case "elapsed", "latency":
		mapped = contract.DimElapsed
	case "human", "intervention":
		mapped = contract.DimHuman
	}
	for i := range coverage {
		if coverage[i].Name == mapped {
			coverage[i].Status = status
		}
	}
}

func hasPrefix(s, prefix string) bool {
	return len(s) >= len(prefix) && s[:len(prefix)] == prefix
}

func scrubErr(e error) error {
	if e == nil {
		return nil
	}
	// Never echo rejected private payload contents.
	msg := e.Error()
	if len(msg) > 120 {
		return errors.New("observation validation failed")
	}
	if containsPrivateHint(msg) {
		return fmt.Errorf("observation validation failed: private payload refused")
	}
	return e
}

func containsPrivateHint(msg string) bool {
	for _, p := range []string{"private payload", "credential", "transcript", "reasoning"} {
		if len(msg) >= len(p) {
			for i := 0; i+len(p) <= len(msg); i++ {
				if msg[i:i+len(p)] == p {
					return true
				}
			}
		}
	}
	return false
}
