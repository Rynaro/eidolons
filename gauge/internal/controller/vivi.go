package controller

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"os"
	"path/filepath"
	"strconv"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
	"github.com/Rynaro/eidolons/gauge/internal/store"
)

func (s *Service) ensureViviStore() (*store.Store, error) {
	db, e := s.ensureStatusStore()
	if e != nil {
		return nil, e
	}
	if e = db.EnsureEvaluationNamespaces(); e != nil {
		_ = db.Close()
		return nil, e
	}
	if e = db.EnsureViviNamespaces(); e != nil {
		_ = db.Close()
		return nil, e
	}
	return db, nil
}

// EnsureViviNamespaces adds typed Vivi candidate/context mode buckets under schema 2.
func (s *Service) EnsureViviNamespaces() error {
	db, e := s.ensureViviStore()
	if e != nil {
		return e
	}
	return db.Close()
}

// StartViviSession opens a fixture-local Vivi modes session. Live remains blocked.
func (s *Service) StartViviSession(sess contract.ViviSession) (contract.ViviSession, error) {
	sess.SchemaVersion = contract.ViviSchemaVersion
	sess.ContractVersion = contract.ViviModesContractID
	sess.LiveBlocked = true
	if sess.RecordedAt == "" {
		sess.RecordedAt = s.nowRFC3339()
	}
	if e := sess.Validate(); e != nil {
		return sess, e
	}
	db, e := s.ensureViviStore()
	if e != nil {
		return sess, e
	}
	defer db.Close()
	if e = db.PutViviSession(sess); e != nil {
		return sess, e
	}
	return db.GetViviSession(sess.ID)
}

// SelectViviMode records a named opt-in mode. Gauge never grants publication authority.
func (s *Service) SelectViviMode(m contract.ViviModeSelection) (contract.ViviModeSelection, error) {
	m.SchemaVersion = contract.ViviSchemaVersion
	m.ContractVersion = contract.ViviModesContractID
	m.PublicationAuthority = false
	if m.RecordedAt == "" {
		m.RecordedAt = s.nowRFC3339()
	}
	if e := m.Validate(); e != nil {
		return m, e
	}
	db, e := s.ensureViviStore()
	if e != nil {
		return m, e
	}
	defer db.Close()
	if e = db.PutViviMode(m); e != nil {
		return m, e
	}
	return db.GetViviMode(m.ID)
}

// AttemptViviEdit enforces candidate-workspace scoping and proposal-only controls (R01/R02).
func (s *Service) AttemptViviEdit(sessionID, modeID, targetPath, content string, dirtyUnrelated bool) (contract.ViviEditAttempt, error) {
	db, e := s.ensureViviStore()
	if e != nil {
		return contract.ViviEditAttempt{}, e
	}
	defer db.Close()
	mode, e := db.GetViviMode(modeID)
	if e != nil {
		return contract.ViviEditAttempt{}, e
	}
	if mode.SessionID != sessionID {
		return contract.ViviEditAttempt{}, errors.New("mode session mismatch")
	}
	attempt := contract.ViviEditAttempt{
		SchemaVersion: contract.ViviSchemaVersion,
		ID:            "edit-" + digest8(sessionID+"|"+modeID+"|"+targetPath+"|"+content),
		SessionID:     sessionID,
		ModeID:        modeID,
		TargetPath:    targetPath,
		RecordedAt:    s.nowRFC3339(),
	}
	if dirtyUnrelated {
		attempt.DirtyUnrelated = true
		attempt.Outcome = contract.EditRejectedUnrelated
		attempt.AppliedToUser = false
		if e = db.PutViviEdit(attempt); e != nil {
			return attempt, e
		}
		return attempt, errors.New("unrelated dirty work rejected")
	}
	switch mode.Mode {
	case contract.ViviModeProposalOnly:
		attempt.Outcome = contract.EditRejectedProposalOnly
		attempt.AppliedToUser = false
		if e = db.PutViviEdit(attempt); e != nil {
			return attempt, e
		}
		return attempt, errors.New("proposal-only mode rejects direct edits; emit a proposal")
	case contract.ViviModeCandidateWorkspace:
		if !mode.ScopedAuthorization || mode.AuthorizedWorkspace == "" {
			attempt.Outcome = contract.EditRejectedUnauthorized
			if e = db.PutViviEdit(attempt); e != nil {
				return attempt, e
			}
			return attempt, errors.New("candidate-workspace requires scoped authorization")
		}
		outcome, rel, e := contract.ClassifyCandidatePath(mode.UserTreeRoot, mode.AuthorizedWorkspace, targetPath, mode.ProtectedPaths)
		if e != nil {
			return attempt, e
		}
		attempt.Outcome = outcome
		attempt.RelativeToAuth = rel
		attempt.AppliedToUser = false
		if outcome == contract.EditAccepted {
			// Write only inside the authorized candidate workspace — never the user tree.
			if e = os.MkdirAll(filepath.Dir(targetPath), 0o700); e != nil {
				return attempt, e
			}
			if e = os.WriteFile(targetPath, []byte(content), 0o600); e != nil {
				return attempt, e
			}
			sum := sha256.Sum256([]byte(content))
			attempt.ContentDigest = hex.EncodeToString(sum[:])
			// Confirm user tree file was not created at the same relative path outside auth WS.
			if e = db.PutViviEdit(attempt); e != nil {
				return attempt, e
			}
			return attempt, nil
		}
		if e = db.PutViviEdit(attempt); e != nil {
			return attempt, e
		}
		return attempt, errors.New(outcome)
	default:
		return attempt, errors.New("unsupported vivi mode")
	}
}

