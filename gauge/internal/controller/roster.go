package controller

import (
	"errors"
	"fmt"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
	"github.com/Rynaro/eidolons/gauge/internal/store"
)

func (s *Service) ensureRosterStore() (*store.Store, error) {
	db, e := s.preferencesStore()
	if e != nil {
		return nil, e
	}
	if e = db.EnsureRosterNamespaces(); e != nil {
		_ = db.Close()
		return nil, e
	}
	return db, nil
}

// EnsureRosterNamespaces adds typed roster-adoption buckets under schema 2.
func (s *Service) EnsureRosterNamespaces() error {
	db, e := s.ensureRosterStore()
	if e != nil {
		return e
	}
	return db.Close()
}

func rosterCeiling(id, desc string) contract.SpecialistCeiling {
	return contract.SpecialistCeiling{ID: id, Description: desc, RefusalWeakened: false}
}

func fixtureProfile(id, display, purpose, charter string, aliases []string, forms, inputs []string, out, producer, consumer string, reuseRAMZA, reuseVivi bool) contract.SpecialistProfile {
	method := id + "-method"
	if id == "nexus-adoption" {
		method = "nexus-adoption-method"
	}
	if id == "APIVR-Delta" {
		method = "apivr-delta-method"
	}
	return contract.SpecialistProfile{
		SchemaVersion: contract.RosterSchemaVersion,
		ID:            id,
		DisplayName:   display,
		Aliases:       aliases,
		Purpose:       purpose,
		CharterDigest: charter,
		Ceilings: []contract.SpecialistCeiling{
			rosterCeiling(id+"-ceiling-scope", "preserve declared purpose and refusal boundary"),
			rosterCeiling(id+"-ceiling-auth", "no silent authority widening via adoption"),
		},
		ActivationConditions: []string{
			"task_requires_" + id + "_expertise",
			"fixture_profile_registry",
		},
		Contract:        contract.FixtureSkill(method, producer, forms, inputs, out),
		ProducerVersion: producer,
		ConsumerVersion: consumer,
		ReuseRAMZALite:  reuseRAMZA,
		ReuseViviModes:  reuseVivi,
		GlobalRename:    false,
		OptOutLegacy:    true,
		LiveBlocked:     true,
		RecordedAt:      "2026-09-22T22:00:00Z",
	}
}

