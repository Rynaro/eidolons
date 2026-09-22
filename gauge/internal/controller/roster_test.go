package controller

import (
	"strings"
	"testing"
	"time"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
)

func rosterService(t *testing.T) *Service {
	t.Helper()
	s := New(t.TempDir(), Options{Timeout: time.Second, Clock: func() time.Time {
		return time.Date(2026, 9, 22, 22, 0, 0, 0, time.UTC)
	}})
	if e := s.Init(); e != nil {
		t.Fatal(e)
	}
	if e := s.EnsureRosterNamespaces(); e != nil {
		t.Fatal(e)
	}
	if _, e := s.SeedAdoptionProfiles(); e != nil {
		t.Fatal(e)
	}
	return s
}

// TestV418T01 — clear fix / targeted discovery / lite planning may use embedded methods.
func TestV418T01(t *testing.T) {
	s := rosterService(t)
	reg, e := s.GetRosterRegistry("registry-v4-18")
	if e != nil || !reg.RequiredCovered {
		t.Fatalf("required slices: %+v %v", reg, e)
	}
	for _, need := range contract.RequiredAdoptionSlices {
		ok := false
		for _, id := range reg.ProfileIDs {
			if id == need {
				ok = true
				break
			}
		}
		if !ok {
			t.Fatalf("missing required slice %s", need)
		}
	}

	cases := []struct {
		id, kind, profile string
	}{
		{"route-t01-fix", contract.TaskClearFix, "Kupo"},
		{"route-t01-disc", contract.TaskTargetedDiscovery, "ATLAS"},
		{"route-t01-lite", contract.TaskLitePlanning, "nexus-adoption"},
	}
	for _, c := range cases {
		asgn, e := s.RouteAdoption(contract.RosterRouteRequest{
			SchemaVersion: contract.RosterSchemaVersion,
			ID: c.id, TaskKind: c.kind, ProfileID: c.profile,
			RequiresExpertise: true, SeparateBoundaryNeeded: false,
			Deliverables: []string{"patched-file", "green-tests"},
			RecordedAt:   "2026-09-22T22:01:00Z",
		})
		if e != nil {
			t.Fatal(e)
		}
		if !asgn.ContinuingMaker || asgn.SeparatedWorker || asgn.ExecutionForm != contract.FormEmbedded {
			t.Fatalf("%s: expected embedded continuing maker: %+v", c.id, asgn)
		}
		if asgn.ReportClass != contract.ReportMethodUse {
			t.Fatalf("%s: embedded must report method_use: %+v", c.id, asgn)
		}
		if asgn.UnnecessaryWorkers != 0 || !asgn.DeliverablesPreserved {
			t.Fatalf("%s: deliverables/workers: %+v", c.id, asgn)
		}
		if asgn.EmbeddedSubstituted {
			t.Fatalf("%s: must not claim substitution", c.id)
		}
	}

	// Preserve named expertise — ATLAS display/charter/ceiling intact (not global rename).
	atlas, e := s.GetRosterProfile("ATLAS")
	if e != nil {
		t.Fatal(e)
	}
	if atlas.DisplayName != "ATLAS" || atlas.GlobalRename || atlas.CharterDigest == "" || len(atlas.Ceilings) == 0 {
		t.Fatalf("ATLAS identity/charter/ceilings not preserved: %+v", atlas)
	}
	if atlas.Ceilings[0].RefusalWeakened {
		t.Fatal("refusal must not be weakened")
	}
}

