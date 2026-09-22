package controller

import (
	"testing"
	"time"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
)

func releaseService(t *testing.T) *Service {
	t.Helper()
	s := New(t.TempDir(), Options{Timeout: time.Second, Clock: func() time.Time {
		return time.Date(2026, 9, 22, 19, 0, 0, 0, time.UTC)
	}})
	if e := s.Init(); e != nil {
		t.Fatal(e)
	}
	if e := s.EnsureInstrumentNamespaces(); e != nil {
		t.Fatal(e)
	}
	if e := s.EnsureCalibrationNamespaces(); e != nil {
		t.Fatal(e)
	}
	if e := s.EnsureReleaseNamespaces(); e != nil {
		t.Fatal(e)
	}
	return s
}

func baseMigration(id, origin string) contract.MigrationAttempt {
	return contract.MigrationAttempt{
		SchemaVersion:     contract.ReleaseSchemaVersion,
		ID:                id,
		Origin:            origin,
		Authorized:        true,
		AuthorizationRef:  "auth-mig-1",
		Stage:             contract.MigStageStaging,
		PreviousInstallID: "install-prev",
		StagedInstallID:   "install-staged",
		ActiveInstallID:   "install-prev",
		FailurePoint:      contract.MigFailNone,
		PendingReservations: []string{"res-1"},
		RecordedAt:        "2026-09-22T19:00:00Z",
	}
}

// TestV423T01 — stage+verify before switch; fresh/legacy/v3/dirty/interrupted; no force-integrity bypass.
func TestV423T01(t *testing.T) {
	s := releaseService(t)
	origins := []string{
		contract.MigOriginFresh, contract.MigOriginPreV1411, contract.MigOriginV220,
		contract.MigOriginV331, contract.MigOriginDirty, contract.MigOriginInterrupted,
	}
	for _, origin := range origins {
		m := baseMigration("mig-"+origin, origin)
		out, e := s.AttemptMigration(m)
		if e != nil {
			t.Fatalf("%s: %v", origin, e)
		}
		if !out.StagedVerified || !out.ActiveSwitched || out.ActiveInstallID != "install-staged" {
			t.Fatalf("%s must stage+verify then switch: %+v", origin, out)
		}
		if out.ForceIntegrityBypass {
			t.Fatalf("%s force-integrity bypass forbidden: %+v", origin, out)
		}
	}

	bypass := baseMigration("mig-bypass", contract.MigOriginFresh)
	bypass.ForceIntegrityBypass = true
	out, e := s.AttemptMigration(bypass)
	if e != nil {
		t.Fatal(e)
	}
	if out.ForceIntegrityBypass {
		t.Fatalf("controller must clear force-integrity bypass: %+v", out)
	}

	unauth := baseMigration("mig-unauth", contract.MigOriginLegacyGeneric)
	unauth.Authorized = false
	unauth.AuthorizationRef = ""
	out, e = s.AttemptMigration(unauth)
	if e != nil {
		t.Fatal(e)
	}
	if out.ActiveSwitched || !out.Rejected {
		t.Fatalf("unauthorized migration must not switch: %+v", out)
	}
}

// TestV423T02 — staging/switch/smoke failure recovers previous install + user state.
func TestV423T02(t *testing.T) {
	s := releaseService(t)
	for _, fail := range []string{contract.MigFailStaging, contract.MigFailSwitch, contract.MigFailSmoke} {
		m := baseMigration("mig-fail-"+fail, contract.MigOriginV331)
		m.FailurePoint = fail
		out, e := s.AttemptMigration(m)
		if e != nil {
			t.Fatal(e)
		}
		if out.ActiveSwitched || out.ActiveInstallID != "install-prev" || !out.Rejected {
			t.Fatalf("%s must not switch and must reject: %+v", fail, out)
		}
		if !out.UserStatePreserved || !out.SessionsPreserved || !out.SettingsPreserved {
			t.Fatalf("%s must preserve user state: %+v", fail, out)
		}
		rec, e := s.RecoverMigration(out.ID)
		if e != nil {
			t.Fatal(e)
		}
		if !rec.PreviousInstallRestored || !rec.UsablePrevious || rec.ActiveInstallID != "install-prev" {
			t.Fatalf("%s recovery must restore previous: %+v", fail, out)
		}
		if !rec.RepeatMigrationSafe || len(rec.PendingReservations) == 0 || len(rec.NativeSessions) == 0 {
			t.Fatalf("%s recovery must keep sessions/reservations/repeat-safe: %+v", fail, rec)
		}
	}
}

