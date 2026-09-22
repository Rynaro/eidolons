package controller

import (
	"errors"
	"os"
	"path/filepath"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
	"github.com/Rynaro/eidolons/gauge/internal/store"
)

func (s *Service) ensureRamzaStore() (*store.Store, error) {
	db, e := s.preferencesStore()
	if e != nil {
		return nil, e
	}
	if e = db.EnsureRamzaNamespaces(); e != nil {
		_ = db.Close()
		return nil, e
	}
	return db, nil
}

// EnsureRamzaNamespaces adds typed RAMZA method-contract buckets under schema 2.
func (s *Service) EnsureRamzaNamespaces() error {
	db, e := s.ensureRamzaStore()
	if e != nil {
		return e
	}
	return db.Close()
}

func ramzaCheckoutPresent() bool {
	// Sibling checkout locations used in local multi-repo layouts. Absence is
	// expected in CI/fixture scope — producer artifacts are then simulated.
	candidates := []string{
		filepath.Join("..", "Ramza"),
		filepath.Join("..", "..", "Ramza"),
		"/Users/henrique/workspace/oss/agents/Ramza",
		"/Users/henrique/workspace/oss/Ramza",
	}
	for _, c := range candidates {
		if st, e := os.Stat(c); e == nil && st.IsDir() {
			return true
		}
	}
	return false
}

func applyProducerArtifact(p *contract.RamzaLitePlan) {
	if p.ProducerArtifactSource != "" && p.ProducerArtifactRef != "" {
		return
	}
	if ramzaCheckoutPresent() {
		p.ProducerArtifactSource = contract.ProducerSourceSibling
		if p.ProducerArtifactRef == "" {
			p.ProducerArtifactRef = "sibling://Rynaro/Ramza/" + p.MethodVersion + "/" + p.ID
		}
		return
	}
	src, ref := contract.SimulateProducerArtifact(p.ID)
	p.ProducerArtifactSource = src
	p.ProducerArtifactRef = ref
}

func normalizeLitePlanDefaults(p *contract.RamzaLitePlan) {
	p.SchemaVersion = contract.RamzaSchemaVersion
	p.ContractVersion = contract.RamzaMethodContractID
	p.Mode = contract.RamzaModeLite
	if p.MethodVersion == "" {
		p.MethodVersion = contract.RamzaMethodLiteV2
	}
	if p.SourceOwner == "" {
		p.SourceOwner = contract.RamzaCanonicalSourceOwner
	}
	p.CanonicalSiblingPreserved = true
	p.IndependentPlannerClaim = false
	p.IndependentCritiqueClaim = false
	p.DefaultFlip = false
	p.FileCountSetsRisk = false
	if p.InventedAlternatives == nil {
		p.InventedAlternatives = []string{}
	}
	if !p.EmbeddedInMaker {
		p.EmbeddedInMaker = true
	}
	applyProducerArtifact(p)
}

// PlanLite produces a minimal actionable lite contract without mandatory invented alternatives (R01).
func (s *Service) PlanLite(p contract.RamzaLitePlan) (contract.RamzaLitePlan, error) {
	normalizeLitePlanDefaults(&p)
	if p.RecordedAt == "" {
		p.RecordedAt = s.nowRFC3339()
	}
	// Clear conventional lite: drop any forced invented alternatives before validate.
	if len(p.InventedAlternatives) > 0 {
		return p, errors.New("clear conventional lite task must not invent mandatory alternatives")
	}
	if p.ForcedOptionCount != 0 {
		return p, errors.New("lite plan must not force an option count")
	}
	if e := p.Validate(); e != nil {
		return p, e
	}
	db, e := s.ensureRamzaStore()
	if e != nil {
		return p, e
	}
	defer db.Close()
	if e = db.PutRamzaPlan(p); e != nil {
		return p, e
	}
	return db.GetRamzaPlan(p.ID)
}

