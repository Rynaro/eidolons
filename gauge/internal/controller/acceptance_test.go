package controller

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
)

func accService(t *testing.T) *Service {
	t.Helper()
	s := New(t.TempDir(), Options{Timeout: time.Second, Clock: func() time.Time {
		return time.Date(2026, 9, 22, 18, 0, 0, 0, time.UTC)
	}})
	if e := s.Init(); e != nil {
		t.Fatal(e)
	}
	if e := s.EnsureAcceptanceNamespaces(); e != nil {
		t.Fatal(e)
	}
	return s
}

func accRoot(t *testing.T, s *Service, id string) {
	t.Helper()
	if e := s.InitRoot(id); e != nil {
		t.Fatal(e)
	}
}

func samplePkg(id string) contract.AcceptancePackage {
	return contract.AcceptancePackage{
		SchemaVersion:           contract.AcceptanceSchemaVersion,
		ID:                      id,
		RequestedBehavior:       "returns greeting for known user",
		OracleOrigin:            "fixture-oracle",
		OracleVersion:           "1.0.0",
		EnvironmentID:           "env-fixture",
		RequiredChecks:          []string{"unit", "behavior"},
		RequiresBehaviorGate:    true,
		BehavioralDiscriminator: "greeting_response_vs_empty_stub",
	}
}

func freezeEntries() []contract.CandidateContentEntry {
	return []contract.CandidateContentEntry{
		{Path: "src/main.go", Kind: "tracked", Digest: "aaa", Mode: "0644"},
		{Path: ".env.local", Kind: "untracked", Digest: "bbb", Mode: "0600"},
		{Path: "config.yaml", Kind: "config", Digest: "ccc", Mode: "0644"},
		{Path: "bin/tool", Kind: "mode", Digest: "ddd", Mode: "0755"},
	}
}

func freezeReq(cand, root, acc string) contract.FreezeRequest {
	return contract.FreezeRequest{
		SchemaVersion: contract.AcceptanceSchemaVersion,
		CandidateID:   cand,
		RootID:        root,
		AssignmentID:  "assign-1",
		WorkspaceRoot: "/tmp/ws",
		Entries:       freezeEntries(),
		AcceptanceID:  acc,
		EnvironmentID: "env-fixture",
		BaseDigest:    "base-abc",
		RecordedAt:    "2026-09-22T18:00:00Z",
	}
}

// TestV414T01 — freeze binds check to snapshot; concurrent maker edits do not change tested identity.
func TestV414T01(t *testing.T) {
	s := accService(t)
	accRoot(t, s, "root-t01")
	pkg := samplePkg("acc-t01")
	if e := s.RegisterAcceptancePackage(pkg); e != nil {
		t.Fatal(e)
	}
	frozen, e := s.FreezeCandidate("root-t01", freezeReq("cand-t01", "root-t01", "acc-t01"))
	if e != nil {
		t.Fatal(e)
	}
	snap := frozen.ContentDigest

	// Concurrent maker edits: new freeze with changed entries gets different digest;
	// original freeze identity remains bound for checks.
	edited := freezeReq("cand-t01-edit", "root-t01", "acc-t01")
	edited.Entries = append(edited.Entries, contract.CandidateContentEntry{
		Path: "src/extra.go", Kind: "tracked", Digest: "eee", Mode: "0644",
	})
	edited2, e := s.FreezeCandidate("root-t01", edited)
	if e != nil {
		t.Fatal(e)
	}
	if edited2.ContentDigest == snap {
		t.Fatal("edited candidate must change content digest")
	}

	iso := contract.IsolationCapability{
		Mode: contract.IsolationEnforced, Enforced: true, ContextProvenance: "present",
	}
	receipt, grade, e := s.FinishCheck("root-t01", contract.RunCheckRequest{
		SchemaVersion: contract.AcceptanceSchemaVersion,
		ReceiptID: "rcpt-t01", CheckID: "unit", CandidateID: "cand-t01",
		AcceptanceID: "acc-t01", EnvironmentID: "env-fixture",
		RunnerID: "runner-1", InvocationID: "inv-1",
		ObservedOutcome: contract.OutcomePass, IsolationMode: contract.IsolationEnforced,
		BehaviorObserved: true,
	}, iso)
	if e != nil {
		t.Fatal(e)
	}
	if !grade.Trusted {
		t.Fatalf("expected trusted grade: %+v", grade)
	}
	joined := strings.Join(receipt.Notes, " ")
	if !strings.Contains(joined, "snapshot="+snap) {
		t.Fatalf("logs must identify exact snapshot tested: %v", receipt.Notes)
	}
	if !strings.Contains(joined, "candidate=cand-t01") {
		t.Fatalf("logs must identify candidate: %v", receipt.Notes)
	}
	// Tracked/untracked/config/mode all in freeze.
	kinds := map[string]bool{}
	for _, ent := range frozen.Entries {
		kinds[ent.Kind] = true
	}
	for _, k := range []string{"tracked", "untracked", "config", "mode"} {
		if !kinds[k] {
			t.Fatalf("missing kind %s in freeze", k)
		}
	}
}