// FixtureAdoptionProfiles returns all declared required V4-18 slices.
func FixtureAdoptionProfiles() []contract.SpecialistProfile {
	return []contract.SpecialistProfile{
		fixtureProfile("ATLAS", "ATLAS", "Read-only codebase intelligence and bounded probes",
			"charter-atlas-v1", nil,
			[]string{contract.FormEmbedded, contract.FormConsultant},
			[]string{"scope", "path"}, "atlas-localize.v1",
			"atlas-method@1.0.0", "gauge-roster-adoption@1", false, false),
		fixtureProfile("FORGE", "FORGE", "Implementation and change authorship within charter",
			"charter-forge-v1", []string{"scribe"},
			[]string{contract.FormEmbedded, contract.FormIsolatedWriter, contract.FormConsultant},
			[]string{"brief", "workspace"}, "forge-change.v1",
			"forge-method@1.0.0", "gauge-roster-adoption@1", false, false),
		fixtureProfile("VIGIL", "VIGIL", "Security and risk consultation",
			"charter-vigil-v1", nil,
			[]string{contract.FormConsultant, contract.FormEmbedded},
			[]string{"threat_model"}, "vigil-review.v1",
			"vigil-method@1.0.0", "gauge-roster-adoption@1", false, false),
		fixtureProfile("IDG", "IDG", "Interface and documentation guidance",
			"charter-idg-v1", nil,
			[]string{contract.FormEmbedded, contract.FormConsultant},
			[]string{"surface"}, "idg-doc.v1",
			"idg-method@1.0.0", "gauge-roster-adoption@1", false, false),
		fixtureProfile("Kupo", "Kupo", "Errands and trivial mechanical work",
			"charter-kupo-v1", nil,
			[]string{contract.FormEmbedded},
			[]string{"errand"}, "kupo-errand.v1",
			"kupo-method@1.0.0", "gauge-roster-adoption@1", false, false),
		fixtureProfile("Gilgamesh", "Gilgamesh", "Long-horizon research and dossier work",
			"charter-gilgamesh-v1", nil,
			[]string{contract.FormConsultant, contract.FormEmbedded},
			[]string{"question"}, "gilgamesh-dossier.v1",
			"gilgamesh-method@1.0.0", "gauge-roster-adoption@1", false, false),
		fixtureProfile("SPECTRA", "SPECTRA", "Spec lifecycle and change grammar",
			"charter-spectra-v1", nil,
			[]string{contract.FormEmbedded, contract.FormConsultant},
			[]string{"change_id"}, "spectra-spec.v1",
			"spectra-method@1.0.0", "gauge-roster-adoption@1", false, false),
		fixtureProfile("APIVR-Delta", "APIVR-Δ", "Verification and protected acceptance",
			"charter-apivr-v1", []string{"apivr"},
			[]string{contract.FormVerification, contract.FormConsultant},
			[]string{"candidate", "criteria"}, "apivr-verify.v1",
			"apivr-method@1.0.0", "gauge-roster-adoption@1", false, false),
		fixtureProfile("nexus-adoption", "nexus-adoption", "Nexus-level need-based adoption orchestration",
			"charter-nexus-adoption-v1", nil,
			[]string{contract.FormEmbedded, contract.FormConsultant},
			[]string{"roster_slice"}, "nexus-adoption.v1",
			"nexus-adoption@1.0.0", "gauge-roster-adoption@1", true, true),
	}
}

// SeedAdoptionProfiles registers all required slices and the registry receipt.
func (s *Service) SeedAdoptionProfiles() (contract.RosterAdoptionRegistry, error) {
	db, e := s.ensureRosterStore()
	if e != nil {
		return contract.RosterAdoptionRegistry{}, e
	}
	defer db.Close()

	at := s.nowRFC3339()
	var ids []string
	for _, p := range FixtureAdoptionProfiles() {
		p.RecordedAt = at
		if e := p.Validate(); e != nil {
			return contract.RosterAdoptionRegistry{}, e
		}
		if e := db.PutRosterProfile(p); e != nil {
			return contract.RosterAdoptionRegistry{}, e
		}
		ids = append(ids, p.ID)
	}
	reg := contract.RosterAdoptionRegistry{
		SchemaVersion:   contract.RosterSchemaVersion,
		ID:              "registry-v4-18",
		ContractVersion: contract.RosterAdoptionContractID,
		ProfileIDs:      ids,
		RequiredCovered: true,
		LiveBlocked:     true,
		RecordedAt:      at,
	}
	if e := db.PutRosterRegistry(reg); e != nil {
		return reg, e
	}
	return db.GetRosterRegistry(reg.ID)
}

