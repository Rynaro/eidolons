package controller

import (
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
)

func dispService(t *testing.T) *Service {
	t.Helper()
	s := New(t.TempDir(), Options{Timeout: time.Second, Clock: func() time.Time {
		return time.Date(2026, 9, 22, 16, 0, 0, 0, time.UTC)
	}})
	if e := s.Init(); e != nil {
		t.Fatal(e)
	}
	if e := s.EnsureDispatchNamespaces(); e != nil {
		t.Fatal(e)
	}
	return s
}

func dispRoot(t *testing.T, s *Service, id string) {
	t.Helper()
	if e := s.InitRoot(id); e != nil {
		t.Fatal(e)
	}
}

func dispCeilings() []contract.Ceiling {
	return allCeilings(100, 100, 100, 100, 10)
}

func baseDispatch(intentID, root, op string) contract.AdmitDispatchRequest {
	return contract.AdmitDispatchRequest{
		IntentID: intentID, RootID: root, OperationID: op,
		TupleID: contract.QualifiedDispatchTupleID,
		Method:  contract.QualifiedDispatchMethod,
		RequestedGranularity: contract.GranularityRequest,
		Requested: contract.RequestedSettings{
			Model: "requested-model", Effort: "high", Method: contract.QualifiedDispatchMethod,
		},
		Admit: baseAdmit("res-"+intentID, root, "proj-disp", "task-"+intentID, 10, dispCeilings()),
		OwnershipSessionID: "sess-" + intentID,
		OwnershipProcessID: "proc-" + intentID,
		OwnershipWorktree:  "wt-" + intentID,
		RecordedAt:         "2026-09-22T16:00:00Z",
	}
}

// TestV412T01 — commit reservation + intent before native send; faults on both sides of commit/send/ack.
func TestV412T01(t *testing.T) {
	s := dispService(t)
	dispRoot(t, s, "root-t01")
	counters := NewNativeMethodCounters()
	adapter := NewFakeNativeAdapter(counters)

	// Fail before commit → Start counter stays 0.
	req := baseDispatch("intent-before", "root-t01", "op-before")
	r, e := s.AdmitAndDispatch("root-t01", req, adapter, DispatchFaultBeforeCommit)
	if e != nil {
		t.Fatal(e)
	}
	if r.Admitted || r.NativeSent {
		t.Fatalf("before-commit should reject without send: %+v", r)
	}
	if counters.Snapshot().Start != 0 {
		t.Fatalf("native send preceded durable intent: start=%d", counters.Snapshot().Start)
	}

	// Fail after commit before send → intent committed, Start still 0.
	req2 := baseDispatch("intent-after-commit", "root-t01", "op-after-commit")
	r2, e := s.AdmitAndDispatch("root-t01", req2, adapter, DispatchFaultAfterCommit)
	if e == nil || !strings.Contains(e.Error(), "after_commit") {
		t.Fatalf("expected after-commit fault, got %v", e)
	}
	if !r2.Admitted || r2.Intent == nil || r2.Intent.Status != contract.IntentCommitted {
		t.Fatalf("intent must be durable before send: %+v", r2)
	}
	if counters.Snapshot().Start != 0 {
		t.Fatalf("send must not run after commit fault: start=%d", counters.Snapshot().Start)
	}

	// Fail after send before ack → uncertain; Start == 1.
	req3 := baseDispatch("intent-after-send", "root-t01", "op-after-send")
	r3, e := s.AdmitAndDispatch("root-t01", req3, adapter, DispatchFaultAfterSend)
	if e == nil || !strings.Contains(e.Error(), "after_send") {
		t.Fatalf("expected after-send fault, got %v", e)
	}
	if r3.Intent == nil || r3.Intent.Status != contract.IntentUncertain {
		t.Fatalf("expected uncertain after send/ack gap: %+v", r3)
	}
	if counters.Snapshot().Start != 1 {
		t.Fatalf("exactly one send expected, got %d", counters.Snapshot().Start)
	}

	// Happy path + after-ack fault still records ack.
	req4 := baseDispatch("intent-ok", "root-t01", "op-ok")
	r4, e := s.AdmitAndDispatch("root-t01", req4, adapter, DispatchFaultAfterAck)
	if e == nil || !strings.Contains(e.Error(), "after_ack") {
		t.Fatalf("expected after-ack fault, got %v", e)
	}
	if r4.Intent == nil || r4.Intent.Status != contract.IntentAcked {
		t.Fatalf("ack must be recorded: %+v", r4)
	}
	if r4.Intent.CommittedAt == "" || r4.Intent.SentAt == "" || r4.Intent.AckedAt == "" {
		t.Fatalf("missing durable timestamps: %+v", r4.Intent)
	}
}

