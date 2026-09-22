package contract_test

import (
	"testing"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
)

func known(n float64) *float64 { return &n }

func attempt(arm, task, id string, terminal, acceptance string, costKind string, amount *float64) contract.AttemptRecord {
	return contract.AttemptRecord{
		SchemaVersion: contract.InstrumentSchemaVersion,
		ID: id, TrialID: "trial-1", ProtocolID: "proto-1", ProtocolDigest: "digest-1",
		ArmID: arm, ArmKind: contract.ArmNative, TaskRootID: task, AttemptID: id,
		InvocationRef: "inv-1", ConfigRef: "cfg-1", EnvironmentRef: "env-1",
		TerminalState: terminal, Acceptance: acceptance,
		AcceptanceEvidence: func() string {
			if acceptance == contract.AcceptanceAccepted {
				return "oracle-pass"
			}
			return ""
		}(),
		CostKind: costKind, CostAmount: amount, CostUnit: "fixture-unit",
		ResourceCoverage: []string{"inference"},
		StartedAt: "2026-09-22T12:00:00Z", EndedAt: "2026-09-22T12:00:01Z",
	}
}

func TestV409ArithmeticVectorK(t *testing.T) {
	// K: costs 2,3,1,4 total10; 2 accepted → 5/accepted; replay acceptance does not inflate.
	recs := []contract.AttemptRecord{
		attempt("native", "task-a", "a1", contract.TerminalFailed, contract.AcceptanceNone, contract.CostKnown, known(2)),
		attempt("native", "task-a", "a2", contract.TerminalCompleted, contract.AcceptanceAccepted, contract.CostKnown, known(3)),
		attempt("native", "task-b", "b1", contract.TerminalCancelled, contract.AcceptanceNone, contract.CostKnown, known(1)),
		attempt("native", "task-b", "b2", contract.TerminalCompleted, contract.AcceptanceAccepted, contract.CostKnown, known(4)),
	}
	sum, e := contract.SummarizeAttempts(recs)
	if e != nil {
		t.Fatal(e)
	}
	if sum.AttemptCount != 4 || !sum.KnownCompleteKnown || sum.KnownCompleteTotal == nil || *sum.KnownCompleteTotal != 10 {
		t.Fatalf("K totals: %+v", sum)
	}
	if sum.AcceptedDistinctRoots != 2 || !sum.RatioDefined || sum.CostPerAccepted == nil || *sum.CostPerAccepted != 5 {
		t.Fatalf("K ratio: %+v", sum)
	}
	// Replay acceptance notification for task A — still 2 distinct roots.
	replay := attempt("native", "task-a", "a2-replay", contract.TerminalCompleted, contract.AcceptanceAccepted, contract.CostKnown, known(0))
	sum2, e := contract.SummarizeAttempts(append(recs, replay))
	if e != nil {
		t.Fatal(e)
	}
	if sum2.AcceptedDistinctRoots != 2 {
		t.Fatalf("replay inflated accepted roots: %d", sum2.AcceptedDistinctRoots)
	}
}

func TestV409ArithmeticVectorZ(t *testing.T) {
	recs := []contract.AttemptRecord{
		attempt("native", "task-a", "a1", contract.TerminalFailed, contract.AcceptanceNone, contract.CostKnown, known(2)),
		attempt("native", "task-a", "a2", contract.TerminalCancelled, contract.AcceptanceNone, contract.CostKnown, known(1)),
		attempt("native", "task-b", "b1", contract.TerminalAbandoned, contract.AcceptanceNone, contract.CostKnown, known(3)),
	}
	sum, e := contract.SummarizeAttempts(recs)
	if e != nil {
		t.Fatal(e)
	}
	if sum.AttemptCount != 3 || !sum.KnownCompleteKnown || *sum.KnownCompleteTotal != 6 {
		t.Fatalf("Z totals: %+v", sum)
	}
	if sum.AcceptedDistinctRoots != 0 || sum.RatioDefined || sum.CostPerAccepted != nil {
		t.Fatalf("Z ratio must be undefined: %+v", sum)
	}
}