// RouteAdoption decides embedded vs separated specialist execution (R01–R03).
func (s *Service) RouteAdoption(req contract.RosterRouteRequest) (contract.RosterRouteAssignment, error) {
	req.SchemaVersion = contract.RosterSchemaVersion
	if req.RecordedAt == "" {
		req.RecordedAt = s.nowRFC3339()
	}
	if e := req.Validate(); e != nil {
		return contract.RosterRouteAssignment{}, e
	}

	db, e := s.ensureRosterStore()
	if e != nil {
		return contract.RosterRouteAssignment{}, e
	}
	defer db.Close()

	profile, e := db.GetRosterProfile(req.ProfileID)
	if e != nil {
		return contract.RosterRouteAssignment{}, e
	}

	asgn := contract.RosterRouteAssignment{
		SchemaVersion:         contract.RosterSchemaVersion,
		ID:                    "asgn-" + req.ID,
		RequestID:             req.ID,
		ProfileID:             req.ProfileID,
		DeliverablesPreserved: len(req.Deliverables) > 0 || req.RequiresExpertise,
		RecordedAt:            req.RecordedAt,
		UnnecessaryWorkers:    0,
		EmbeddedSubstituted:   false,
	}

	// R02: explicit specialist / independent review must preserve separation.
	if req.ExplicitRequestKind != "" {
		form := contract.FormConsultant
		boundary := contract.AdoptBoundaryExplicitUser
		switch req.ExplicitRequestKind {
		case contract.RequestSeparateATLASInspect:
			form = contract.FormConsultant
			boundary = contract.BoundaryIndependentConsult
		case contract.RequestIndependentCritique:
			form = contract.FormConsultant
			boundary = contract.BoundaryIndependentConsult
		case contract.RequestReadOnlyIntent:
			form = contract.FormConsultant
			boundary = contract.BoundaryContextSeparation
		case contract.RequestRequiredDocumentation:
			form = contract.FormConsultant
			boundary = contract.AdoptBoundaryExplicitUser
		case contract.RequestNamedLegacySpecialist:
			form = contract.FormConsultant
			boundary = contract.AdoptBoundaryExplicitUser
		}
		if req.PreferredForm != "" {
			form = req.PreferredForm
		}
		asgn.ExecutionForm = form
		asgn.ReportClass = contract.ReportSpecialistInvocation
		asgn.ContinuingMaker = false
		asgn.SeparatedWorker = true
		asgn.BoundaryReason = boundary
		asgn.BoundaryReasonRecorded = true
		asgn.Selection = contract.SelectionReason{
			RuleID: "V4-18-R02", Kind: "explicit_user_request",
			Detail: "preserve separate specialist/independent execution; embedded must not substitute",
			Profile: profile.ID,
		}
		if e := asgn.Validate(); e != nil {
			return asgn, e
		}
		if e := db.PutRosterAssignment(asgn); e != nil {
			return asgn, e
		}
		return db.GetRosterAssignment(asgn.ID)
	}

	// R03: distinct context / permission / independent track must record reason.
	if req.SeparateBoundaryNeeded {
		boundary := req.BoundaryReason
		if boundary == "" {
			return asgn, errors.New("separate boundary requires recorded reason")
		}
		form := req.PreferredForm
		if form == "" {
			switch boundary {
			case contract.AdoptBoundaryIsolatedWriter:
				form = contract.FormIsolatedWriter
			case contract.AdoptBoundaryChecker:
				form = contract.FormVerification
			default:
				form = contract.FormConsultant
			}
		}
		asgn.ExecutionForm = form
		asgn.ReportClass = contract.ReportSpecialistInvocation
		asgn.ContinuingMaker = false
		asgn.SeparatedWorker = true
		asgn.BoundaryReason = boundary
		asgn.BoundaryReasonRecorded = true
		asgn.Selection = contract.SelectionReason{
			RuleID: "V4-18-R03", Kind: "execution_boundary",
			Detail: "recorded boundary: " + boundary,
			Profile: profile.ID,
		}
		if e := asgn.Validate(); e != nil {
			return asgn, e
		}
		if e := db.PutRosterAssignment(asgn); e != nil {
			return asgn, e
		}
		return db.GetRosterAssignment(asgn.ID)
	}

	// R01: expertise without separate boundary → embedded method.
	if req.RequiresExpertise && !req.SeparateBoundaryNeeded {
		asgn.ExecutionForm = contract.FormEmbedded
		asgn.ReportClass = contract.ReportMethodUse
		asgn.ContinuingMaker = true
		asgn.SeparatedWorker = false
		asgn.UnnecessaryWorkers = 0
		asgn.Selection = contract.SelectionReason{
			RuleID: "V4-18-R01", Kind: "embedded_method",
			Detail: fmt.Sprintf("embedded %s method; not a mandatory specialist worker", profile.DisplayName),
			Profile: profile.ID,
		}
		if e := asgn.Validate(); e != nil {
			return asgn, e
		}
		if e := db.PutRosterAssignment(asgn); e != nil {
			return asgn, e
		}
		return db.GetRosterAssignment(asgn.ID)
	}

	return asgn, errors.New("route request does not match R01/R02/R03 activation")
}