// TestV412T02 — ambiguous outcome → reconcile existing intent before redispatch.
func TestV412T02(t *testing.T) {
	s := dispService(t)
	dispRoot(t, s, "root-t02")
	adapter := NewFakeNativeAdapter(NewNativeMethodCounters())

	req := baseDispatch("intent-t02", "root-t02", "op-t02")
	r, e := s.AdmitAndDispatch("root-t02", req, adapter, DispatchFaultAfterSend)
	if e == nil {
		t.Fatal("expected after-send fault")
	}
	if r.Intent == nil || r.Intent.Status != contract.IntentUncertain {
		t.Fatalf("need uncertain intent: %+v", r)
	}

	// Lookup-capable host resolves without auto-redispatch.
	rec, e := s.ReconcileDispatch("root-t02", contract.ReconcileDispatchRequest{
		IntentID: "intent-t02", RootID: "root-t02", RecordedAt: "2026-09-22T16:01:00Z",
		AllowRedispatch: true,
	}, adapter)
	if e != nil {
		t.Fatal(e)
	}
	if rec.Status != contract.ReconcileResolved || rec.Redispatched {
		t.Fatalf("lookup must resolve without auto-redispatch: %+v", rec)
	}

	// Unsupported lookup remains unknown (not auto-retry).
	s2 := dispService(t)
	dispRoot(t, s2, "root-t02b")
	adapter2 := NewFakeNativeAdapter(NewNativeMethodCounters())
	adapter2.LookupEnabled = false
	req2 := baseDispatch("intent-t02b", "root-t02b", "op-t02b")
	_, _ = s2.AdmitAndDispatch("root-t02b", req2, adapter2, DispatchFaultAfterSend)
	rec2, e := s2.ReconcileDispatch("root-t02b", contract.ReconcileDispatchRequest{
		IntentID: "intent-t02b", RootID: "root-t02b", RecordedAt: "2026-09-22T16:02:00Z",
	}, adapter2)
	if e != nil {
		t.Fatal(e)
	}
	if rec2.Status != contract.ReconcileUnsupported || rec2.Redispatched {
		t.Fatalf("unsupported lookup must remain unknown: %+v", rec2)
	}
	if rec2.Intent == nil || rec2.Intent.Status != contract.IntentUncertain {
		t.Fatalf("intent stays uncertain: %+v", rec2.Intent)
	}
}