// EmitViviProposal returns a candidate proposal without applying it to the user tree (R02).
func (s *Service) EmitViviProposal(sessionID, modeID, diff string) (contract.ViviProposal, error) {
	db, e := s.ensureViviStore()
	if e != nil {
		return contract.ViviProposal{}, e
	}
	defer db.Close()
	mode, e := db.GetViviMode(modeID)
	if e != nil {
		return contract.ViviProposal{}, e
	}
	if mode.SessionID != sessionID {
		return contract.ViviProposal{}, errors.New("mode session mismatch")
	}
	if mode.Mode != contract.ViviModeProposalOnly && mode.Mode != contract.ViviModeCandidateWorkspace {
		return contract.ViviProposal{}, errors.New("proposal requires a named opt-in mode")
	}
	sum := sha256.Sum256([]byte(diff))
	p := contract.ViviProposal{
		SchemaVersion:        contract.ViviSchemaVersion,
		ID:                   "prop-" + hex.EncodeToString(sum[:8]),
		SessionID:            sessionID,
		ModeID:               modeID,
		DiffDigest:           hex.EncodeToString(sum[:]),
		AppliedToUserTree:    false,
		StandaloneCompatible: true,
		RecordedAt:           s.nowRFC3339(),
	}
	if e = p.Validate(); e != nil {
		return p, e
	}
	if e = db.PutViviProposal(p); e != nil {
		return p, e
	}
	return db.GetViviProposal(p.ID)
}

// ApplyViviProposal performs a separate parent-authorized application (R02).
// Without parent authorization the user tree remains untouched.
func (s *Service) ApplyViviProposal(sessionID, proposalID string, parentAuthorized bool, userTreeApplyPath string) (contract.ViviProposalApplication, error) {
	db, e := s.ensureViviStore()
	if e != nil {
		return contract.ViviProposalApplication{}, e
	}
	defer db.Close()
	prop, e := db.GetViviProposal(proposalID)
	if e != nil {
		return contract.ViviProposalApplication{}, e
	}
	if prop.SessionID != sessionID {
		return contract.ViviProposalApplication{}, errors.New("proposal session mismatch")
	}
	app := contract.ViviProposalApplication{
		SchemaVersion:    contract.ViviSchemaVersion,
		ID:               "apply-" + digest8(proposalID+"|"+strconv.FormatBool(parentAuthorized)+"|"+userTreeApplyPath),
		SessionID:        sessionID,
		ProposalID:       proposalID,
		ParentAuthorized: parentAuthorized,
		RecordedAt:       s.nowRFC3339(),
	}
	if !parentAuthorized {
		app.AppliedToUserTree = false
		app.RejectedReason = "parent_authorization_required"
		if e = db.PutViviApplication(app); e != nil {
			return app, e
		}
		return app, errors.New("parent-authorized application required; proposal remains unapplied")
	}
	if userTreeApplyPath == "" {
		app.AppliedToUserTree = false
		app.RejectedReason = "apply_path_required"
		if e = db.PutViviApplication(app); e != nil {
			return app, e
		}
		return app, errors.New("apply path required for parent-authorized application")
	}
	if e = os.MkdirAll(filepath.Dir(userTreeApplyPath), 0o700); e != nil {
		return app, e
	}
	if e = os.WriteFile(userTreeApplyPath, []byte("applied:"+prop.DiffDigest+"\n"), 0o600); e != nil {
		return app, e
	}
	app.AppliedToUserTree = true
	if e = app.Validate(); e != nil {
		return app, e
	}
	if e = db.PutViviApplication(app); e != nil {
		return app, e
	}
	return app, nil
}