// TestV418T02 — explicit specialist / independent review preserves separation.
func TestV418T02(t *testing.T) {
	s := rosterService(t)
	cases := []struct {
		id, profile, kind string
	}{
		{"route-t02-legacy", "FORGE", contract.RequestNamedLegacySpecialist},
		{"route-t02-atlas", "ATLAS", contract.RequestSeparateATLASInspect},
		{"route-t02-crit", "VIGIL", contract.RequestIndependentCritique},
		{"route-t02-docs", "IDG", contract.RequestRequiredDocumentation},
		{"route-t02-ro", "ATLAS", contract.RequestReadOnlyIntent},
	}
	for _, c := range cases {
		asgn, e := s.RouteAdoption(contract.RosterRouteRequest{
			SchemaVersion: contract.RosterSchemaVersion,
			ID: c.id, TaskKind: "explicit-user", ProfileID: c.profile,
			RequiresExpertise: true, ExplicitRequestKind: c.kind,
			Deliverables: []string{"independent-result"},
			RecordedAt:   "2026-09-22T22:02:00Z",
		})
		if e != nil {
			t.Fatal(e)
		}
		if asgn.ContinuingMaker || !asgn.SeparatedWorker {
			t.Fatalf("%s: must separate: %+v", c.id, asgn)
		}
		if asgn.ReportClass != contract.ReportSpecialistInvocation {
			t.Fatalf("%s: must be specialist invocation: %+v", c.id, asgn)
		}
		if !asgn.BoundaryReasonRecorded || asgn.BoundaryReason == "" {
			t.Fatalf("%s: boundary reason required: %+v", c.id, asgn)
		}
		if asgn.EmbeddedSubstituted {
			t.Fatalf("%s: embedded must not substitute for independent request", c.id)
		}
		if asgn.Selection.RuleID != "V4-18-R02" {
			t.Fatalf("%s: wrong rule: %+v", c.id, asgn.Selection)
		}
	}
}

// TestV418T03 — FORGE/VIGIL consult, isolated writer, checker record reasons; no unexplained fan-out.
func TestV418T03(t *testing.T) {
	s := rosterService(t)
	cases := []struct {
		id, profile, boundary, form string
	}{
		{"route-t03-forge", "FORGE", contract.AdoptBoundaryFORGEConsult, contract.FormConsultant},
		{"route-t03-vigil", "VIGIL", contract.AdoptBoundaryVIGILConsult, contract.FormConsultant},
		{"route-t03-iso", "FORGE", contract.AdoptBoundaryIsolatedWriter, contract.FormIsolatedWriter},
		{"route-t03-check", "APIVR-Delta", contract.AdoptBoundaryChecker, contract.FormVerification},
	}
	for _, c := range cases {
		asgn, e := s.RouteAdoption(contract.RosterRouteRequest{
			SchemaVersion: contract.RosterSchemaVersion,
			ID: c.id, TaskKind: "bounded-consult", ProfileID: c.profile,
			RequiresExpertise: true, SeparateBoundaryNeeded: true,
			BoundaryReason: c.boundary, PreferredForm: c.form,
			Deliverables: []string{"consult-result"},
			RecordedAt:   "2026-09-22T22:03:00Z",
		})
		if e != nil {
			t.Fatal(e)
		}
		if !asgn.SeparatedWorker || !asgn.BoundaryReasonRecorded || asgn.BoundaryReason != c.boundary {
			t.Fatalf("%s: unexplained fan-out: %+v", c.id, asgn)
		}
		if asgn.ExecutionForm != c.form {
			t.Fatalf("%s: form=%s want %s", c.id, asgn.ExecutionForm, c.form)
		}
		if asgn.Selection.RuleID != "V4-18-R03" {
			t.Fatalf("%s: wrong rule: %+v", c.id, asgn.Selection)
		}
	}

	// Missing reason rejects.
	if _, e := s.RouteAdoption(contract.RosterRouteRequest{
		SchemaVersion: contract.RosterSchemaVersion,
		ID: "route-t03-bad", TaskKind: "bounded-consult", ProfileID: "FORGE",
		RequiresExpertise: true, SeparateBoundaryNeeded: true,
		RecordedAt: "2026-09-22T22:03:30Z",
	}); e == nil {
		t.Fatal("separate boundary without reason must fail")
	}
}