// TestV423T03 — docs-only vs code/behavior; smoke ≠ missing live evidence.
func TestV423T03(t *testing.T) {
	s := releaseService(t)
	docs := contract.ReleaseCandidate{
		SchemaVersion: contract.ReleaseSchemaVersion,
		ID: "cand-docs", Kind: contract.ReleaseKindDocsOnly,
		DeclaredDeterministicOK: true,
		DeterministicChecks:     []string{"go-test", "schema"},
		SmokeSucceeded:          true,
		RecordedAt:              "2026-09-22T19:00:00Z",
	}
	out, e := s.EvaluateReleaseCandidate(docs)
	if e != nil || !out.GatePassed || out.LiveEvidenceRequired {
		t.Fatalf("docs-only should pass without live: %+v %v", out, e)
	}

	codeMissing := contract.ReleaseCandidate{
		SchemaVersion: contract.ReleaseSchemaVersion,
		ID: "cand-code-smoke", Kind: contract.ReleaseKindCodeBehavior,
		DeclaredDeterministicOK: true,
		DeterministicChecks:     []string{"go-test", "anchors"},
		SmokeSucceeded:          true,
		LiveEvidenceAuthorized:  false,
		LiveEvidencePresent:     false,
		RecordedAt:              "2026-09-22T19:00:00Z",
	}
	out, e = s.EvaluateReleaseCandidate(codeMissing)
	if e != nil {
		t.Fatal(e)
	}
	if out.GatePassed || out.RejectReason != "smoke_success_does_not_replace_live_evidence" {
		t.Fatalf("smoke must not replace live evidence: %+v", out)
	}

	codeOK := contract.ReleaseCandidate{
		SchemaVersion: contract.ReleaseSchemaVersion,
		ID: "cand-code-ok", Kind: contract.ReleaseKindCodeBehavior,
		DeclaredDeterministicOK: true,
		DeterministicChecks:     []string{"go-test"},
		LiveEvidenceAuthorized:  true,
		LiveEvidencePresent:     true,
		SmokeSucceeded:          true,
		RecordedAt:              "2026-09-22T19:00:00Z",
	}
	out, e = s.EvaluateReleaseCandidate(codeOK)
	if e != nil || !out.GatePassed {
		t.Fatalf("authorized live evidence should pass gate: %+v %v", out, e)
	}
}

// TestV423T04 — insufficient evidence / missing approval leave defaults unchanged; report ≠ tag/merge.
func TestV423T04(t *testing.T) {
	s := releaseService(t)
	cases := []struct {
		id      string
		enough  bool
		approve bool
		report  bool
		want    string
	}{
		{"auth-nowin", false, false, true, contract.AuthBlockedInsufficientEvidence},
		{"auth-noapprove", true, false, true, contract.AuthBlockedMissingApproval},
		{"auth-report", true, true, true, contract.AuthBlockedPreparedReportOnly},
	}
	for _, tc := range cases {
		p := contract.PromotionAuthorization{
			SchemaVersion:           contract.ReleaseSchemaVersion,
			ID:                      tc.id,
			CandidateID:             "cand-code-ok",
			EvidenceSufficient:      tc.enough,
			OperatorApprovalPresent: tc.approve,
			ApprovalRef:             "",
			PreparedReportReady:     tc.report,
			RecordedAt:              "2026-09-22T19:00:00Z",
		}
		if tc.approve {
			p.ApprovalRef = "ops-approve-1"
		}
		out, e := s.AuthorizePromotion(p)
		if e != nil {
			t.Fatal(e)
		}
		if out.BehavioralDefaultsChanged || out.TagAuthorized || out.MergeAuthorized || out.PublicationAuthorized {
			t.Fatalf("%s must not change defaults or authorize publication: %+v", tc.id, out)
		}
		if out.BlockReason != tc.want {
			t.Fatalf("%s block want %s got %s", tc.id, tc.want, out.BlockReason)
		}
	}
}

// TestV423T05 — unmigrated supported consumer blocks retirement.
func TestV423T05(t *testing.T) {
	s := releaseService(t)
	blocked := contract.RetirementRequest{
		SchemaVersion: contract.ReleaseSchemaVersion,
		ID: "retire-1", ComponentID: "component-legacy",
		UnmigratedConsumers: []string{"consumer-a"},
		ReplacementTested:   true,
		InventoryEvidence:   true, LicenseEvidence: true, HistoryEvidence: true,
		SupportEvidence: true, RollbackEvidence: true,
		ExplicitArchiveAuth: true, ArchiveAuthorizationRef: "archive-auth-1",
		RecordedAt: "2026-09-22T19:00:00Z",
	}
	out, e := s.EvaluateRetirement(blocked)
	if e != nil {
		t.Fatal(e)
	}
	if !out.RetirementBlocked || out.BlockReason != "unmigrated_supported_consumer" {
		t.Fatalf("unmigrated consumer must block: %+v", out)
	}

	complete := contract.RetirementRequest{
		SchemaVersion: contract.ReleaseSchemaVersion,
		ID: "retire-2", ComponentID: "component-ready",
		UnmigratedConsumers: nil,
		ReplacementTested:   true,
		InventoryEvidence:   true, LicenseEvidence: true, HistoryEvidence: true,
		SupportEvidence: true, RollbackEvidence: true,
		ExplicitArchiveAuth: true, ArchiveAuthorizationRef: "archive-auth-2",
		RecordedAt: "2026-09-22T19:00:00Z",
	}
	out, e = s.EvaluateRetirement(complete)
	if e != nil {
		t.Fatal(e)
	}
	if !out.RetirementBlocked || out.BlockReason != "archival_not_authorized_by_planning_package" {
		t.Fatalf("package must still refuse real archival: %+v", out)
	}
}