// MarkPlanReady refuses readiness while behavior/authority decisions remain unresolved (R02).
// File count never sets risk.
func (s *Service) MarkPlanReady(planID string) (contract.RamzaLitePlan, error) {
	db, e := s.ensureRamzaStore()
	if e != nil {
		return contract.RamzaLitePlan{}, e
	}
	defer db.Close()
	p, e := db.GetRamzaPlan(planID)
	if e != nil {
		return p, e
	}
	if p.FileCountSetsRisk {
		return p, errors.New("file count must not set risk")
	}
	for _, d := range p.UnresolvedDecisions {
		if d.AffectsBehavior || d.AffectsAuthority || d.BlocksReady {
			return p, errors.New("unresolved behavior/authority decision blocks ready-for-implementation")
		}
	}
	for _, a := range p.Assumptions {
		if a.AffectsAcceptance && a.Status == contract.AssumptionUnresolved {
			return p, errors.New("acceptance-affecting unresolved assumption blocks ready")
		}
	}
	p.ReadyForImplementation = true
	p.RecordedAt = s.nowRFC3339()
	if e := p.Validate(); e != nil {
		return p, e
	}
	if e := db.UpdateRamzaPlan(p); e != nil {
		return p, e
	}
	return db.GetRamzaPlan(planID)
}

// ConsumeSettledDecision carries producer decisions into the maker without duplicate search (R03).
// Changed evidence reopens only the relevant choice.
func (s *Service) ConsumeSettledDecision(req contract.ConsumeDecisionRequest) (contract.ConsumeDecisionResult, error) {
	req.SchemaVersion = contract.RamzaSchemaVersion
	if e := req.Validate(); e != nil {
		return contract.ConsumeDecisionResult{}, e
	}
	db, e := s.ensureRamzaStore()
	if e != nil {
		return contract.ConsumeDecisionResult{}, e
	}
	defer db.Close()
	p, e := db.GetRamzaPlan(req.PlanID)
	if e != nil {
		return contract.ConsumeDecisionResult{}, e
	}
	var found *contract.SettledDecision
	idx := -1
	for i := range p.SettledDecisions {
		if p.SettledDecisions[i].ID == req.DecisionID {
			found = &p.SettledDecisions[i]
			idx = i
			break
		}
	}
	if found == nil {
		return contract.ConsumeDecisionResult{}, errors.New("settled decision not found on plan")
	}
	out := contract.ConsumeDecisionResult{
		SchemaVersion:         contract.RamzaSchemaVersion,
		PlanID:                p.ID,
		Decision:              *found,
		ConsumerCarryComplete: true,
	}
	if req.ChangedEvidence {
		matched := false
		for _, cond := range found.InvalidationConditions {
			if cond == req.ChangedCondition {
				matched = true
				break
			}
		}
		if !matched {
			return out, errors.New("changed evidence condition does not match decision invalidation set")
		}
		found.Reopened = true
		found.ReopenReason = req.ChangedCondition
		found.DuplicateSearchRequired = true
		found.EvidenceFingerprint = req.CurrentEvidenceFP
		p.SettledDecisions[idx] = *found
		out.Decision = *found
		out.DuplicateSearchRequired = true
		out.ReopenedOnlyRelevant = true
	} else {
		if found.EvidenceFingerprint != req.CurrentEvidenceFP && found.EvidenceFingerprint != "" {
			// Fingerprint drift without an explicit invalidation condition stays carried;
			// only named conditions reopen. Consumer still avoids duplicate search.
		}
		found.Reopened = false
		found.DuplicateSearchRequired = false
		p.SettledDecisions[idx] = *found
		out.Decision = *found
		out.DuplicateSearchRequired = false
		out.ReopenedOnlyRelevant = false
	}
	p.ConsumerCarryComplete = true
	p.RecordedAt = s.nowRFC3339()
	if e := p.Validate(); e != nil {
		return out, e
	}
	if e := out.Validate(); e != nil {
		return out, e
	}
	if e := db.UpdateRamzaPlan(p); e != nil {
		return out, e
	}
	receiptID := p.ID + "/" + found.ID
	if e := db.PutRamzaConsumeReceipt(receiptID, out); e != nil {
		return out, e
	}
	return out, nil
}