// TestV418T04 — control diff retains protected tests; option counts are heuristics; rationale not certified.
func TestV418T04(t *testing.T) {
	s := rosterService(t)

	rule, e := s.ReviseMethodologyControl(contract.MethodologyControlRevision{
		SchemaVersion: contract.RosterSchemaVersion,
		ID: "ctrl-t04-rule", ProfileID: "SPECTRA", ControlName: "maker_ne_checker",
		Classification: contract.ControlClassRule, PriorVersion: "spectra-rule@1",
		ReplacementRef: "spectra-rule@2", ProtectedTestsRetained: true,
		RecordedAt: "2026-09-22T22:04:00Z",
	})
	if e != nil || rule.Classification != contract.ControlClassRule || !rule.ProtectedTestsRetained {
		t.Fatalf("rule: %+v %v", rule, e)
	}

	heur, e := s.ReviseMethodologyControl(contract.MethodologyControlRevision{
		SchemaVersion: contract.RosterSchemaVersion,
		ID: "ctrl-t04-heur", ProfileID: "nexus-adoption", ControlName: "option_count",
		Classification: contract.ControlClassHeuristic, PriorVersion: "opt@1",
		ReplacementRef: "opt@2", ProtectedTestsRetained: true,
		OptionCountIsHeuristic: true,
		RecordedAt: "2026-09-22T22:04:01Z",
	})
	if e != nil || !heur.OptionCountIsHeuristic {
		t.Fatalf("heuristic option_count: %+v %v", heur, e)
	}

	rat, e := s.ReviseMethodologyControl(contract.MethodologyControlRevision{
		SchemaVersion: contract.RosterSchemaVersion,
		ID: "ctrl-t04-rat", ProfileID: "ATLAS", ControlName: "probe_budget_rationale",
		Classification: contract.ControlClassRationale, PriorVersion: "atlas-r@1",
		ReplacementRef: "atlas-r@2", ProtectedTestsRetained: true,
		RationaleCertified: false,
		RecordedAt: "2026-09-22T22:04:02Z",
	})
	if e != nil || rat.RationaleCertified {
		t.Fatalf("rationale must not be certified: %+v %v", rat, e)
	}

	// Reject false certification / dropped protected tests.
	bad := contract.MethodologyControlRevision{
		SchemaVersion: contract.RosterSchemaVersion,
		ID: "ctrl-t04-bad", ProfileID: "ATLAS", ControlName: "probe_budget_rationale",
		Classification: contract.ControlClassRationale, PriorVersion: "atlas-r@1",
		ReplacementRef: "atlas-r@2", ProtectedTestsRetained: false,
		RecordedAt: "2026-09-22T22:04:03Z",
	}
	if _, e := s.ReviseMethodologyControl(bad); e == nil {
		t.Fatal("dropped protected tests must reject")
	}
	bad2 := bad
	bad2.ID = "ctrl-t04-bad2"
	bad2.ProtectedTestsRetained = true
	bad2.RationaleCertified = true
	if _, e := s.ReviseMethodologyControl(bad2); e == nil {
		t.Fatal("falsely certified rationale must reject")
	}
}