// TestV414T02 — enforced FS boundary denies protected writes; credentials not inherited.
func TestV414T02(t *testing.T) {
	base := t.TempDir()
	b, e := NewIsolationBoundary(base, contract.IsolationEnforced)
	if e != nil {
		t.Fatal(e)
	}
	defer b.Release()

	cap := b.Capability("present")
	if !cap.Enforced {
		t.Fatal("expected enforced isolation")
	}

	// Direct write must fail under chmod deny.
	if e := b.AttemptProtectedWrite("journal.jsonl", "tamper"); e == nil {
		t.Fatal("direct protected write must be denied")
	}

	for _, name := range []string{"journal.jsonl", "receipt.json", "oracle.yaml", "checker.key"} {
		denied, out, err := b.AttemptProtectedWriteViaShell(name, "candidate-overwrite")
		if err != nil {
			t.Fatalf("%s: %v out=%s", name, err, out)
		}
		if !denied {
			t.Fatalf("%s: expected write denial", name)
		}
	}

	// Candidate env must not inherit checker credentials.
	env := append(filteredCandidateEnv(), "CHECKER_TOKEN=secret", "GAUGE_SIGNER_KEY=k", "ACCEPTANCE_KEY=x")
	// filteredCandidateEnv strips from os.Environ; CandidateEnvHasCheckerCreds on raw injection:
	if !CandidateEnvHasCheckerCreds([]string{"CHECKER_TOKEN=secret"}) {
		t.Fatal("detector should see checker creds")
	}
	clean := filteredCandidateEnv()
	if CandidateEnvHasCheckerCreds(clean) {
		t.Fatal("filtered candidate env must not carry checker credentials")
	}
	_ = env

	// Label-only boundary does NOT deny — contrast control.
	labelBase := t.TempDir()
	lb, e := NewIsolationBoundary(labelBase, contract.IsolationLabel)
	if e != nil {
		t.Fatal(e)
	}
	if lb.Capability("present").Enforced {
		t.Fatal("label-only must not report enforced")
	}
	if e := lb.AttemptProtectedWrite("journal.jsonl", "label-tamper"); e != nil {
		t.Fatalf("label-only should allow write (no enforcement): %v", e)
	}
}