// PresentRubricScore labels uncalibrated scores as heuristics (R04).
func (s *Service) PresentRubricScore(planID string, score contract.RubricScore) (contract.RubricScore, error) {
	score.SchemaVersion = contract.RamzaSchemaVersion
	if score.IsProbability || score.ProbabilityPercent != nil {
		return score, errors.New("rubric scores must never be presented as probabilities")
	}
	if score.IndependentVerification {
		return score, errors.New("uncalibrated rubric score is not independent verification")
	}
	if !score.Calibrated {
		score.Label = contract.RubricLabelHeuristic
	}
	if e := score.Validate(); e != nil {
		return score, e
	}
	if planID == "" {
		return score, nil
	}
	db, e := s.ensureRamzaStore()
	if e != nil {
		return score, e
	}
	defer db.Close()
	p, e := db.GetRamzaPlan(planID)
	if e != nil {
		return score, e
	}
	replaced := false
	for i := range p.RubricScores {
		if p.RubricScores[i].ID == score.ID {
			p.RubricScores[i] = score
			replaced = true
			break
		}
	}
	if !replaced {
		p.RubricScores = append(p.RubricScores, score)
	}
	p.RecordedAt = s.nowRFC3339()
	if e := p.Validate(); e != nil {
		return score, e
	}
	if e := db.UpdateRamzaPlan(p); e != nil {
		return score, e
	}
	return score, nil
}

// SelectProfilePackage preserves declared controls for legacy/full; lite uses versioned amendment (R05).
func (s *Service) SelectProfilePackage(p contract.ProfilePackage) (contract.ProfilePackage, error) {
	p.SchemaVersion = contract.RamzaSchemaVersion
	if p.RecordedAt == "" {
		p.RecordedAt = s.nowRFC3339()
	}
	if p.CharterChanged {
		p.AmendmentRequired = true
		if p.AmendmentVersion == "" {
			return p, errors.New("changed charter requires a versioned amendment")
		}
	}
	switch p.Mode {
	case contract.RamzaModeFull:
		if p.MethodVersion == "" {
			p.MethodVersion = contract.RamzaMethodFullV1
		}
		p.StandaloneCompatible = true
		p.CompatibleWithPrior = true
	case contract.RamzaModeLegacy:
		if p.MethodVersion == "" {
			p.MethodVersion = contract.RamzaMethodLegacyV1
		}
		p.StandaloneCompatible = true
		p.CompatibleWithPrior = true
	case contract.RamzaModeLite:
		if p.MethodVersion == "" {
			p.MethodVersion = contract.RamzaMethodLiteV2
		}
		p.StandaloneCompatible = true
		if p.PriorVersion != "" && p.PriorVersion != contract.RamzaMethodLiteV2 && !p.AmendmentRequired {
			// Prior lite charter change requires explicit amendment versioning.
			if p.CharterChanged {
				p.AmendmentRequired = true
			}
		}
		p.CompatibleWithPrior = !p.CharterChanged || p.AmendmentRequired
	default:
		return p, errors.New("unknown ramza profile mode")
	}
	if e := p.Validate(); e != nil {
		return p, e
	}
	db, e := s.ensureRamzaStore()
	if e != nil {
		return p, e
	}
	defer db.Close()
	if e = db.PutRamzaProfile(p); e != nil {
		return p, e
	}
	return db.GetRamzaProfile(p.ID)
}

// PublishHeuristic records activation conditions, scope, and retirement; queues reevaluation on harness change (R06).
func (s *Service) PublishHeuristic(h contract.HeuristicPublication) (contract.HeuristicPublication, error) {
	h.SchemaVersion = contract.RamzaSchemaVersion
	if h.RecordedAt == "" {
		h.RecordedAt = s.nowRFC3339()
	}
	h.UnqualifiedBenefitClaim = false
	if !h.TaskMatched {
		h.Activated = false
		if h.State == "" || h.State == contract.HeuristicStateActive {
			h.State = contract.HeuristicStateInactive
		}
	} else if h.State == "" {
		h.State = contract.HeuristicStateActive
		h.Activated = true
	}
	if h.ModelOrHarnessChanged {
		h.State = contract.HeuristicStateReevaluationQueued
		h.Activated = false
		if h.Detail == "" {
			h.Detail = "model/harness change queues reevaluation; no unqualified benefit claim"
		}
	}
	if e := h.Validate(); e != nil {
		return h, e
	}
	db, e := s.ensureRamzaStore()
	if e != nil {
		return h, e
	}
	defer db.Close()
	if e = db.PutRamzaHeuristic(h); e != nil {
		return h, e
	}
	return db.GetRamzaHeuristic(h.ID)
}

