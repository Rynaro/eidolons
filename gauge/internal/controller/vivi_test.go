package controller

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
)

func viviService(t *testing.T) *Service {
	t.Helper()
	s := New(t.TempDir(), Options{Timeout: time.Second, Clock: func() time.Time {
		return time.Date(2026, 9, 22, 18, 30, 0, 0, time.UTC)
	}})
	if e := s.Init(); e != nil {
		t.Fatal(e)
	}
	if e := s.EnsureViviNamespaces(); e != nil {
		t.Fatal(e)
	}
	return s
}

func startViviSession(t *testing.T, s *Service, id string) contract.ViviSession {
	t.Helper()
	sess, e := s.StartViviSession(contract.ViviSession{
		ID: id, RootBudgetID: "budget-" + id,
	})
	if e != nil {
		t.Fatal(e)
	}
	return sess
}

// TestV417T01 — proposal-only control, user-tree escape, protected criteria,
// unrelated dirty work, and valid candidate edits (R01).
func TestV417T01(t *testing.T) {
	s := viviService(t)
	sess := startViviSession(t, s, "sess-t01")

	userTree := t.TempDir()
	candidate := filepath.Join(t.TempDir(), "candidate-ws")
	if e := os.MkdirAll(candidate, 0o700); e != nil {
		t.Fatal(e)
	}
	protected := filepath.Join(candidate, "oracle.yaml")
	if e := os.WriteFile(protected, []byte("criteria\n"), 0o600); e != nil {
		t.Fatal(e)
	}

	// Proposal-only control: direct edits rejected.
	po, e := s.SelectViviMode(contract.ViviModeSelection{
		ID: "mode-po", SessionID: sess.ID, Mode: contract.ViviModeProposalOnly,
	})
	if e != nil {
		t.Fatal(e)
	}
	if _, e = s.AttemptViviEdit(sess.ID, po.ID, filepath.Join(candidate, "x.go"), "x", false); e == nil {
		t.Fatal("proposal-only must reject direct edits")
	}

	cw, e := s.SelectViviMode(contract.ViviModeSelection{
		ID: "mode-cw", SessionID: sess.ID, Mode: contract.ViviModeCandidateWorkspace,
		ScopedAuthorization: true, AuthorizedWorkspace: candidate, UserTreeRoot: userTree,
		ProtectedPaths: []string{protected},
	})
	if e != nil {
		t.Fatal(e)
	}

	// Valid candidate edit.
	validPath := filepath.Join(candidate, "pkg", "f.go")
	ok, e := s.AttemptViviEdit(sess.ID, cw.ID, validPath, "package pkg\n", false)
	if e != nil {
		t.Fatal(e)
	}
	if ok.Outcome != contract.EditAccepted || ok.AppliedToUser {
		t.Fatalf("valid candidate edit: %+v", ok)
	}
	if _, e = os.Stat(validPath); e != nil {
		t.Fatal("candidate file missing", e)
	}
	// User tree must remain untouched.
	entries, _ := os.ReadDir(userTree)
	if len(entries) != 0 {
		t.Fatalf("user tree polluted: %v", entries)
	}

	// User-tree escape.
	escape := filepath.Join(userTree, "stolen.go")
	bad, e := s.AttemptViviEdit(sess.ID, cw.ID, escape, "bad", false)
	if e == nil || bad.Outcome != contract.EditRejectedUserTree {
		t.Fatalf("user-tree escape: %+v err=%v", bad, e)
	}
	if _, err := os.Stat(escape); !os.IsNotExist(err) {
		t.Fatal("escape must not write user tree")
	}

	// Protected criteria.
	prot, e := s.AttemptViviEdit(sess.ID, cw.ID, protected, "hacked", false)
	if e == nil || prot.Outcome != contract.EditRejectedProtected {
		t.Fatalf("protected: %+v err=%v", prot, e)
	}

	// Unrelated dirty work.
	dirty, e := s.AttemptViviEdit(sess.ID, cw.ID, filepath.Join(candidate, "ok.go"), "ok", true)
	if e == nil || dirty.Outcome != contract.EditRejectedUnrelated {
		t.Fatalf("unrelated dirty: %+v err=%v", dirty, e)
	}
}