// TestV418T05 — exact producer/consumer versions; reject invented tags / changed performatives / mandatory imports.
func TestV418T05(t *testing.T) {
	s := rosterService(t)
	prof, e := s.GetRosterProfile("Gilgamesh")
	if e != nil {
		t.Fatal(e)
	}

	ok, e := s.CheckProfileCompatibility(contract.ProfileCompatibilityCheck{
		SchemaVersion: contract.RosterSchemaVersion,
		ID: "compat-t05-ok", ProfileID: "Gilgamesh",
		ProducerVersion: prof.ProducerVersion, ConsumerVersion: prof.ConsumerVersion,
		DiscoveryParity: true,
		RecordedAt:      "2026-09-22T22:05:00Z",
	})
	if e != nil || !ok.Compatible {
		t.Fatalf("exact versions should pass: %+v %v", ok, e)
	}

	// Reuse V4-16/V4-17 contracts on nexus-adoption slice.
	nexus, e := s.GetRosterProfile("nexus-adoption")
	if e != nil {
		t.Fatal(e)
	}
	if !nexus.ReuseRAMZALite || !nexus.ReuseViviModes {
		t.Fatalf("nexus-adoption should reuse V4-16/V4-17 contracts: %+v", nexus)
	}

	for _, neg := range []struct {
		id   string
		mut  func(*contract.ProfileCompatibilityCheck)
		want string
	}{
		{"compat-t05-prod", func(c *contract.ProfileCompatibilityCheck) {
			c.ProducerVersion = "invented@9.9.9"
		}, "producer_version_mismatch"},
		{"compat-t05-tags", func(c *contract.ProfileCompatibilityCheck) {
			c.InventedTags = true
		}, "invented_tags"},
		{"compat-t05-perf", func(c *contract.ProfileCompatibilityCheck) {
			c.ChangedPerformatives = true
		}, "changed_performatives"},
		{"compat-t05-ext", func(c *contract.ProfileCompatibilityCheck) {
			c.MandatoryExternalAgent = true
		}, "mandatory_external_agent_import"},
		{"compat-t05-disc", func(c *contract.ProfileCompatibilityCheck) {
			c.DiscoveryParity = false
		}, "discovery_parity_failed"},
	} {
		c := contract.ProfileCompatibilityCheck{
			SchemaVersion: contract.RosterSchemaVersion,
			ID: neg.id, ProfileID: "Gilgamesh",
			ProducerVersion: prof.ProducerVersion, ConsumerVersion: prof.ConsumerVersion,
			DiscoveryParity: true,
			RecordedAt:      "2026-09-22T22:05:10Z",
		}
		neg.mut(&c)
		out, e := s.CheckProfileCompatibility(c)
		if e != nil {
			t.Fatal(e)
		}
		if out.Compatible {
			t.Fatalf("%s should reject", neg.id)
		}
		joined := strings.Join(out.RejectReasons, ",")
		if !strings.Contains(joined, neg.want) {
			t.Fatalf("%s: want %s in %s", neg.id, neg.want, joined)
		}
	}
}

// TestV418T06 — missing input / oversized / inline-only reject isolation; bounded consultant succeeds.
func TestV418T06(t *testing.T) {
	s := rosterService(t)
	vigil, e := s.GetRosterProfile("VIGIL")
	if e != nil {
		t.Fatal(e)
	}

	ok, e := s.CheckIsolationContract(contract.IsolationContractCheck{
		SchemaVersion: contract.RosterSchemaVersion,
		ID: "iso-t06-ok", ProfileID: "VIGIL", MethodID: "vigil-consult",
		AdvertisedIsolated: true, ExecutionForm: contract.FormConsultant,
		Contract: vigil.Contract, ProvidedInputs: []string{"threat_model"},
		ResultBytes: 100, InlineOnlySkill: false,
		RecordedAt: "2026-09-22T22:06:00Z",
	})
	if e != nil || !ok.Accepted {
		t.Fatalf("bounded consultant should succeed: %+v %v", ok, e)
	}

	miss, e := s.CheckIsolationContract(contract.IsolationContractCheck{
		SchemaVersion: contract.RosterSchemaVersion,
		ID: "iso-t06-miss", ProfileID: "VIGIL", MethodID: "vigil-consult",
		AdvertisedIsolated: true, ExecutionForm: contract.FormConsultant,
		Contract: vigil.Contract, ProvidedInputs: []string{}, // missing threat_model
		ResultBytes: 10, RecordedAt: "2026-09-22T22:06:01Z",
	})
	if e != nil || miss.Accepted || !strings.Contains(strings.Join(miss.RejectReasons, ","), "missing_input") {
		t.Fatalf("missing input: %+v %v", miss, e)
	}

	oversized := vigil.Contract
	oversized.MaxOutputBytes = 50
	big, e := s.CheckIsolationContract(contract.IsolationContractCheck{
		SchemaVersion: contract.RosterSchemaVersion,
		ID: "iso-t06-big", ProfileID: "VIGIL", MethodID: "vigil-consult",
		AdvertisedIsolated: true, ExecutionForm: contract.FormConsultant,
		Contract: oversized, ProvidedInputs: []string{"threat_model"},
		ResultBytes: 9999, RecordedAt: "2026-09-22T22:06:02Z",
	})
	if e != nil || big.Accepted || !strings.Contains(strings.Join(big.RejectReasons, ","), "oversized_result") {
		t.Fatalf("oversized: %+v %v", big, e)
	}

	inlineOnly := contract.FixtureSkill("kupo-inline", "1.0.0", []string{contract.FormEmbedded}, []string{"errand"}, "kupo-errand.v1")
	inl, e := s.CheckIsolationContract(contract.IsolationContractCheck{
		SchemaVersion: contract.RosterSchemaVersion,
		ID: "iso-t06-inl", ProfileID: "Kupo", MethodID: "kupo-inline",
		AdvertisedIsolated: true, ExecutionForm: contract.FormConsultant,
		Contract: inlineOnly, ProvidedInputs: []string{"errand"},
		InlineOnlySkill: true, ResultBytes: 10,
		RecordedAt: "2026-09-22T22:06:03Z",
	})
	if e != nil || inl.Accepted || !strings.Contains(strings.Join(inl.RejectReasons, ","), "inline_only") {
		t.Fatalf("inline-only: %+v %v", inl, e)
	}
}