// TestV414T03 — pass/fail/error/cancelled/skipped recorded; prose cannot replace observation.
func TestV414T03(t *testing.T) {
	s := accService(t)
	accRoot(t, s, "root-t03")
	if e := s.RegisterAcceptancePackage(samplePkg("acc-t03")); e != nil {
		t.Fatal(e)
	}
	if _, e := s.FreezeCandidate("root-t03", freezeReq("cand-t03", "root-t03", "acc-t03")); e != nil {
		t.Fatal(e)
	}
	iso := contract.IsolationCapability{Mode: contract.IsolationEnforced, Enforced: true, ContextProvenance: "present"}

	outcomes := []string{
		contract.OutcomePass, contract.OutcomeFail, contract.OutcomeError,
		contract.OutcomeCancelled, contract.OutcomeSkipped,
	}
	for i, o := range outcomes {
		r, _, e := s.FinishCheck("root-t03", contract.RunCheckRequest{
			SchemaVersion: contract.AcceptanceSchemaVersion,
			ReceiptID: "rcpt-t03-" + o, CheckID: "unit", CandidateID: "cand-t03",
			AcceptanceID: "acc-t03", EnvironmentID: "env-fixture",
			RunnerID: "runner-1", InvocationID: "inv-" + o,
			ObservedOutcome: o, IsolationMode: contract.IsolationEnforced,
			BehaviorObserved: true, AuthoredProse: "looks good",
		}, iso)
		if e != nil {
			t.Fatalf("%s: %v", o, e)
		}
		if r.Outcome != o {
			t.Fatalf("want %s got %s (i=%d)", o, r.Outcome, i)
		}
		if r.Provenance.InvocationID == "" || r.Provenance.RunnerID == "" {
			t.Fatalf("missing provenance: %+v", r.Provenance)
		}
	}

	// Authored success prose without observation → error, not pass.
	r, grade, e := s.FinishCheck("root-t03", contract.RunCheckRequest{
		SchemaVersion: contract.AcceptanceSchemaVersion,
		ReceiptID: "rcpt-t03-prose", CheckID: "unit", CandidateID: "cand-t03",
		AcceptanceID: "acc-t03", EnvironmentID: "env-fixture",
		RunnerID: "runner-1", InvocationID: "inv-prose",
		ObservedOutcome: "", AuthoredProse: "SUCCESS all green",
		IsolationMode: contract.IsolationEnforced, BehaviorObserved: true,
	}, iso)
	if e != nil {
		t.Fatal(e)
	}
	if r.Outcome != contract.OutcomeError {
		t.Fatalf("prose alone must not pass: %s", r.Outcome)
	}
	if grade.Trusted {
		t.Fatal("prose-only must not be trusted")
	}
}

// TestV414T04 — missing isolation/provenance withholds trusted grade; enforced is positive control.
func TestV414T04(t *testing.T) {
	cases := []struct {
		name string
		cap  contract.IsolationCapability
		want bool
	}{
		{"enforced+prov", contract.IsolationCapability{Mode: contract.IsolationEnforced, Enforced: true, ContextProvenance: "present"}, true},
		{"label", contract.IsolationCapability{Mode: contract.IsolationLabel, Enforced: false, ContextProvenance: "present"}, false},
		{"directory", contract.IsolationCapability{Mode: contract.IsolationDirectory, Enforced: false, ContextProvenance: "present"}, false},
		{"no-prov", contract.IsolationCapability{Mode: contract.IsolationEnforced, Enforced: true, ContextProvenance: "absent"}, false},
	}
	for _, c := range cases {
		g := GradeFromIsolation(c.cap)
		if g.Trusted != c.want {
			t.Fatalf("%s: trusted=%v want %v reasons=%v", c.name, g.Trusted, c.want, g.Reasons)
		}
		if !c.want && g.IntegrityGrade != contract.GradeWithheld {
			t.Fatalf("%s: expected withheld grade, got %s", c.name, g.IntegrityGrade)
		}
		if c.want && g.IntegrityGrade != contract.GradeTrustedIntegrity {
			t.Fatalf("%s: expected trusted integrity, got %s", c.name, g.IntegrityGrade)
		}
	}
}