// TestV412T03 — observed values recorded separately from requested settings.
func TestV412T03(t *testing.T) {
	s := dispService(t)
	dispRoot(t, s, "root-t03")
	adapter := NewFakeNativeAdapter(NewNativeMethodCounters())
	req := baseDispatch("intent-t03", "root-t03", "op-t03")
	r, e := s.AdmitAndDispatch("root-t03", req, adapter, DispatchFaultNone)
	if e != nil || !r.Admitted {
		t.Fatalf("dispatch: %+v %v", r, e)
	}
	if r.Intent.Requested.Model != "requested-model" {
		t.Fatalf("requested model lost: %+v", r.Intent.Requested)
	}
	if r.Intent.Observed.Model == "" || r.Intent.Observed.Model == r.Intent.Requested.Model {
		t.Fatalf("observed must differ from ignored requested model: %+v", r.Intent.Observed)
	}
	if r.Intent.Observed.Effort == r.Intent.Requested.Effort {
		t.Fatalf("observed effort should reflect host ignore: %+v", r.Intent.Observed)
	}

	ev := contract.NativeEvent{
		SchemaVersion: contract.DispatchSchemaVersion, ID: "ev-1", IntentID: "intent-t03",
		OperationID: "op-t03", Sequence: 1, Kind: "usage",
		Requested: r.Intent.Requested, Observed: r.Intent.Observed,
		ChildUsageGap: true, RecordedAt: "2026-09-22T16:03:00Z",
	}
	if _, e := s.RecordDispatchEvent("root-t03", ev); e != nil {
		t.Fatal(e)
	}
	dup := ev
	dup.ID = "ev-1-dup"
	dup.DuplicateOf = "ev-1"
	dup.Sequence = 2
	if _, e := s.RecordDispatchEvent("root-t03", dup); e != nil {
		t.Fatal(e)
	}
	term := contract.NativeEvent{
		SchemaVersion: contract.DispatchSchemaVersion, ID: "ev-term", IntentID: "intent-t03",
		OperationID: "op-t03", Sequence: 3, Kind: "terminal",
		Requested: r.Intent.Requested, Observed: r.Intent.Observed,
		TransportTerminal: true, TerminalError: "host_error",
		AcceptanceClaim: false, RecordedAt: "2026-09-22T16:03:01Z",
	}
	if _, e := s.RecordDispatchEvent("root-t03", term); e != nil {
		t.Fatal(e)
	}
	term.AcceptanceClaim = true
	if _, e := s.RecordDispatchEvent("root-t03", term); e == nil {
		t.Fatal("transport event must not claim acceptance")
	}
	events, e := s.DispatchEvents("root-t03", "intent-t03")
	if e != nil {
		t.Fatal(e)
	}
	if len(events) < 3 {
		t.Fatalf("expected events including duplicate and terminal, got %d", len(events))
	}
	foundGap, foundDup, foundTerm := false, false, false
	for _, x := range events {
		if x.ChildUsageGap {
			foundGap = true
		}
		if x.DuplicateOf != "" {
			foundDup = true
		}
		if x.TransportTerminal && x.TerminalError != "" && !x.AcceptanceClaim {
			foundTerm = true
		}
	}
	if !foundGap || !foundDup || !foundTerm {
		t.Fatalf("missing event facets gap=%v dup=%v term=%v", foundGap, foundDup, foundTerm)
	}
}

