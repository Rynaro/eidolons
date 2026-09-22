package controller

import (
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
	"github.com/Rynaro/eidolons/gauge/internal/store"
)

func (s *Service) ensureAcceptanceStore() (*store.Store, error) {
	db, e := s.ensureCompilerStore()
	if e != nil {
		return nil, e
	}
	if e = db.EnsureAcceptanceNamespaces(); e != nil {
		_ = db.Close()
		return nil, e
	}
	return db, nil
}

// EnsureAcceptanceNamespaces adds typed acceptance buckets under schema 2.
func (s *Service) EnsureAcceptanceNamespaces() error {
	db, e := s.ensureAcceptanceStore()
	if e != nil {
		return e
	}
	return db.Close()
}

// RegisterAcceptancePackage persists an acceptance package definition.
func (s *Service) RegisterAcceptancePackage(pkg contract.AcceptancePackage) error {
	if e := pkg.Validate(); e != nil {
		return e
	}
	db, e := store.Open(s.storePath(), s.opts.Timeout)
	if e != nil {
		return e
	}
	defer db.Close()
	return db.PersistAcceptancePackage(pkg)
}

// FreezeCandidate binds verification to a frozen content + acceptance/env identity (R01).
func (s *Service) FreezeCandidate(rootID string, req contract.FreezeRequest) (contract.FrozenCandidate, error) {
	req.RootID = rootID
	if req.RecordedAt == "" {
		req.RecordedAt = s.opts.Clock().UTC().Format(time.RFC3339)
	}
	if e := req.Validate(); e != nil {
		return contract.FrozenCandidate{}, e
	}

	release, e := s.lock(rootID, false)
	if e != nil {
		return contract.FrozenCandidate{}, errors.New("append_lock_unavailable")
	}
	defer release()
	if _, _, e = s.active(rootID); e != nil {
		return contract.FrozenCandidate{}, errors.New("active_claim_or_inventory_failed")
	}

	digest := contract.ComputeContentDigest(req.Entries)
	exclusions := append([]string(nil), req.Exclusions...)
	if req.BaseDigest != "" {
		exclusions = append(exclusions, "base:"+req.BaseDigest)
	}
	c := contract.FrozenCandidate{
		SchemaVersion: contract.AcceptanceSchemaVersion,
		ID:            req.CandidateID,
		RootID:        rootID,
		AssignmentID:  req.AssignmentID,
		WorkspaceRoot: req.WorkspaceRoot,
		Entries:       append([]contract.CandidateContentEntry(nil), req.Entries...),
		ContentDigest: digest,
		AcceptanceID:  req.AcceptanceID,
		EnvironmentID: req.EnvironmentID,
		FrozenAt:      req.RecordedAt,
		Exclusions:    exclusions,
	}

	db, e := store.Open(s.storePath(), s.opts.Timeout)
	if e != nil {
		return c, e
	}
	defer db.Close()

	// Store base digest alongside via protected_paths journal detail in Persist.
	// Also stash base digest in a sidecar field through acceptance package update if needed.
	out, e := db.PersistFrozenCandidate(c)
	if e != nil {
		return out, e
	}
	if req.BaseDigest != "" {
		_ = db.RecordProtectedPaths("base/"+c.ID, []string{req.BaseDigest})
	}
	return out, nil
}