// TestV417T02 — proposal-only returns proposal without applying; parent apply is separate (R02).
func TestV417T02(t *testing.T) {
	s := viviService(t)
	sess := startViviSession(t, s, "sess-t02")
	userTree := t.TempDir()

	mode, e := s.SelectViviMode(contract.ViviModeSelection{
		ID: "mode-po2", SessionID: sess.ID, Mode: contract.ViviModeProposalOnly,
	})
	if e != nil {
		t.Fatal(e)
	}
	prop, e := s.EmitViviProposal(sess.ID, mode.ID, "diff --git a/f.go\n+hello\n")
	if e != nil {
		t.Fatal(e)
	}
	if prop.AppliedToUserTree || !prop.StandaloneCompatible || prop.DiffDigest == "" {
		t.Fatalf("proposal: %+v", prop)
	}
	entries, _ := os.ReadDir(userTree)
	if len(entries) != 0 {
		t.Fatal("proposal must not touch user tree")
	}

	// Unauthorized apply rejected; tree still clean.
	app, e := s.ApplyViviProposal(sess.ID, prop.ID, false, filepath.Join(userTree, "f.go"))
	if e == nil || app.AppliedToUserTree || app.RejectedReason == "" {
		t.Fatalf("unauthorized apply: %+v err=%v", app, e)
	}
	entries, _ = os.ReadDir(userTree)
	if len(entries) != 0 {
		t.Fatal("unauthorized apply must leave user tree clean")
	}

	// Parent-authorized application is a separate operation.
	app, e = s.ApplyViviProposal(sess.ID, prop.ID, true, filepath.Join(userTree, "f.go"))
	if e != nil || !app.AppliedToUserTree || !app.ParentAuthorized {
		t.Fatalf("authorized apply: %+v err=%v", app, e)
	}
	if app.ID == prop.ID {
		t.Fatal("application must be a distinct operation identity")
	}
	if _, err := os.Stat(filepath.Join(userTree, "f.go")); err != nil {
		t.Fatal("authorized apply should write user tree")
	}
}

// TestV417T03 — warm/fresh continuity; resets recorded without resetting accounting (R03).
func TestV417T03(t *testing.T) {
	s := viviService(t)
	sess := startViviSession(t, s, "sess-t03")

	// Fresh fixture: continuity mode on, no warm history yet.
	fresh, e := s.InitViviContinuity(contract.ViviContinuityState{
		ID: "cont-fresh", SessionID: sess.ID, RootBudgetID: sess.RootBudgetID,
		ContinuityMode: true, WarmContext: false,
	})
	if e != nil {
		t.Fatal(e)
	}
	if fresh.WarmContext || fresh.RepairAttempts != 0 || !fresh.AccountingPreserved {
		t.Fatalf("fresh: %+v", fresh)
	}

	// Warm fixture retains decisions and failures across repairs.
	warm, e := s.InitViviContinuity(contract.ViviContinuityState{
		ID: "cont-warm", SessionID: sess.ID, RootBudgetID: sess.RootBudgetID,
		ContinuityMode: true, WarmContext: false,
	})
	if e != nil {
		t.Fatal(e)
	}
	warm, e = s.RecordViviRepairAttempt(warm.ID, "use-existing-helper", "compile_error: missing import")
	if e != nil {
		t.Fatal(e)
	}
	warm, e = s.RecordViviRepairAttempt(warm.ID, "add-import", "test_fail: assertion")
	if e != nil {
		t.Fatal(e)
	}
	if !warm.WarmContext || warm.RepairAttempts != 2 || len(warm.Decisions) != 2 || len(warm.FailureHistory) != 2 {
		t.Fatalf("warm repairs: %+v", warm)
	}
	budgetBefore := warm.RootBudgetID

	// Reset is recorded; accounting (root budget) preserved; history retained.
	warm, e = s.RecordViviContextReset(warm.ID, "fresh-worker-spawn")
	if e != nil {
		t.Fatal(e)
	}
	if warm.ContextResets != 1 || len(warm.ResetEvents) != 1 || !warm.AccountingPreserved {
		t.Fatalf("reset: %+v", warm)
	}
	if warm.RootBudgetID != budgetBefore {
		t.Fatal("reset must not create a new budget root")
	}
	if len(warm.Decisions) != 2 || len(warm.FailureHistory) != 2 {
		t.Fatal("continuity must retain decisions and failure history across reset")
	}
}

// TestV417T04 — maker rename/fork fails; separated checker only gets observed grade (R04).
func TestV417T04(t *testing.T) {
	s := viviService(t)
	sess := startViviSession(t, s, "sess-t04")

	renamed, e := s.SubmitViviVerification(contract.ViviVerificationSubmission{
		ID: "ver-rename", SessionID: sess.ID, CandidateID: "cand-1",
		MakerWorkerID: "maker-a", CheckerWorkerID: "maker-a-renamed",
		MakerRenamedAsChecker: true,
		EvidenceGrade: contract.EvidenceGradeIndependent,
		ObservedEvidenceGrade: contract.EvidenceGradeIndependent,
	})
	if e != nil {
		t.Fatal(e)
	}
	if !renamed.Rejected || renamed.EvidenceGrade == contract.EvidenceGradeIndependent {
		t.Fatalf("rename must fail independence: %+v", renamed)
	}

	forked, e := s.SubmitViviVerification(contract.ViviVerificationSubmission{
		ID: "ver-fork", SessionID: sess.ID, CandidateID: "cand-1",
		MakerWorkerID: "maker-a", CheckerWorkerID: "maker-a-fork",
		MakerForkedAsChecker: true,
	})
	if e != nil {
		t.Fatal(e)
	}
	if !forked.Rejected {
		t.Fatalf("fork must fail: %+v", forked)
	}

	// Separated recorded checker — only the actually observed grade.
	sep, e := s.SubmitViviVerification(contract.ViviVerificationSubmission{
		ID: "ver-sep", SessionID: sess.ID, CandidateID: "cand-1",
		MakerWorkerID: "maker-a", CheckerWorkerID: "checker-b",
		ObservedEvidenceGrade: contract.EvidenceGradeSeparated,
		EvidenceGrade:         contract.EvidenceGradeSeparated,
	})
	if e != nil {
		t.Fatal(e)
	}
	if sep.Rejected || !sep.ControllerManaged || sep.EvidenceGrade != contract.EvidenceGradeSeparated {
		t.Fatalf("separated checker: %+v", sep)
	}

	overclaim, e := s.SubmitViviVerification(contract.ViviVerificationSubmission{
		ID: "ver-over", SessionID: sess.ID, CandidateID: "cand-1",
		MakerWorkerID: "maker-a", CheckerWorkerID: "checker-b",
		ObservedEvidenceGrade: contract.EvidenceGradeSeparated,
		EvidenceGrade:         contract.EvidenceGradeIndependent,
	})
	if e != nil {
		t.Fatal(e)
	}
	if !overclaim.Rejected || overclaim.EvidenceGrade != contract.EvidenceGradeSeparated {
		t.Fatalf("overclaim must clamp to observed: %+v", overclaim)
	}
}