// InitViviContinuity starts continuity tracking for a coherent task (R03).
func (s *Service) InitViviContinuity(c contract.ViviContinuityState) (contract.ViviContinuityState, error) {
	c.SchemaVersion = contract.ViviSchemaVersion
	if c.RecordedAt == "" {
		c.RecordedAt = s.nowRFC3339()
	}
	if c.Decisions == nil {
		c.Decisions = []string{}
	}
	if c.FailureHistory == nil {
		c.FailureHistory = []string{}
	}
	c.AccountingPreserved = true
	if e := c.Validate(); e != nil {
		return c, e
	}
	db, e := s.ensureViviStore()
	if e != nil {
		return c, e
	}
	defer db.Close()
	sess, e := db.GetViviSession(c.SessionID)
	if e != nil {
		return c, e
	}
	if c.RootBudgetID == "" {
		c.RootBudgetID = sess.RootBudgetID
	}
	if c.RootBudgetID != sess.RootBudgetID {
		return c, errors.New("continuity root budget must match session")
	}
	if e = c.Validate(); e != nil {
		return c, e
	}
	if e = db.PutViviContinuity(c); e != nil {
		return c, e
	}
	return db.GetViviContinuity(c.ID)
}

// RecordViviRepairAttempt appends a failure and decision under continuity (R03).
func (s *Service) RecordViviRepairAttempt(continuityID, decision, failure string) (contract.ViviContinuityState, error) {
	db, e := s.ensureViviStore()
	if e != nil {
		return contract.ViviContinuityState{}, e
	}
	defer db.Close()
	c, e := db.GetViviContinuity(continuityID)
	if e != nil {
		return c, e
	}
	if !c.ContinuityMode {
		return c, errors.New("continuity mode not active")
	}
	c.RepairAttempts++
	if decision != "" {
		c.Decisions = append(c.Decisions, decision)
	}
	if failure != "" {
		c.FailureHistory = append(c.FailureHistory, failure)
	}
	c.WarmContext = true
	c.AccountingPreserved = true
	c.RecordedAt = s.nowRFC3339()
	if e = c.Validate(); e != nil {
		return c, e
	}
	if e = db.PutViviContinuity(c); e != nil {
		return c, e
	}
	return db.GetViviContinuity(c.ID)
}

// RecordViviContextReset records a reset without resetting root accounting (R03).
func (s *Service) RecordViviContextReset(continuityID, reason string) (contract.ViviContinuityState, error) {
	db, e := s.ensureViviStore()
	if e != nil {
		return contract.ViviContinuityState{}, e
	}
	defer db.Close()
	c, e := db.GetViviContinuity(continuityID)
	if e != nil {
		return c, e
	}
	c.ContextResets++
	c.ResetEvents = append(c.ResetEvents, reason)
	c.AccountingPreserved = true
	// Decisions and failure history are retained across resets under continuity mode.
	c.RecordedAt = s.nowRFC3339()
	if e = c.Validate(); e != nil {
		return c, e
	}
	if e = db.PutViviContinuity(c); e != nil {
		return c, e
	}
	return db.GetViviContinuity(c.ID)
}