func TestV409ArithmeticVectorU(t *testing.T) {
	recs := []contract.AttemptRecord{
		attempt("native", "task-a", "a1", contract.TerminalFailed, contract.AcceptanceNone, contract.CostKnown, known(2)),
		attempt("native", "task-a", "a2", contract.TerminalCompleted, contract.AcceptanceAccepted, contract.CostUnknown, nil),
		attempt("native", "task-b", "b1", contract.TerminalAbandoned, contract.AcceptanceNone, contract.CostKnown, known(3)),
	}
	sum, e := contract.SummarizeAttempts(recs)
	if e != nil {
		t.Fatal(e)
	}
	if sum.AttemptCount != 3 || sum.KnownSubtotal != 5 || !sum.TotalUnknown {
		t.Fatalf("U subtotal: %+v", sum)
	}
	if sum.RatioDefined || !sum.RatioUnknown {
		t.Fatalf("U ratio must be unknown: %+v", sum)
	}
	if sum.AcceptedDistinctRoots != 1 {
		t.Fatalf("U accepted roots: %d", sum.AcceptedDistinctRoots)
	}
}

func TestV409ArithmeticVectorW(t *testing.T) {
	ratio, e := contract.WeightedRatio([]contract.WeightedGroup{
		{Total: 2, AcceptedRoots: 1},
		{Total: 18, AcceptedRoots: 3},
	})
	if e != nil {
		t.Fatal(e)
	}
	if ratio != 5 {
		t.Fatalf("W expected 20/4=5, got %v (not unweighted mean 4)", ratio)
	}
}

func TestV409ArithmeticNativeV3ShareSchema(t *testing.T) {
	mk := func(kind string) []contract.AttemptRecord {
		return []contract.AttemptRecord{
			{
				SchemaVersion: contract.InstrumentSchemaVersion, ID: "x1", TrialID: "t", ProtocolID: "p", ProtocolDigest: "d",
				ArmID: kind, ArmKind: kind, TaskRootID: "task-a", AttemptID: "x1",
				InvocationRef: "i", ConfigRef: "c", EnvironmentRef: "e",
				TerminalState: contract.TerminalFailed, Acceptance: contract.AcceptanceNone,
				CostKind: contract.CostKnown, CostAmount: known(2), CostUnit: "u",
				ResourceCoverage: []string{"inference"}, StartedAt: "2026-09-22T12:00:00Z", EndedAt: "2026-09-22T12:00:01Z",
			},
			{
				SchemaVersion: contract.InstrumentSchemaVersion, ID: "x2", TrialID: "t", ProtocolID: "p", ProtocolDigest: "d",
				ArmID: kind, ArmKind: kind, TaskRootID: "task-a", AttemptID: "x2",
				InvocationRef: "i", ConfigRef: "c", EnvironmentRef: "e",
				TerminalState: contract.TerminalCompleted, Acceptance: contract.AcceptanceAccepted, AcceptanceEvidence: "oracle",
				CostKind: contract.CostKnown, CostAmount: known(3), CostUnit: "u",
				ResourceCoverage: []string{"inference"}, StartedAt: "2026-09-22T12:00:00Z", EndedAt: "2026-09-22T12:00:01Z",
			},
		}
	}
	n, e := contract.SummarizeAttempts(mk(contract.ArmNative))
	if e != nil {
		t.Fatal(e)
	}
	v, e := contract.SummarizeAttempts(mk(contract.ArmOriginalV3))
	if e != nil {
		t.Fatal(e)
	}
	if *n.KnownCompleteTotal != *v.KnownCompleteTotal || *n.CostPerAccepted != *v.CostPerAccepted {
		t.Fatalf("native/v3 arithmetic diverged: %+v vs %+v", n, v)
	}
}