// TestV417T05 — novel architecture, push/deploy, external spend, expanded scope (R05).
func TestV417T05(t *testing.T) {
	s := viviService(t)
	sess := startViviSession(t, s, "sess-t05")

	cases := []struct {
		task     string
		boundary string
	}{
		{"design novel architecture from scratch", contract.BoundaryNovelArchitecture},
		{"push and deploy to production", contract.BoundaryPushDeploy},
		{"authorize external spend on paid API", contract.BoundaryExternalSpend},
		{"expand scope beyond the accepted charter", contract.BoundaryExpandedScope},
		{"greenfield product creation", contract.BoundaryGreenfield},
		{"grant publication of the sibling methodology", contract.BoundaryPublication},
	}
	for i, tc := range cases {
		b, e := s.RefuseViviBoundary(sess.ID, tc.task, []string{"compose-atlas", "compose-ramza"})
		if e != nil {
			t.Fatalf("case %d: %v", i, e)
		}
		if b.Boundary != tc.boundary || !b.Refused || b.EvadedViaComposition {
			t.Fatalf("case %d: %+v", i, b)
		}
		if len(b.MethodComposition) == 0 {
			t.Fatalf("composition should be recorded without evasion: %+v", b)
		}
	}

	// In-scope brownfield task is not a boundary refusal.
	if _, e := s.RefuseViviBoundary(sess.ID, "fix brownfield helper in existing package", nil); e == nil {
		t.Fatal("in-scope task must not refuse")
	}
}

// TestV417T06 — continue, native compaction, fresh-worker; unsupported compaction unknown (R06).
func TestV417T06(t *testing.T) {
	s := viviService(t)
	sess := startViviSession(t, s, "sess-t06")

	cont, e := s.SelectViviContextStrategy(contract.ViviContextStrategyRecord{
		ID: "ctx-continue", SessionID: sess.ID,
		Strategy: contract.ContextStrategyContinue,
		HostCompactionSupport: "unknown",
		TransitionBoundary: contract.ContextTransitionObserved,
		ClaimedCompleted: true,
	})
	if e != nil {
		t.Fatal(e)
	}
	if cont.StrategyVersion == "" || cont.TransitionBoundary != contract.ContextTransitionObserved {
		t.Fatalf("continue: %+v", cont)
	}

	fresh, e := s.SelectViviContextStrategy(contract.ViviContextStrategyRecord{
		ID: "ctx-fresh", SessionID: sess.ID,
		Strategy: contract.ContextStrategyFreshWorker,
		HostCompactionSupport: "unknown",
		TransitionBoundary: contract.ContextTransitionObserved,
		ClaimedCompleted: true,
	})
	if e != nil {
		t.Fatal(e)
	}
	if fresh.Strategy != contract.ContextStrategyFreshWorker {
		t.Fatalf("fresh-worker: %+v", fresh)
	}

	native, e := s.SelectViviContextStrategy(contract.ViviContextStrategyRecord{
		ID: "ctx-native", SessionID: sess.ID,
		Strategy: contract.ContextStrategyNativeCompaction,
		HostCompactionSupport: "supported",
		TransitionBoundary: contract.ContextTransitionObserved,
		ClaimedCompleted: true,
	})
	if e != nil {
		t.Fatal(e)
	}
	if !native.ClaimedCompleted {
		t.Fatalf("supported native compaction: %+v", native)
	}

	// Unsupported host compaction is unknown, not claimed completed.
	unsup, e := s.SelectViviContextStrategy(contract.ViviContextStrategyRecord{
		ID: "ctx-unsup", SessionID: sess.ID,
		Strategy: contract.ContextStrategyNativeCompaction,
		HostCompactionSupport: "unsupported",
		TransitionBoundary: contract.ContextTransitionObserved, // controller must rewrite
		ClaimedCompleted: true,
	})
	if e != nil {
		t.Fatal(e)
	}
	if unsup.TransitionBoundary != contract.ContextTransitionUnknown || unsup.ClaimedCompleted {
		t.Fatalf("unsupported must be unknown not completed: %+v", unsup)
	}
}