// RecordAssumption keeps unsupported assumptions unresolved rather than converting them (R07).
func (s *Service) RecordAssumption(planID string, a contract.PlanningAssumption) (contract.PlanningAssumption, error) {
	a.SchemaVersion = contract.RamzaSchemaVersion
	if a.RecordedAt == "" {
		a.RecordedAt = s.nowRFC3339()
	}
	if a.Status == "" {
		a.Status = contract.AssumptionUnresolved
	}
	if a.Status == contract.AssumptionUnresolved {
		a.ConvertedToRequirement = false
	}
	if e := a.Validate(); e != nil {
		return a, e
	}
	db, e := s.ensureRamzaStore()
	if e != nil {
		return a, e
	}
	defer db.Close()
	if e = db.PutRamzaAssumption(a); e != nil {
		return a, e
	}
	if planID != "" {
		p, e := db.GetRamzaPlan(planID)
		if e != nil {
			return a, e
		}
		replaced := false
		for i := range p.Assumptions {
			if p.Assumptions[i].ID == a.ID {
				p.Assumptions[i] = a
				replaced = true
				break
			}
		}
		if !replaced {
			p.Assumptions = append(p.Assumptions, a)
		}
		// Ready plans cannot retain acceptance-affecting unresolved assumptions.
		if p.ReadyForImplementation && a.AffectsAcceptance && a.Status == contract.AssumptionUnresolved {
			p.ReadyForImplementation = false
		}
		p.RecordedAt = s.nowRFC3339()
		if e := p.Validate(); e != nil {
			return a, e
		}
		if e := db.UpdateRamzaPlan(p); e != nil {
			return a, e
		}
	}
	return a, nil
}

// ShowRamzaPlan returns a persisted lite plan.
func (s *Service) ShowRamzaPlan(id string) (contract.RamzaLitePlan, error) {
	db, e := s.ensureRamzaStore()
	if e != nil {
		return contract.RamzaLitePlan{}, e
	}
	defer db.Close()
	return db.GetRamzaPlan(id)
}

// AttachUnresolvedDecision adds a blocking decision before readiness (test/helper surface).
func (s *Service) AttachUnresolvedDecision(planID string, d contract.UnresolvedDecision) (contract.RamzaLitePlan, error) {
	if e := d.Validate(); e != nil {
		return contract.RamzaLitePlan{}, e
	}
	db, e := s.ensureRamzaStore()
	if e != nil {
		return contract.RamzaLitePlan{}, e
	}
	defer db.Close()
	p, e := db.GetRamzaPlan(planID)
	if e != nil {
		return p, e
	}
	p.UnresolvedDecisions = append(p.UnresolvedDecisions, d)
	p.ReadyForImplementation = false
	p.RecordedAt = s.nowRFC3339()
	if e := p.Validate(); e != nil {
		return p, e
	}
	if e := db.UpdateRamzaPlan(p); e != nil {
		return p, e
	}
	return db.GetRamzaPlan(planID)
}

// AttachSettledDecision records a producer decision for consumer carry (test/helper surface).
func (s *Service) AttachSettledDecision(planID string, d contract.SettledDecision) (contract.RamzaLitePlan, error) {
	d.DuplicateSearchRequired = false
	d.Reopened = false
	if e := d.Validate(); e != nil {
		return contract.RamzaLitePlan{}, e
	}
	db, e := s.ensureRamzaStore()
	if e != nil {
		return contract.RamzaLitePlan{}, e
	}
	defer db.Close()
	p, e := db.GetRamzaPlan(planID)
	if e != nil {
		return p, e
	}
	p.SettledDecisions = append(p.SettledDecisions, d)
	p.RecordedAt = s.nowRFC3339()
	if e := p.Validate(); e != nil {
		return p, e
	}
	if e := db.UpdateRamzaPlan(p); e != nil {
		return p, e
	}
	return db.GetRamzaPlan(planID)
}

// ResolveUnresolved clears a decision once the information is supplied (test helper).
func (s *Service) ResolveUnresolved(planID, decisionID string) (contract.RamzaLitePlan, error) {
	db, e := s.ensureRamzaStore()
	if e != nil {
		return contract.RamzaLitePlan{}, e
	}
	defer db.Close()
	p, e := db.GetRamzaPlan(planID)
	if e != nil {
		return p, e
	}
	kept := p.UnresolvedDecisions[:0]
	for _, d := range p.UnresolvedDecisions {
		if d.ID == decisionID {
			continue
		}
		kept = append(kept, d)
	}
	p.UnresolvedDecisions = kept
	p.RecordedAt = s.nowRFC3339()
	if e := p.Validate(); e != nil {
		return p, e
	}
	if e := db.UpdateRamzaPlan(p); e != nil {
		return p, e
	}
	return db.GetRamzaPlan(planID)
}