// ReviseMethodologyControl records rule/heuristic/rationale classification (R04).
func (s *Service) ReviseMethodologyControl(c contract.MethodologyControlRevision) (contract.MethodologyControlRevision, error) {
	c.SchemaVersion = contract.RosterSchemaVersion
	if c.RecordedAt == "" {
		c.RecordedAt = s.nowRFC3339()
	}
	if c.Classification == contract.ControlClassHeuristic && c.ControlName == "option_count" {
		c.OptionCountIsHeuristic = true
	}
	// RationaleCertified must remain false — Validate rejects false certification (R04).
	if e := c.Validate(); e != nil {
		return c, e
	}
	db, e := s.ensureRosterStore()
	if e != nil {
		return c, e
	}
	defer db.Close()
	if _, e = db.GetRosterProfile(c.ProfileID); e != nil {
		return c, e
	}
	if e = db.PutRosterControl(c); e != nil {
		return c, e
	}
	return c, nil
}

// CheckProfileCompatibility validates exact producer/consumer versions (R05).
func (s *Service) CheckProfileCompatibility(c contract.ProfileCompatibilityCheck) (contract.ProfileCompatibilityCheck, error) {
	c.SchemaVersion = contract.RosterSchemaVersion
	if c.RecordedAt == "" {
		c.RecordedAt = s.nowRFC3339()
	}
	db, e := s.ensureRosterStore()
	if e != nil {
		return c, e
	}
	defer db.Close()
	profile, e := db.GetRosterProfile(c.ProfileID)
	if e != nil {
		return c, e
	}
	if c.ExpectedProducer == "" {
		c.ExpectedProducer = profile.ProducerVersion
	}
	if c.ExpectedConsumer == "" {
		c.ExpectedConsumer = profile.ConsumerVersion
	}

	var reasons []string
	if c.InventedTags {
		reasons = append(reasons, "invented_tags")
	}
	if c.ChangedPerformatives {
		reasons = append(reasons, "changed_performatives")
	}
	if c.MandatoryExternalAgent {
		reasons = append(reasons, "mandatory_external_agent_import")
	}
	if c.ProducerVersion != c.ExpectedProducer {
		reasons = append(reasons, "producer_version_mismatch")
	}
	if c.ConsumerVersion != c.ExpectedConsumer {
		reasons = append(reasons, "consumer_version_mismatch")
	}
	if !c.DiscoveryParity {
		reasons = append(reasons, "discovery_parity_failed")
	}
	if len(reasons) > 0 {
		c.Compatible = false
		c.RejectReasons = reasons
	} else {
		c.Compatible = true
		c.RejectReasons = nil
	}
	if e := c.Validate(); e != nil {
		return c, e
	}
	if e = db.PutRosterCompat(c); e != nil {
		return c, e
	}
	return c, nil
}