// TestV414T05 — base moved / dirty / conflicts require revalidation; no unchecked apply.
func TestV414T05(t *testing.T) {
	s := accService(t)
	accRoot(t, s, "root-t05")
	if e := s.RegisterAcceptancePackage(samplePkg("acc-t05")); e != nil {
		t.Fatal(e)
	}
	if _, e := s.FreezeCandidate("root-t05", freezeReq("cand-t05", "root-t05", "acc-t05")); e != nil {
		t.Fatal(e)
	}

	ok, e := s.ApplyCandidate("root-t05", contract.ApplyRequest{
		SchemaVersion: contract.AcceptanceSchemaVersion, CandidateID: "cand-t05",
		CurrentBaseDigest: "base-abc",
	})
	if e != nil {
		t.Fatal(e)
	}
	if ok.Status != contract.ApplyAllowed {
		t.Fatalf("stable base should allow: %+v", ok)
	}

	moved, e := s.ApplyCandidate("root-t05", contract.ApplyRequest{
		SchemaVersion: contract.AcceptanceSchemaVersion, CandidateID: "cand-t05",
		CurrentBaseDigest: "base-moved",
	})
	if e != nil {
		t.Fatal(e)
	}
	if moved.Status != contract.ApplyRequireRevalidate {
		t.Fatalf("moved base: %+v", moved)
	}

	dirty, e := s.ApplyCandidate("root-t05", contract.ApplyRequest{
		SchemaVersion: contract.AcceptanceSchemaVersion, CandidateID: "cand-t05",
		CurrentBaseDigest: "base-abc", TargetDirty: true,
	})
	if e != nil {
		t.Fatal(e)
	}
	if dirty.Status != contract.ApplyRequireRevalidate {
		t.Fatalf("dirty: %+v", dirty)
	}

	conflict, e := s.ApplyCandidate("root-t05", contract.ApplyRequest{
		SchemaVersion: contract.AcceptanceSchemaVersion, CandidateID: "cand-t05",
		CurrentBaseDigest: "base-abc", HasConflicts: true,
	})
	if e != nil {
		t.Fatal(e)
	}
	if conflict.Status != contract.ApplyRequireRevalidate {
		t.Fatalf("conflicts: %+v", conflict)
	}
}

// TestV414T06 — human report preserves distinct fields; digest ≠ author/semantic.
func TestV414T06(t *testing.T) {
	frozen := contract.FrozenCandidate{
		SchemaVersion: contract.AcceptanceSchemaVersion,
		ID: "cand-t06", ContentDigest: "deadbeef",
	}
	proj := contract.Projection{
		ArtifactIntegrity:   contract.Grade{Status: "verified"},
		ExecutionProvenance: contract.Grade{Status: "self-attested"},
		AcceptanceStatus:    contract.Acceptance{Status: "not-accepted", Reasons: []string{"pending"}},
		Checks: []contract.Check{{
			ID: "unit", OracleID: "o1", Outcome: "pass",
			ArtifactIntegrity: "verified", ExecutionProvenance: "self-attested",
		}},
	}
	report := ProjectHumanReport(frozen, nil, proj)
	if report.ArtifactIntegrity.Status != "verified" {
		t.Fatal("integrity field lost")
	}
	if report.ExecutionProvenance.Status != "self-attested" {
		t.Fatal("provenance field lost")
	}
	if report.AcceptanceStatus.Status != "not-accepted" {
		t.Fatal("acceptance field lost")
	}
	if report.AuthorAuthenticated {
		t.Fatal("digest must not authenticate author")
	}
	if report.SemanticCorrectness != "unproven" {
		t.Fatal("digest must not prove semantic correctness")
	}
	// Canonical round-trip.
	raw, e := json.Marshal(report.Canonical)
	if e != nil {
		t.Fatal(e)
	}
	var again map[string]any
	if e := json.Unmarshal(raw, &again); e != nil {
		t.Fatal(e)
	}
	if again["content_digest"] != "deadbeef" {
		t.Fatalf("round-trip digest: %v", again["content_digest"])
	}
}

