package controller

import (
	"errors"
	"fmt"
	"time"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
	"github.com/Rynaro/eidolons/gauge/internal/store"
)

func (s *Service) ensureObservationStore() (*store.Store, error) {
	db, e := s.preferencesStore()
	if e != nil {
		return nil, e
	}
	if e = db.EnsureObservationNamespaces(); e != nil {
		_ = db.Close()
		return nil, e
	}
	return db, nil
}

func (s *Service) EnsureObservationNamespaces() error {
	db, e := s.ensureObservationStore()
	if e != nil {
		return e
	}
	return db.Close()
}

// StartTask allocates a fresh UUID execution root distinct from the route digest.
func (s *Service) StartTask(routeDigest string) (contract.TaskStartResult, error) {
	var result contract.TaskStartResult
	if routeDigest == "" || len(routeDigest) > 128 {
		return result, errors.New("route digest required and bounded")
	}
	if e := contract.ValidateMetadata(map[string]string{"note_ref": "ok"}); e != nil {
		return result, e
	}
	rootID := contract.NewUUID()
	// UUID contains hyphens which ValidRoot allows via runName.
	if !contract.ValidRoot(rootID) {
		return result, errors.New("allocated root identity rejected")
	}
	if e := s.InitRoot(rootID); e != nil {
		return result, e
	}
	taskID := contract.NewUUID()
	now := s.opts.Clock().UTC().Format(time.RFC3339)
	db, e := s.ensureObservationStore()
	if e != nil {
		return result, e
	}
	defer db.Close()
	snap, e := db.Snapshot()
	if e != nil {
		return result, e
	}
	root := snap.Roots[rootID]
	edge := contract.LineageEdge{
		SchemaVersion: contract.ObservationSchemaVersion,
		ID:            "route-" + contract.Digest([]byte(routeDigest))[:16],
		RootID:        rootID,
		Role:          contract.LineageRoute,
		ChildID:       rootID,
		RouteDigest:   routeDigest,
		AssignmentID:  root.Binding.Assignment,
		InvocationID:  root.Binding.Invocation,
		ConfigID:      contract.Digest([]byte("config:" + root.Manifest.Adapter + ":" + root.Generation))[:32],
		CreatedAt:     now,
	}
	taskEdge := contract.LineageEdge{
		SchemaVersion: contract.ObservationSchemaVersion,
		ID:            "task-" + taskID[:8],
		RootID:        rootID,
		Role:          contract.LineageTask,
		ChildID:       taskID,
		AssignmentID:  root.Binding.Assignment,
		InvocationID:  root.Binding.Invocation,
		ConfigID:      edge.ConfigID,
		RouteDigest:   routeDigest,
		CreatedAt:     now,
	}
	if e = db.PutLineage(edge); e != nil {
		return result, e
	}
	if e = db.PutLineage(taskEdge); e != nil {
		return result, e
	}
	result = contract.TaskStartResult{
		RootID: rootID, TaskID: taskID, RouteDigest: routeDigest,
		Assignment: root.Binding.Assignment, Invocation: root.Binding.Invocation, ConfigID: edge.ConfigID,
	}
	return result, nil
}

// ResumeRoot resolves an existing durable root; unknown IDs fail without creating a root.
func (s *Service) ResumeRoot(id string) error {
	if !contract.ValidRoot(id) {
		return errors.New("invalid root identity")
	}
	snap, e := s.inspect()
	if e != nil {
		return e
	}
	if _, ok := snap.Roots[id]; !ok {
		return fmt.Errorf("unknown root %s; resume refused without creating", id)
	}
	_, _, e = s.active(id)
	return e
}