// SubmitViviVerification enforces controller-managed maker≠checker boundary (R04).
func (s *Service) SubmitViviVerification(v contract.ViviVerificationSubmission) (contract.ViviVerificationSubmission, error) {
	v.SchemaVersion = contract.ViviSchemaVersion
	if v.RecordedAt == "" {
		v.RecordedAt = s.nowRFC3339()
	}
	// Maker rename/fork cannot mint independent evidence.
	if v.MakerRenamedAsChecker || v.MakerForkedAsChecker {
		v.Rejected = true
		v.RejectedReason = "maker_rename_or_fork_is_not_independent_checker"
		v.EvidenceGrade = contract.EvidenceGradeNone
		v.ObservedEvidenceGrade = contract.EvidenceGradeNone
		v.ControllerManaged = true
	} else if v.CheckerWorkerID != "" && v.CheckerWorkerID != v.MakerWorkerID {
		v.ControllerManaged = true
		v.Rejected = false
		// Separated recorded checker only satisfies the actually observed grade.
		if v.ObservedEvidenceGrade == "" {
			v.ObservedEvidenceGrade = contract.EvidenceGradeSeparated
		}
		if v.EvidenceGrade == "" {
			v.EvidenceGrade = v.ObservedEvidenceGrade
		}
		if v.EvidenceGrade == contract.EvidenceGradeIndependent && v.ObservedEvidenceGrade != contract.EvidenceGradeIndependent {
			v.Rejected = true
			v.RejectedReason = "claimed_independent_exceeds_observed"
			v.EvidenceGrade = v.ObservedEvidenceGrade
		}
	} else if !v.ControllerManaged {
		v.Rejected = true
		v.RejectedReason = "verification_requires_controller_managed_boundary"
		v.EvidenceGrade = contract.EvidenceGradeNone
		if v.ObservedEvidenceGrade == "" {
			v.ObservedEvidenceGrade = contract.EvidenceGradeNone
		}
	}
	if e := v.Validate(); e != nil {
		return v, e
	}
	db, e := s.ensureViviStore()
	if e != nil {
		return v, e
	}
	defer db.Close()
	if e = db.PutViviVerification(v); e != nil {
		return v, e
	}
	return v, nil
}

// RefuseViviBoundary returns the applicable authority/greenfield boundary (R05).
// Method composition cannot evade the declared boundary.
func (s *Service) RefuseViviBoundary(sessionID, task string, composition []string) (contract.ViviBoundaryRefusal, error) {
	boundary, ok := contract.ClassifyTaskBoundary(task)
	if !ok {
		return contract.ViviBoundaryRefusal{}, errors.New("task does not exceed declared vivi boundaries")
	}
	b := contract.ViviBoundaryRefusal{
		SchemaVersion:        contract.ViviSchemaVersion,
		ID:                   "bound-" + digest8(sessionID+"|"+boundary+"|"+task),
		SessionID:            sessionID,
		Boundary:             boundary,
		TaskDescription:      task,
		MethodComposition:    append([]string(nil), composition...),
		EvadedViaComposition: false,
		Refused:              true,
		RecordedAt:           s.nowRFC3339(),
	}
	// Composition attempt is recorded but never flips Refused/Evaded.
	if len(composition) > 0 {
		// Explicitly refuse evasion: composition is informational only.
		b.EvadedViaComposition = false
		b.Refused = true
	}
	if e := b.Validate(); e != nil {
		return b, e
	}
	db, e := s.ensureViviStore()
	if e != nil {
		return b, e
	}
	defer db.Close()
	if _, e = db.GetViviSession(sessionID); e != nil {
		return b, e
	}
	if e = db.PutViviBoundary(b); e != nil {
		return b, e
	}
	return b, nil
}

// SelectViviContextStrategy records strategy version and observed transition (R06).
func (s *Service) SelectViviContextStrategy(c contract.ViviContextStrategyRecord) (contract.ViviContextStrategyRecord, error) {
	c.SchemaVersion = contract.ViviSchemaVersion
	if c.RecordedAt == "" {
		c.RecordedAt = s.nowRFC3339()
	}
	if c.StrategyVersion == "" {
		c.StrategyVersion = contract.ViviModesContractID + "/" + c.Strategy
	}
	// Unsupported host compaction is unknown, not claimed completed.
	if c.Strategy == contract.ContextStrategyNativeCompaction && c.HostCompactionSupport == "unsupported" {
		c.TransitionBoundary = contract.ContextTransitionUnknown
		c.ClaimedCompleted = false
	}
	if e := c.Validate(); e != nil {
		return c, e
	}
	db, e := s.ensureViviStore()
	if e != nil {
		return c, e
	}
	defer db.Close()
	if _, e = db.GetViviSession(c.SessionID); e != nil {
		return c, e
	}
	if e = db.PutViviContextStrategy(c); e != nil {
		return c, e
	}
	return db.GetViviContextStrategy(c.ID)
}

func digest8(s string) string {
	sum := sha256.Sum256([]byte(s))
	return hex.EncodeToString(sum[:8])
}