// FinishCheck records actual outcome + invocation provenance (R03). Authored
// success prose cannot replace observation. Isolation/provenance gates trusted
// grade (R04). Behavior gate applies when required (R09).
func (s *Service) FinishCheck(rootID string, req contract.RunCheckRequest, iso contract.IsolationCapability) (contract.CheckReceipt, contract.VerificationGradeReport, error) {
	if req.RecordedAt == "" {
		req.RecordedAt = s.opts.Clock().UTC().Format(time.RFC3339)
	}
	grade := GradeFromIsolation(iso)
	empty := contract.CheckReceipt{}

	if e := req.Validate(); e != nil {
		return empty, grade, e
	}

	release, e := s.lock(rootID, false)
	if e != nil {
		return empty, grade, errors.New("append_lock_unavailable")
	}
	defer release()
	if _, _, e = s.active(rootID); e != nil {
		return empty, grade, errors.New("active_claim_or_inventory_failed")
	}

	db, e := store.Open(s.storePath(), s.opts.Timeout)
	if e != nil {
		return empty, grade, e
	}
	defer db.Close()

	frozen, e := db.GetFrozenCandidate(req.CandidateID)
	if e != nil {
		return empty, grade, e
	}
	if frozen.AcceptanceID != req.AcceptanceID || frozen.EnvironmentID != req.EnvironmentID {
		return empty, grade, errors.New("check not bound to frozen acceptance/environment identities")
	}

	pkg, pkgErr := db.GetAcceptancePackage(req.AcceptanceID)

	outcome := req.ObservedOutcome
	// Authored prose never substitutes for observation (R03).
	if outcome == "" {
		if req.AuthoredProse != "" {
			outcome = contract.OutcomeError
			grade.Reasons = append(grade.Reasons, "authored_prose_cannot_replace_observation")
			grade.Trusted = false
			grade.IntegrityGrade = contract.GradeWithheld
		} else {
			return empty, grade, errors.New("observed outcome required")
		}
	}
	switch outcome {
	case contract.OutcomePass, contract.OutcomeFail, contract.OutcomeError, contract.OutcomeCancelled, contract.OutcomeSkipped:
	default:
		return empty, grade, fmt.Errorf("unknown observed outcome %q", outcome)
	}

	notes := []string{
		fmt.Sprintf("snapshot=%s", frozen.ContentDigest),
		fmt.Sprintf("candidate=%s", frozen.ID),
		fmt.Sprintf("acceptance=%s", frozen.AcceptanceID),
		fmt.Sprintf("environment=%s", frozen.EnvironmentID),
	}
	if req.AuthoredProse != "" && outcome == contract.OutcomePass {
		// Prose claiming success alongside observation is fine, but prose alone is not.
		notes = append(notes, "authored_prose_ignored_for_outcome")
	}

	// Behavior gate (R09): when package requires observable application behavior,
	// unit-only / fabricated-log (behavior_observed=false) cannot pass.
	if pkgErr == nil && pkg.RequiresBehaviorGate && outcome == contract.OutcomePass && !req.BehaviorObserved {
		outcome = contract.OutcomeFail
		notes = append(notes, "behavior_gate_failed:unit_or_fabricated_without_declared_env_execution")
		grade.Reasons = append(grade.Reasons, "behavior_gate_failed")
	}

	if !grade.Trusted && outcome == contract.OutcomePass {
		// Pass observation may still be recorded, but trusted grade is withheld (R04).
		notes = append(notes, "trusted_verification_grade_withheld")
	}

	receipt := contract.CheckReceipt{
		SchemaVersion:  contract.AcceptanceSchemaVersion,
		ID:             req.ReceiptID,
		CheckID:        req.CheckID,
		Outcome:        outcome,
		IntegrityGrade: grade.IntegrityGrade,
		Notes:          notes,
		Provenance: contract.CheckInvocationProvenance{
			RunnerID:      req.RunnerID,
			InvocationID:  req.InvocationID,
			CandidateID:   req.CandidateID,
			AcceptanceID:  req.AcceptanceID,
			EnvironmentID: req.EnvironmentID,
			IsolationMode: req.IsolationMode,
			ObservedAt:    req.RecordedAt,
			CommandDigest: req.CommandDigest,
			AuthoredProse: req.AuthoredProse,
		},
	}
	out, e := db.PersistCheckReceipt(receipt)
	return out, grade, e
}