// TestV418T07 — untested / no-win / inconclusive stay experimental or maintenance — never measured.
func TestV418T07(t *testing.T) {
	s := rosterService(t)
	cases := []struct {
		id, class, wantLabel string
	}{
		{"ben-t07-unt", contract.BenefitUntested, contract.BenefitUnproven},
		{"ben-t07-nw", contract.BenefitNoWin, contract.BenefitMaintenance},
		{"ben-t07-inc", contract.BenefitInconclusive, contract.BenefitExperimental},
	}
	for _, c := range cases {
		out, e := s.LabelBenefitEvidence(contract.BenefitEvidenceLabel{
			SchemaVersion: contract.RosterSchemaVersion,
			ID: c.id, ProfileID: "SPECTRA", Strategy: "fan-out-heavy",
			EvidenceClass: c.class,
			RecordedAt:    "2026-09-22T22:07:00Z",
		})
		if e != nil {
			t.Fatal(e)
		}
		if out.Label != c.wantLabel {
			t.Fatalf("%s: label=%s want %s", c.id, out.Label, c.wantLabel)
		}
		if out.AdvertisedAsMeasured || out.PerformanceGainClaimed || out.Label == contract.BenefitMeasured {
			t.Fatalf("%s: must not advertise measured: %+v", c.id, out)
		}
	}

	// Explicit measured without V4-21 evidence rejects.
	if _, e := s.LabelBenefitEvidence(contract.BenefitEvidenceLabel{
		SchemaVersion: contract.RosterSchemaVersion,
		ID: "ben-t07-bad", ProfileID: "SPECTRA", Strategy: "claimed-win",
		EvidenceClass: contract.BenefitMeasured, Label: contract.BenefitMeasured,
		AdvertisedAsMeasured: true, PerformanceGainClaimed: true,
		RecordedAt: "2026-09-22T22:07:10Z",
	}); e == nil {
		t.Fatal("measured without V4-21 evidence must reject")
	}

	// With V4-21 evidence ref, measured is allowed.
	ok, e := s.LabelBenefitEvidence(contract.BenefitEvidenceLabel{
		SchemaVersion: contract.RosterSchemaVersion,
		ID: "ben-t07-ok", ProfileID: "SPECTRA", Strategy: "qualified-arm",
		EvidenceClass: contract.BenefitMeasured, Label: contract.BenefitMeasured,
		QualifyingComparative: true, V421EvidenceRef: "receipts/V4-21.md#arm-fixture",
		AdvertisedAsMeasured: true, PerformanceGainClaimed: true,
		RecordedAt: "2026-09-22T22:07:11Z",
	})
	if e != nil || ok.Label != contract.BenefitMeasured {
		t.Fatalf("measured with V4-21 ref: %+v %v", ok, e)
	}
}