// TestV414T07 — qualification needs valid+stub+missing_edge+regression discrimination.
func TestV414T07(t *testing.T) {
	s := accService(t)
	accRoot(t, s, "root-t07")
	if e := s.RegisterAcceptancePackage(samplePkg("acc-t07")); e != nil {
		t.Fatal(e)
	}

	good, e := s.QualifyOracle("root-t07", contract.QualifyRequest{
		SchemaVersion: contract.AcceptanceSchemaVersion,
		ID: "qual-good", AcceptanceID: "acc-t07",
		Trials: []contract.OracleTrial{
			{CandidateLabel: "valid", Expected: "pass", Observed: "pass"},
			{CandidateLabel: "stub", Expected: "fail", Observed: "fail"},
			{CandidateLabel: "missing_edge", Expected: "fail", Observed: "fail"},
			{CandidateLabel: "regression", Expected: "fail", Observed: "fail"},
		},
	})
	if e != nil {
		t.Fatal(e)
	}
	if !good.Qualified {
		t.Fatalf("adequate discrimination should qualify: %+v", good)
	}

	bad, e := s.QualifyOracle("root-t07", contract.QualifyRequest{
		SchemaVersion: contract.AcceptanceSchemaVersion,
		ID: "qual-bad", AcceptanceID: "acc-t07",
		Trials: []contract.OracleTrial{
			{CandidateLabel: "valid", Expected: "pass", Observed: "pass"},
			{CandidateLabel: "stub", Expected: "fail", Observed: "pass"}, // fails to reject stub
			{CandidateLabel: "missing_edge", Expected: "fail", Observed: "fail"},
			{CandidateLabel: "regression", Expected: "fail", Observed: "fail"},
		},
	})
	if e != nil {
		t.Fatal(e)
	}
	if bad.Qualified {
		t.Fatal("inadequate discrimination must not qualify")
	}
	found := false
	for _, r := range bad.FailReasons {
		if r == "inadequate_discrimination" || strings.Contains(r, "stub:") {
			found = true
		}
	}
	if !found {
		t.Fatalf("expected discrimination failure: %v", bad.FailReasons)
	}

	missing, e := s.QualifyOracle("root-t07", contract.QualifyRequest{
		SchemaVersion: contract.AcceptanceSchemaVersion,
		ID: "qual-missing", AcceptanceID: "acc-t07",
		Trials: []contract.OracleTrial{
			{CandidateLabel: "valid", Expected: "pass", Observed: "pass"},
		},
	})
	if e != nil {
		t.Fatal(e)
	}
	if missing.Qualified {
		t.Fatal("missing representative defects must not qualify")
	}
}

// TestV414T08 — maker test/def changes need owner review; maker alone insufficient.
func TestV414T08(t *testing.T) {
	s := accService(t)
	accRoot(t, s, "root-t08")
	if e := s.RegisterAcceptancePackage(samplePkg("acc-t08")); e != nil {
		t.Fatal(e)
	}

	for _, kind := range []string{"deletion", "relaxed_assertion", "legitimate_expectation"} {
		rev, e := s.ReviewOwnerChange("root-t08", contract.AcceptanceOwnerReview{
			SchemaVersion: contract.AcceptanceSchemaVersion,
			ID: "rev-" + kind, AcceptanceID: "acc-t08", OwnerID: "owner-1",
			ChangeKind: kind, MakerApproved: true, OwnerApproved: false,
		})
		if e != nil {
			t.Fatal(e)
		}
		if rev.OwnerApproved {
			t.Fatal("maker alone must not set owner approval")
		}
		if !rev.InvalidatesOld {
			t.Fatal("old evidence must be invalidated pending owner")
		}
		if !strings.Contains(rev.Detail, "maker_approval_insufficient") {
			t.Fatalf("detail: %s", rev.Detail)
		}
	}

	ok, e := s.ReviewOwnerChange("root-t08", contract.AcceptanceOwnerReview{
		SchemaVersion: contract.AcceptanceSchemaVersion,
		ID: "rev-owner", AcceptanceID: "acc-t08", OwnerID: "owner-1",
		ChangeKind: "legitimate_expectation", MakerApproved: true, OwnerApproved: true,
	})
	if e != nil {
		t.Fatal(e)
	}
	if !ok.OwnerApproved || !ok.InvalidatesOld {
		t.Fatalf("owner review must record and invalidate: %+v", ok)
	}
}