// TestV412T04 — cancellation stays nonterminal until native outcome established.
func TestV412T04(t *testing.T) {
	s := dispService(t)
	dispRoot(t, s, "root-t04")
	adapter := NewFakeNativeAdapter(NewNativeMethodCounters())
	adapter.SetLiveProcess(true)
	req := baseDispatch("intent-t04", "root-t04", "op-t04")
	if _, e := s.AdmitAndDispatch("root-t04", req, adapter, DispatchFaultNone); e != nil {
		t.Fatal(e)
	}

	intent, e := s.CancelDispatch("root-t04", contract.CancelDispatchRequest{
		IntentID: "intent-t04", RootID: "root-t04", RecordedAt: "2026-09-22T16:04:00Z",
	}, adapter)
	if e != nil {
		t.Fatal(e)
	}
	if intent.Cancel.State != contract.CancelInterruptAccepted {
		t.Fatalf("expected interrupt accepted, got %s", intent.Cancel.State)
	}
	if intent.Cancel.IsTerminal() {
		t.Fatal("accepted interrupt with live process must remain nonterminal")
	}
	if !intent.Cancel.ProcessAlive || !intent.Cancel.UsageDelayed {
		t.Fatalf("live process + delayed usage expected: %+v", intent.Cancel)
	}

	// Missing ack path: interrupt failure keeps CancelRequested nonterminal.
	s2 := dispService(t)
	dispRoot(t, s2, "root-t04b")
	adapter2 := NewFakeNativeAdapter(NewNativeMethodCounters())
	req2 := baseDispatch("intent-t04b", "root-t04b", "op-t04b")
	if _, e := s2.AdmitAndDispatch("root-t04b", req2, adapter2, DispatchFaultNone); e != nil {
		t.Fatal(e)
	}
	adapter2.interruptFail = errors.New("ack missing")
	intent2, e := s2.CancelDispatch("root-t04b", contract.CancelDispatchRequest{
		IntentID: "intent-t04b", RootID: "root-t04b", RecordedAt: "2026-09-22T16:04:01Z",
	}, adapter2)
	if e != nil {
		t.Fatal(e)
	}
	if intent2.Cancel.State != contract.CancelRequested || !intent2.Cancel.AckMissing {
		t.Fatalf("missing ack must stay requested/nonterminal: %+v", intent2.Cancel)
	}

	// Confirmed stop is a distinct control before final reconciliation.
	stopped, e := s.ConfirmDispatchStopped("root-t04", "intent-t04", "2026-09-22T16:04:02Z")
	if e != nil {
		t.Fatal(e)
	}
	if stopped.Cancel.State != contract.CancelConfirmedStopped {
		t.Fatalf("expected confirmed stopped: %+v", stopped.Cancel)
	}
	rec, e := s.ReconcileDispatch("root-t04", contract.ReconcileDispatchRequest{
		IntentID: "intent-t04", RootID: "root-t04", RecordedAt: "2026-09-22T16:04:03Z",
	}, adapter)
	if e != nil {
		t.Fatal(e)
	}
	if rec.Intent == nil || rec.Intent.Cancel.State != contract.CancelFinalReconciled {
		t.Fatalf("final reconciliation distinct from confirmed stop: %+v", rec.Intent.Cancel)
	}
}

// TestV412T05 — cleanup preserves unrelated processes/workspaces.
func TestV412T05(t *testing.T) {
	s := dispService(t)
	dispRoot(t, s, "root-t05")
	adapter := NewFakeNativeAdapter(NewNativeMethodCounters())
	req := baseDispatch("intent-t05", "root-t05", "op-t05")
	if _, e := s.AdmitAndDispatch("root-t05", req, adapter, DispatchFaultNone); e != nil {
		t.Fatal(e)
	}
	res, e := s.CleanupDispatch("root-t05", "intent-t05", adapter,
		[]string{"adj-sess"}, []string{"adj-proc"}, []string{"adj-wt"})
	if e != nil {
		t.Fatal(e)
	}
	if len(res.CleanedSessions) != 1 || res.CleanedSessions[0] != "sess-intent-t05" {
		t.Fatalf("owned session not cleaned: %+v", res)
	}
	if len(res.PreservedSessions) != 1 || res.PreservedSessions[0] != "adj-sess" {
		t.Fatalf("adjacent session not preserved: %+v", res)
	}
	if len(res.PreservedProcesses) != 1 || res.PreservedProcesses[0] != "adj-proc" {
		t.Fatalf("adjacent process not preserved: %+v", res)
	}
	if len(res.PreservedWorktrees) != 1 || res.PreservedWorktrees[0] != "adj-wt" {
		t.Fatalf("adjacent worktree not preserved: %+v", res)
	}
	if res.PermissionBoundary == "" || res.NetworkBoundary == "" {
		t.Fatalf("ownership/permission/network boundary required: %+v", res)
	}
}