// TestV423T06 — host version change invalidates cancellation/usage/tool-boundary qualification.
func TestV423T06(t *testing.T) {
	s := releaseService(t)
	h := contract.HostCapabilityQualification{
		SchemaVersion:        contract.ReleaseSchemaVersion,
		ID:                   "hostcap-1",
		HostID:               "host-claude",
		QualifiedHostVersion: "host-v1",
		ObservedHostVersion:  "host-v1",
		CapabilityAreas: []string{
			contract.CapAreaCancellation, contract.CapAreaUsage, contract.CapAreaToolBoundary,
		},
		QualificationValid:  true,
		ManagedClaimsActive: true,
		RecordedAt:          "2026-09-22T19:00:00Z",
	}
	out, e := s.RegisterHostCapabilityQualification(h)
	if e != nil || !out.QualificationValid {
		t.Fatalf("register: %+v %v", out, e)
	}
	out, e = s.InvalidateHostCapabilityOnVersionChange(h.ID, "host-v2")
	if e != nil {
		t.Fatal(e)
	}
	if out.QualificationValid || out.ManagedClaimsActive || !out.RecheckRequired {
		t.Fatalf("version drift must invalidate managed claims: %+v", out)
	}
	if out.InvalidationReason == "" {
		t.Fatalf("invalidation reason required: %+v", out)
	}
}

// TestV423T07 — correctness / managed-op / performance reported separately; no composite green.
func TestV423T07(t *testing.T) {
	s := releaseService(t)
	r := contract.ReleaseReadinessReport{
		SchemaVersion:                contract.ReleaseSchemaVersion,
		ID:                           "ready-1",
		CandidateID:                  "cand-code-smoke",
		CorrectnessDecision:          contract.DecisionPass,
		ManagedOperationDecision:     contract.DecisionBlocked,
		PerformancePromotionDecision: contract.DecisionNull,
		CompositeGreenBadge:          true, // cleared
		GovernanceOnlyLabel:          true,
		MeasuredSpeedCostSuperiority: true, // cleared when governance-only
		DeferredExperiments:          []string{"optional-client", "optional-offline-ui"},
		ImplementedBreaksOnly:        true,
		RecordedAt:                   "2026-09-22T19:00:00Z",
	}
	out, e := s.ReportReleaseReadiness(r)
	if e != nil {
		t.Fatal(e)
	}
	if out.CompositeGreenBadge {
		t.Fatalf("composite green badge forbidden: %+v", out)
	}
	if out.MeasuredSpeedCostSuperiority {
		t.Fatalf("governance-only must not claim measured superiority: %+v", out)
	}
	if out.CorrectnessDecision != contract.DecisionPass ||
		out.ManagedOperationDecision != contract.DecisionBlocked ||
		out.PerformancePromotionDecision != contract.DecisionNull {
		t.Fatalf("decisions must remain separate: %+v", out)
	}
}

// TestV423T08 — strategy/method rollback retains lineage/evidence/obligations; no stale authority.
func TestV423T08(t *testing.T) {
	s := releaseService(t)
	r := contract.StrategyMethodRollback{
		SchemaVersion:           contract.ReleaseSchemaVersion,
		ID:                      "rollback-1",
		StrategyVersion:         "strategy-v2",
		RollbackTarget:          "strategy-v1",
		ActiveCandidateID:       "cand-active",
		PendingCancellation:     true,
		UnknownUsage:            true,
		LaterFailureRecorded:    true,
		StaleAcceptance:         true,  // cleared
		BudgetRefilled:          true,  // cleared
		WiderAuthorityGranted:   true,  // cleared
		StillAuthorizedContract: "contract-still-auth",
		RecordedAt:              "2026-09-22T19:00:00Z",
	}
	out, e := s.RollbackStrategyMethod(r)
	if e != nil {
		t.Fatal(e)
	}
	if !out.TaskLineageRetained || !out.EvidenceHistoryRetained {
		t.Fatalf("must retain lineage and evidence: %+v", out)
	}
	if len(out.OutstandingObligations) == 0 {
		t.Fatalf("must retain outstanding obligations: %+v", out)
	}
	if out.StaleAcceptance || out.BudgetRefilled || out.WiderAuthorityGranted {
		t.Fatalf("must not grant stale acceptance/budget/wider authority: %+v", out)
	}
}