// CheckIsolationContract enforces bounded I/O for advertised isolation (R06).
func (s *Service) CheckIsolationContract(c contract.IsolationContractCheck) (contract.IsolationContractCheck, error) {
	c.SchemaVersion = contract.RosterSchemaVersion
	if c.RecordedAt == "" {
		c.RecordedAt = s.nowRFC3339()
	}
	db, e := s.ensureRosterStore()
	if e != nil {
		return c, e
	}
	defer db.Close()
	if _, e = db.GetRosterProfile(c.ProfileID); e != nil {
		return c, e
	}

	var reasons []string
	if e := c.Contract.Validate(); e != nil {
		reasons = append(reasons, e.Error())
	}
	if c.AdvertisedIsolated {
		formOK := false
		for _, f := range c.Contract.AllowedForms {
			if f == c.ExecutionForm {
				formOK = true
				break
			}
			if f == contract.FormConsultant || f == contract.FormIsolatedWriter || f == contract.FormVerification {
				// contract allows some isolation form
			}
		}
		isolAllowed := false
		for _, f := range c.Contract.AllowedForms {
			if f == contract.FormConsultant || f == contract.FormIsolatedWriter || f == contract.FormVerification {
				isolAllowed = true
				break
			}
		}
		if c.InlineOnlySkill || !isolAllowed {
			reasons = append(reasons, "inline_only_skill_rejects_isolation")
		}
		if !formOK {
			reasons = append(reasons, "forbidden_execution_form:"+c.ExecutionForm)
		}
		have := map[string]bool{}
		for _, in := range c.ProvidedInputs {
			have[in] = true
		}
		for _, need := range c.Contract.RequiredInputs {
			if !have[need] {
				reasons = append(reasons, "missing_input:"+need)
			}
		}
		if c.Contract.MaxOutputBytes > 0 && c.ResultBytes > c.Contract.MaxOutputBytes {
			reasons = append(reasons, "oversized_result")
		}
	}
	if len(reasons) > 0 {
		c.Accepted = false
		c.RejectReasons = reasons
	} else {
		c.Accepted = true
		c.RejectReasons = nil
	}
	if e := c.Validate(); e != nil {
		return c, e
	}
	if e = db.PutRosterIsolation(c); e != nil {
		return c, e
	}
	return c, nil
}

// LabelBenefitEvidence labels unproven performance benefits (R07).
func (s *Service) LabelBenefitEvidence(b contract.BenefitEvidenceLabel) (contract.BenefitEvidenceLabel, error) {
	b.SchemaVersion = contract.RosterSchemaVersion
	if b.RecordedAt == "" {
		b.RecordedAt = s.nowRFC3339()
	}
	db, e := s.ensureRosterStore()
	if e != nil {
		return b, e
	}
	defer db.Close()
	if _, e = db.GetRosterProfile(b.ProfileID); e != nil {
		return b, e
	}

	switch b.EvidenceClass {
	case contract.BenefitUntested, contract.BenefitNoWin, contract.BenefitInconclusive:
		b.QualifyingComparative = false
		b.AdvertisedAsMeasured = false
		b.PerformanceGainClaimed = false
		if b.Label == "" || b.Label == contract.BenefitMeasured {
			if b.EvidenceClass == contract.BenefitInconclusive {
				b.Label = contract.BenefitExperimental
			} else if b.EvidenceClass == contract.BenefitNoWin {
				b.Label = contract.BenefitMaintenance
			} else {
				b.Label = contract.BenefitUnproven
			}
		}
	case contract.BenefitExperimental, contract.BenefitMaintenance, contract.BenefitUnproven:
		b.QualifyingComparative = false
		b.AdvertisedAsMeasured = false
		b.PerformanceGainClaimed = false
		b.Label = b.EvidenceClass
	case contract.BenefitMeasured:
		if b.V421EvidenceRef == "" {
			return b, errors.New("measured benefit requires V4-21 evidence reference")
		}
		b.QualifyingComparative = true
		b.Label = contract.BenefitMeasured
	}

	if e := b.Validate(); e != nil {
		return b, e
	}
	if e = db.PutRosterBenefit(b); e != nil {
		return b, e
	}
	return b, nil
}

// GetRosterProfile returns a persisted profile.
func (s *Service) GetRosterProfile(id string) (contract.SpecialistProfile, error) {
	db, e := s.ensureRosterStore()
	if e != nil {
		return contract.SpecialistProfile{}, e
	}
	defer db.Close()
	return db.GetRosterProfile(id)
}

// GetRosterRegistry returns the adoption registry receipt.
func (s *Service) GetRosterRegistry(id string) (contract.RosterAdoptionRegistry, error) {
	db, e := s.ensureRosterStore()
	if e != nil {
		return contract.RosterAdoptionRegistry{}, e
	}
	defer db.Close()
	return db.GetRosterRegistry(id)
}