// TestV412T06 — cannot enforce required control at requested granularity → preflight reject.
func TestV412T06(t *testing.T) {
	s := dispService(t)
	dispRoot(t, s, "root-t06")
	adapter := NewFakeNativeAdapter(NewNativeMethodCounters())
	// Turn-only enforcement cannot satisfy request-level limits.
	adapter.EnforcedGranularityVal = contract.GranularityTurn
	req := baseDispatch("intent-t06", "root-t06", "op-t06")
	req.RequestedGranularity = contract.GranularityRequest
	r, e := s.AdmitAndDispatch("root-t06", req, adapter, DispatchFaultNone)
	if e != nil {
		t.Fatal(e)
	}
	if r.Admitted || r.NativeSent {
		t.Fatalf("granularity mismatch must preflight-reject: %+v", r)
	}
	joined := strings.Join(r.RejectReasons, ",")
	if !strings.Contains(joined, "granularity_unsupported") {
		t.Fatalf("expected granularity reject, got %v", r.RejectReasons)
	}
	if adapter.Counters.Snapshot().Start != 0 {
		t.Fatal("rejected preflight must not send")
	}

	// Version drift rejects.
	adapter2 := NewFakeNativeAdapter(NewNativeMethodCounters())
	adapter2.Version = "0.0.0-drift"
	req2 := baseDispatch("intent-t06b", "root-t06", "op-t06b")
	r2, e := s.AdmitAndDispatch("root-t06", req2, adapter2, DispatchFaultNone)
	if e != nil {
		t.Fatal(e)
	}
	if r2.Admitted || !strings.Contains(strings.Join(r2.RejectReasons, ","), "version_drift") {
		t.Fatalf("version drift must reject: %+v", r2)
	}

	// Downgrade requires a different operator request (turn granularity with turn-only adapter).
	adapter3 := NewFakeNativeAdapter(NewNativeMethodCounters())
	adapter3.EnforcedGranularityVal = contract.GranularityTurn
	req3 := baseDispatch("intent-t06c", "root-t06", "op-t06c")
	req3.RequestedGranularity = contract.GranularityTurn
	r3, e := s.AdmitAndDispatch("root-t06", req3, adapter3, DispatchFaultNone)
	if e != nil || !r3.Admitted {
		t.Fatalf("matching downgraded request must succeed: %+v %v", r3, e)
	}
}

// TestV412T07 — retry/replay reuses original operation identity; no duplicate effect.
func TestV412T07(t *testing.T) {
	s := dispService(t)
	dispRoot(t, s, "root-t07")
	adapter := NewFakeNativeAdapter(NewNativeMethodCounters())
	req := baseDispatch("intent-t07", "root-t07", "op-t07")
	req.IdempotencyKey = "idem-t07"
	r, e := s.AdmitAndDispatch("root-t07", req, adapter, DispatchFaultAfterSend)
	if e == nil {
		t.Fatal("expected after-send fault")
	}
	_ = r
	if adapter.EffectCount() != 1 {
		t.Fatalf("expected one remote effect, got %d", adapter.EffectCount())
	}
	// Replay same key/operation — must not duplicate effect.
	r2, e := s.ReplayDispatch("root-t07", req, adapter)
	if e != nil {
		// First attempt crashed after send; replay may complete ack without new effect.
		if r2.Intent == nil && adapter.EffectCount() != 1 {
			t.Fatalf("replay failed unexpectedly: %v", e)
		}
	}
	if adapter.EffectCount() != 1 {
		t.Fatalf("same key must not duplicate effect: count=%d", adapter.EffectCount())
	}
	starts := adapter.Counters.Snapshot().Start
	if starts < 2 {
		t.Fatalf("replay should invoke Start for idempotent reuse, got %d", starts)
	}

	// No lookup/key support → unresolved.
	s2 := dispService(t)
	dispRoot(t, s2, "root-t07b")
	adapter2 := NewFakeNativeAdapter(NewNativeMethodCounters())
	adapter2.LookupEnabled = false
	adapter2.IdempotencyKeyEnabled = false
	req2 := baseDispatch("intent-t07b", "root-t07b", "op-t07b")
	r3, e := s2.ReplayDispatch("root-t07b", req2, adapter2)
	if e != nil {
		t.Fatal(e)
	}
	if r3.Admitted || !strings.Contains(strings.Join(r3.RejectReasons, ","), "no_lookup_or_idempotency") {
		t.Fatalf("unsupported idempotency must stay unresolved: %+v", r3)
	}
}