// BindLineage attaches descendant/reviewer/retry/successor to the original root.
func (s *Service) BindLineage(rootID string, edge contract.LineageEdge) error {
	edge.RootID = rootID
	if e := edge.Validate(); e != nil {
		return e
	}
	switch edge.Role {
	case contract.RoleDescendant, contract.RoleReviewer, contract.RoleRetry, contract.RoleSuccessor,
		contract.LineageAssignment, contract.LineageInvocation, contract.LineageConfig,
		contract.LineageCandidate, contract.LineageIntent, contract.LineageCausalEvent, contract.LineagePolicy:
	default:
		return errors.New("unsupported lineage role")
	}
	release, e := s.lock(rootID, false)
	if e != nil {
		return e
	}
	defer release()
	if _, _, e = s.active(rootID); e != nil {
		return e
	}
	db, e := store.Open(s.storePath(), s.opts.Timeout)
	if e != nil {
		return e
	}
	defer db.Close()
	if e = db.EnsureObservationNamespaces(); e != nil {
		return e
	}
	return db.PutLineage(edge)
}

// RecordUsage persists a typed usage observation under append lock and active checks.
func (s *Service) RecordUsage(rootID string, o contract.UsageObservation) error {
	o.RootID = rootID
	if e := o.Validate(); e != nil {
		return errors.New("observation validation failed")
	}
	release, e := s.lock(rootID, false)
	if e != nil {
		return e
	}
	defer release()
	_, root, e := s.active(rootID)
	if e != nil {
		return e
	}
	// Historical links stay with the observation; do not rewrite from latest binding.
	if o.AssignmentID == "" {
		o.AssignmentID = root.Binding.Assignment
	}
	if o.InvocationID == "" {
		o.InvocationID = root.Binding.Invocation
	}
	if o.TaskID == "" {
		o.TaskID = rootID
	}
	if o.ConfigurationID == "" {
		o.ConfigurationID = "unspecified-configuration"
	}
	if o.ReceiptTime == "" {
		o.ReceiptTime = s.opts.Clock().UTC().Format(time.RFC3339)
	}
	o.DetailRetained = true
	db, e := store.Open(s.storePath(), s.opts.Timeout)
	if e != nil {
		return e
	}
	defer db.Close()
	if e = db.EnsureObservationNamespaces(); e != nil {
		return e
	}
	return db.PutUsageObservation(o)
}

// CorrectUsage records a correction identity; forks/conflicts reject.
func (s *Service) CorrectUsage(rootID string, c contract.UsageCorrection) error {
	c.RootID = rootID
	if e := c.Validate(); e != nil {
		return errors.New("correction validation failed")
	}
	release, e := s.lock(rootID, false)
	if e != nil {
		return e
	}
	defer release()
	if _, _, e = s.active(rootID); e != nil {
		return e
	}
	if c.ReceiptTime == "" {
		c.ReceiptTime = s.opts.Clock().UTC().Format(time.RFC3339)
	}
	db, e := store.Open(s.storePath(), s.opts.Timeout)
	if e != nil {
		return e
	}
	defer db.Close()
	if e = db.EnsureObservationNamespaces(); e != nil {
		return e
	}
	return db.PutUsageCorrection(c)
}

func (s *Service) SummarizeUsage(rootID string, stream contract.StreamIdentity) (contract.UsageSummary, error) {
	if _, e := s.Status(rootID); e != nil {
		return contract.UsageSummary{}, e
	}
	db, e := s.ensureObservationStore()
	if e != nil {
		return contract.UsageSummary{}, e
	}
	defer db.Close()
	return db.SummarizeUsage(rootID, stream)
}

func (s *Service) ExportUsage(rootID string) (contract.UsageExport, error) {
	if _, e := s.Status(rootID); e != nil {
		return contract.UsageExport{}, e
	}
	db, e := s.ensureObservationStore()
	if e != nil {
		return contract.UsageExport{}, e
	}
	defer db.Close()
	return db.ExportUsage(rootID)
}

func (s *Service) RetainUsage(rootID string) error {
	release, e := s.lock(rootID, false)
	if e != nil {
		return e
	}
	defer release()
	if _, _, e = s.active(rootID); e != nil {
		return e
	}
	db, e := store.Open(s.storePath(), s.opts.Timeout)
	if e != nil {
		return e
	}
	defer db.Close()
	if e = db.EnsureObservationNamespaces(); e != nil {
		return e
	}
	return db.RetainUsage(rootID)
}