// TestV414T09 — behavior gate: unit-only and fabricated-log fail; genuine behavior passes.
func TestV414T09(t *testing.T) {
	s := accService(t)
	accRoot(t, s, "root-t09")
	pkg := samplePkg("acc-t09")
	pkg.RequiresBehaviorGate = true
	if e := s.RegisterAcceptancePackage(pkg); e != nil {
		t.Fatal(e)
	}
	if _, e := s.FreezeCandidate("root-t09", freezeReq("cand-t09", "root-t09", "acc-t09")); e != nil {
		t.Fatal(e)
	}
	iso := contract.IsolationCapability{Mode: contract.IsolationEnforced, Enforced: true, ContextProvenance: "present"}

	unitOnly, _, e := s.FinishCheck("root-t09", contract.RunCheckRequest{
		SchemaVersion: contract.AcceptanceSchemaVersion,
		ReceiptID: "rcpt-unit", CheckID: "behavior", CandidateID: "cand-t09",
		AcceptanceID: "acc-t09", EnvironmentID: "env-fixture",
		RunnerID: "runner-1", InvocationID: "inv-unit",
		ObservedOutcome: contract.OutcomePass, IsolationMode: contract.IsolationEnforced,
		BehaviorObserved: false, // unit-only / fabricated log
	}, iso)
	if e != nil {
		t.Fatal(e)
	}
	if unitOnly.Outcome != contract.OutcomeFail {
		t.Fatalf("unit-only must fail behavior gate: %s", unitOnly.Outcome)
	}

	genuine, _, e := s.FinishCheck("root-t09", contract.RunCheckRequest{
		SchemaVersion: contract.AcceptanceSchemaVersion,
		ReceiptID: "rcpt-beh", CheckID: "behavior", CandidateID: "cand-t09",
		AcceptanceID: "acc-t09", EnvironmentID: "env-fixture",
		RunnerID: "runner-1", InvocationID: "inv-beh",
		ObservedOutcome: contract.OutcomePass, IsolationMode: contract.IsolationEnforced,
		BehaviorObserved: true,
	}, iso)
	if e != nil {
		t.Fatal(e)
	}
	if genuine.Outcome != contract.OutcomePass {
		t.Fatalf("genuine behavior should pass: %s notes=%v", genuine.Outcome, genuine.Notes)
	}
}

// TestV414T10 — ambiguous brief/oracle / missing discriminator → definition blocker.
func TestV414T10(t *testing.T) {
	s := accService(t)
	accRoot(t, s, "root-t10")

	ambiguous := samplePkg("acc-t10a")
	ambiguous.RequestedBehavior = "ambiguous"
	ambiguous.BehavioralDiscriminator = "x"
	if e := s.RegisterAcceptancePackage(ambiguous); e != nil {
		t.Fatal(e)
	}
	b, e := s.AssessDefinition("root-t10", ambiguous, "block-brief")
	if e != nil {
		t.Fatal(e)
	}
	if b == nil || b.Kind != contract.BlockerAmbiguousBrief {
		t.Fatalf("expected ambiguous brief blocker: %+v", b)
	}

	oracle := samplePkg("acc-t10b")
	oracle.OracleOrigin = "ambiguous"
	oracle.BehavioralDiscriminator = "x"
	if e := s.RegisterAcceptancePackage(oracle); e != nil {
		t.Fatal(e)
	}
	b2, e := s.AssessDefinition("root-t10", oracle, "block-oracle")
	if e != nil {
		t.Fatal(e)
	}
	if b2 == nil || b2.Kind != contract.BlockerAmbiguousOracle {
		t.Fatalf("expected ambiguous oracle: %+v", b2)
	}

	missing := samplePkg("acc-t10c")
	missing.BehavioralDiscriminator = ""
	if e := s.RegisterAcceptancePackage(missing); e != nil {
		t.Fatal(e)
	}
	b3, e := s.AssessDefinition("root-t10", missing, "block-disc")
	if e != nil {
		t.Fatal(e)
	}
	if b3 == nil || b3.Kind != contract.BlockerMissingDiscriminator {
		t.Fatalf("expected missing discriminator: %+v", b3)
	}

	// Clear package → no blocker, no silent invention/weakening.
	clear := samplePkg("acc-t10d")
	if e := s.RegisterAcceptancePackage(clear); e != nil {
		t.Fatal(e)
	}
	b4, e := s.AssessDefinition("root-t10", clear, "block-none")
	if e != nil {
		t.Fatal(e)
	}
	if b4 != nil {
		t.Fatalf("clear package must not invent blocker: %+v", b4)
	}
}

// Ensure protected dir cleanup works on unix.
func TestV414IsolationCleanup(t *testing.T) {
	base := t.TempDir()
	b, e := NewIsolationBoundary(base, contract.IsolationEnforced)
	if e != nil {
		t.Fatal(e)
	}
	if e := b.Release(); e != nil {
		t.Fatal(e)
	}
	// After release, writes succeed again.
	p := filepath.Join(b.ProtectedDir, "journal.jsonl")
	if e := os.WriteFile(p, []byte("post"), 0o600); e != nil {
		t.Fatal(e)
	}
}