// TestV412T08 — method outside qualified set rejects; no privileged sibling fallback.
func TestV412T08(t *testing.T) {
	s := dispService(t)
	dispRoot(t, s, "root-t08")
	adapter := NewFakeNativeAdapter(NewNativeMethodCounters())

	bad := baseDispatch("intent-t08-bad", "root-t08", "op-t08-bad")
	bad.Method = "direct-exec"
	bad.Requested.Method = "direct-exec"
	r, e := s.AdmitAndDispatch("root-t08", bad, adapter, DispatchFaultNone)
	if e != nil {
		t.Fatal(e)
	}
	if r.Admitted || r.NativeSent {
		t.Fatalf("unqualified direct-exec must reject: %+v", r)
	}
	if !strings.Contains(strings.Join(r.RejectReasons, ","), "method_outside_qualified_set") {
		t.Fatalf("expected method reject: %v", r.RejectReasons)
	}

	fs := baseDispatch("intent-t08-fs", "root-t08", "op-t08-fs")
	fs.Method = "filesystem-write"
	fs.Requested.Method = "filesystem-write"
	r2, e := s.AdmitAndDispatch("root-t08", fs, adapter, DispatchFaultNone)
	if e != nil {
		t.Fatal(e)
	}
	if r2.Admitted {
		t.Fatalf("filesystem method cannot bypass sandboxed denial: %+v", r2)
	}
	if adapter.Counters.Snapshot().Start != 0 {
		t.Fatal("denied methods must not hit Start")
	}

	// Qualified operation is the positive control.
	ok := baseDispatch("intent-t08-ok", "root-t08", "op-t08-ok")
	r3, e := s.AdmitAndDispatch("root-t08", ok, adapter, DispatchFaultNone)
	if e != nil || !r3.Admitted || !r3.NativeSent {
		t.Fatalf("qualified method must succeed: %+v %v", r3, e)
	}
}

// TestV412T09 — durable session history unavailable → reconstruction report without native continuity.
func TestV412T09(t *testing.T) {
	s := dispService(t)
	dispRoot(t, s, "root-t09")
	adapter := NewFakeNativeAdapter(NewNativeMethodCounters())

	req := baseDispatch("intent-t09", "root-t09", "op-t09")
	req.LostNativeSession = true
	req.PortableCheckpointID = "ckpt-t09"
	r, e := s.AdmitAndDispatch("root-t09", req, adapter, DispatchFaultNone)
	if e != nil || !r.Admitted {
		t.Fatalf("portable reconstruction path: %+v %v", r, e)
	}
	if r.Intent == nil || r.Intent.Reconstruction == nil {
		t.Fatal("reconstruction report required")
	}
	rep := r.Intent.Reconstruction
	if rep.Kind != contract.ReconstructionPortable {
		t.Fatalf("expected portable reconstruction, got %s", rep.Kind)
	}
	if rep.ClaimsNativeContinuity {
		t.Fatal("must not claim native-session continuity")
	}
	if rep.ReconstructedInvocationID == "" || rep.ReconstructedInvocationID == req.OperationID {
		t.Fatalf("reconstructed invocation must be distinctly identified: %q", rep.ReconstructedInvocationID)
	}
	if rep.NativeSessionPresent {
		t.Fatal("lost session must report native_session_present=false")
	}

	// Missing reconstruction support remains blocked.
	s2 := dispService(t)
	dispRoot(t, s2, "root-t09b")
	adapter2 := NewFakeNativeAdapter(NewNativeMethodCounters())
	adapter2.ReconstructionEnabled = false
	req2 := baseDispatch("intent-t09b", "root-t09b", "op-t09b")
	req2.LostNativeSession = true
	req2.PortableCheckpointID = "ckpt-t09b"
	r2, e := s2.AdmitAndDispatch("root-t09b", req2, adapter2, DispatchFaultNone)
	if e != nil {
		t.Fatal(e)
	}
	if r2.Admitted {
		t.Fatalf("missing reconstruction support must block: %+v", r2)
	}
	if r2.Intent == nil || r2.Intent.Reconstruction == nil || r2.Intent.Reconstruction.Kind != contract.ReconstructionBlocked {
		t.Fatalf("expected reconstruction blocked: %+v", r2.Intent)
	}
}