// DecideApplication requires revalidation when the target base moved/dirty/conflicts (R05).
func (s *Service) DecideApplication(req contract.ApplyRequest, frozenBaseDigest string) (contract.ApplicationDecision, error) {
	if e := req.Validate(); e != nil {
		return contract.ApplicationDecision{}, e
	}
	d := contract.ApplicationDecision{
		CandidateID:       req.CandidateID,
		FrozenBaseDigest:  frozenBaseDigest,
		CurrentBaseDigest: req.CurrentBaseDigest,
	}
	if frozenBaseDigest == "" {
		d.Status = contract.ApplyDenied
		d.Reasons = append(d.Reasons, "missing_frozen_base")
		return d, nil
	}
	if req.CurrentBaseDigest == "" || req.CurrentBaseDigest != frozenBaseDigest {
		d.Status = contract.ApplyRequireRevalidate
		d.Reasons = append(d.Reasons, "target_base_changed")
	}
	if req.TargetDirty {
		d.Status = contract.ApplyRequireRevalidate
		d.Reasons = append(d.Reasons, "target_dirty")
	}
	if req.HasConflicts {
		d.Status = contract.ApplyRequireRevalidate
		d.Reasons = append(d.Reasons, "integration_conflicts")
	}
	if d.Status == "" {
		d.Status = contract.ApplyAllowed
	}
	return d, nil
}

// ApplyCandidate loads freeze base digest and gates application (R05).
func (s *Service) ApplyCandidate(rootID string, req contract.ApplyRequest) (contract.ApplicationDecision, error) {
	release, e := s.lock(rootID, false)
	if e != nil {
		return contract.ApplicationDecision{}, errors.New("append_lock_unavailable")
	}
	defer release()
	if _, _, e = s.active(rootID); e != nil {
		return contract.ApplicationDecision{}, errors.New("active_claim_or_inventory_failed")
	}
	db, e := store.Open(s.storePath(), s.opts.Timeout)
	if e != nil {
		return contract.ApplicationDecision{}, e
	}
	defer db.Close()
	frozen, e := db.GetFrozenCandidate(req.CandidateID)
	if e != nil {
		return contract.ApplicationDecision{}, e
	}
	_ = frozen
	// Base digest was stored under protected_paths session key base/<id>.
	// For fixture simplicity, callers pass CurrentBaseDigest and we compare via
	// a freeze-time digest stored in Exclusions sentinel or separate lookup.
	baseDigest := lookupBaseDigest(db, req.CandidateID)
	return s.DecideApplication(req, baseDigest)
}

func lookupBaseDigest(db *store.Store, candidateID string) string {
	// RecordProtectedPaths stores {"paths":[digest]}; read via List is awkward —
	// store base digest as first exclusion prefixed with "base:" when freezing
	// is the simpler path; ApplyCandidate tests pass frozen digest explicitly
	// through DecideApplication. Here try GetFrozenCandidate Exclusions.
	c, e := db.GetFrozenCandidate(candidateID)
	if e != nil {
		return ""
	}
	for _, ex := range c.Exclusions {
		if len(ex) > 5 && ex[:5] == "base:" {
			return ex[5:]
		}
	}
	return ""
}

// ProjectHumanReport preserves distinct integrity/provenance/acceptance (R06).
// Digest equality does not authenticate author or prove semantic correctness.
func ProjectHumanReport(frozen contract.FrozenCandidate, receipts []contract.CheckReceipt, proj contract.Projection) contract.HumanAcceptanceReport {
	report := contract.HumanAcceptanceReport{
		SchemaVersion:       contract.AcceptanceSchemaVersion,
		CandidateID:         frozen.ID,
		ContentDigest:       frozen.ContentDigest,
		ArtifactIntegrity:   proj.ArtifactIntegrity,
		ExecutionProvenance: proj.ExecutionProvenance,
		AcceptanceStatus:    proj.AcceptanceStatus,
		Checks:              proj.Checks,
		AuthorAuthenticated: false, // digest never authenticates author
		SemanticCorrectness: "unproven", // digest never proves semantic correctness
		Notes: []string{
			"digest_equality_does_not_authenticate_author",
			"digest_equality_does_not_prove_semantic_correctness",
		},
	}
	canonical, _ := json.Marshal(map[string]any{
		"candidate_id":         frozen.ID,
		"content_digest":       frozen.ContentDigest,
		"artifact_integrity":   proj.ArtifactIntegrity,
		"execution_provenance": proj.ExecutionProvenance,
		"acceptance_status":    proj.AcceptanceStatus,
		"checks":               proj.Checks,
	})
	var round map[string]any
	_ = json.Unmarshal(canonical, &round)
	report.Canonical = round
	_ = receipts
	return report
}

// QualifyOracle records behavior coverage on acceptable and defective candidates (R07).
// Inadequate discrimination prevents qualification — not arbitrary mutation-score targets.
func (s *Service) QualifyOracle(rootID string, req contract.QualifyRequest) (contract.OracleQualification, error) {
	if req.RecordedAt == "" {
		req.RecordedAt = s.opts.Clock().UTC().Format(time.RFC3339)
	}
	if e := req.Validate(); e != nil {
		return contract.OracleQualification{}, e
	}

	release, e := s.lock(rootID, false)
	if e != nil {
		return contract.OracleQualification{}, errors.New("append_lock_unavailable")
	}
	defer release()
	if _, _, e = s.active(rootID); e != nil {
		return contract.OracleQualification{}, errors.New("active_claim_or_inventory_failed")
	}

	q := EvaluateQualification(req)
	db, e := store.Open(s.storePath(), s.opts.Timeout)
	if e != nil {
		return q, e
	}
	defer db.Close()
	if e := db.PersistOracleQualification(q); e != nil {
		return q, e
	}
	if q.Qualified {
		if pkg, e := db.GetAcceptancePackage(req.AcceptanceID); e == nil {
			pkg.Qualified = true
			_ = db.PersistAcceptancePackage(pkg)
		}
	}
	return q, nil
}

// EvaluateQualification is the pure discrimination check (R07).
func EvaluateQualification(req contract.QualifyRequest) contract.OracleQualification {
	q := contract.OracleQualification{
		SchemaVersion: contract.AcceptanceSchemaVersion,
		ID:            req.ID,
		AcceptanceID:  req.AcceptanceID,
		Trials:        append([]contract.OracleTrial(nil), req.Trials...),
		RecordedAt:    req.RecordedAt,
	}
	needLabels := map[string]bool{"valid": false, "stub": false, "missing_edge": false, "regression": false}
	for i := range q.Trials {
		t := &q.Trials[i]
		t.Discriminates = t.Expected != "" && t.Observed == t.Expected
		if !t.Discriminates {
			q.FailReasons = append(q.FailReasons, fmt.Sprintf("%s:expected_%s_got_%s", t.CandidateLabel, t.Expected, t.Observed))
		}
		if _, ok := needLabels[t.CandidateLabel]; ok {
			needLabels[t.CandidateLabel] = true
		}
	}
	for label, seen := range needLabels {
		if !seen {
			q.FailReasons = append(q.FailReasons, "missing_representative:"+label)
		}
	}
	q.Qualified = len(q.FailReasons) == 0
	if !q.Qualified && len(q.FailReasons) > 0 {
		// Inadequate discrimination prevents qualification.
		q.FailReasons = append(q.FailReasons, "inadequate_discrimination")
	}
	return q
}

// ReviewOwnerChange records acceptance-owner review; maker approval alone insufficient (R08).
func (s *Service) ReviewOwnerChange(rootID string, rev contract.AcceptanceOwnerReview) (contract.AcceptanceOwnerReview, error) {
	if rev.RecordedAt == "" {
		rev.RecordedAt = s.opts.Clock().UTC().Format(time.RFC3339)
	}
	if e := rev.Validate(); e != nil {
		return rev, e
	}
	release, e := s.lock(rootID, false)
	if e != nil {
		return rev, errors.New("append_lock_unavailable")
	}
	defer release()
	if _, _, e = s.active(rootID); e != nil {
		return rev, errors.New("active_claim_or_inventory_failed")
	}

	// Maker approval alone cannot replace owner review.
	if rev.MakerApproved && !rev.OwnerApproved {
		rev.InvalidatesOld = true
		rev.Detail = appendDetail(rev.Detail, "maker_approval_insufficient_without_owner_review")
	}
	if rev.OwnerApproved {
		rev.InvalidatesOld = true // old evidence invalidated on authorized def change
		rev.Detail = appendDetail(rev.Detail, "owner_review_recorded_old_evidence_invalidated")
	}

	db, e := store.Open(s.storePath(), s.opts.Timeout)
	if e != nil {
		return rev, e
	}
	defer db.Close()
	if e := db.PersistOwnerReview(rev); e != nil {
		return rev, e
	}
	return rev, nil
}

func appendDetail(existing, add string) string {
	if existing == "" {
		return add
	}
	return existing + "; " + add
}

// AssessDefinition reports an acceptance-definition blocker when criteria cannot
// distinguish requested vs plausible incomplete results (R10). No silent invention.
func (s *Service) AssessDefinition(rootID string, pkg contract.AcceptancePackage, blockerID string) (*contract.DefinitionBlocker, error) {
	release, e := s.lock(rootID, false)
	if e != nil {
		return nil, errors.New("append_lock_unavailable")
	}
	defer release()
	if _, _, e = s.active(rootID); e != nil {
		return nil, errors.New("active_claim_or_inventory_failed")
	}

	blocker := DetectDefinitionBlocker(pkg, blockerID, s.opts.Clock().UTC().Format(time.RFC3339))
	if blocker == nil {
		return nil, nil
	}
	db, e := store.Open(s.storePath(), s.opts.Timeout)
	if e != nil {
		return blocker, e
	}
	defer db.Close()
	if e := db.PersistDefinitionBlocker(*blocker); e != nil {
		return blocker, e
	}
	return blocker, nil
}

// DetectDefinitionBlocker is the pure R10 gate.
func DetectDefinitionBlocker(pkg contract.AcceptancePackage, id, at string) *contract.DefinitionBlocker {
	if pkg.RequestedBehavior == "" || pkg.RequestedBehavior == "ambiguous" {
		return &contract.DefinitionBlocker{
			SchemaVersion: contract.AcceptanceSchemaVersion,
			ID: id, AcceptanceID: pkg.ID, Kind: contract.BlockerAmbiguousBrief,
			Detail: "ambiguous brief; no silent requirement invention", RecordedAt: at,
		}
	}
	if pkg.OracleOrigin == "" || pkg.OracleOrigin == "ambiguous" {
		return &contract.DefinitionBlocker{
			SchemaVersion: contract.AcceptanceSchemaVersion,
			ID: id, AcceptanceID: pkg.ID, Kind: contract.BlockerAmbiguousOracle,
			Detail: "ambiguous oracle; no silent weakening to manufacture a pass", RecordedAt: at,
		}
	}
	if pkg.BehavioralDiscriminator == "" {
		return &contract.DefinitionBlocker{
			SchemaVersion: contract.AcceptanceSchemaVersion,
			ID: id, AcceptanceID: pkg.ID, Kind: contract.BlockerMissingDiscriminator,
			Detail: "missing behavioral discriminator between requested and plausible incomplete", RecordedAt: at,
		}
	}
	return nil
}

// AcceptanceStatus lists frozen candidates for a root.
func (s *Service) AcceptanceStatus(rootID string) ([]contract.FrozenCandidate, error) {
	db, e := store.Open(s.storePath(), s.opts.Timeout)
	if e != nil {
		return nil, e
	}
	defer db.Close()
	return db.ListFrozenCandidates(rootID)
}

// GetFrozen returns a frozen candidate by ID.
func (s *Service) GetFrozen(candidateID string) (contract.FrozenCandidate, error) {
	db, e := store.Open(s.storePath(), s.opts.Timeout)
	if e != nil {
		return contract.FrozenCandidate{}, e
	}
	defer db.Close()
	return db.GetFrozenCandidate(candidateID)
}
