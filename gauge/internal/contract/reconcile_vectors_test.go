package contract_test

import (
	"encoding/json"
	"os"
	"testing"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
)

func TestV408T04IndependentVectors(t *testing.T) {
	// Port of /private/tmp/v4-08-review-probes/vectors.json — independent arithmetic, not production output.
	type vec struct {
		ID       string `json:"id"`
		Expected struct {
			State                    string   `json:"state"`
			Total                    *float64 `json:"total"`
			AfterIdenticalCorrection *float64 `json:"after_identical_correction_replay"`
			CurrentTotal             *float64 `json:"current_total"`
			HistoricalSnapshot       *float64 `json:"historical_snapshot"`
			PrefixConsumption        *float64 `json:"prefix_consumption"`
			ChildBreakdown           *float64 `json:"child_breakdown"`
			ParentTotal              *float64 `json:"parent_total"`
			ChildTotal               *float64 `json:"child_total"`
			CombinedTotal            *float64 `json:"combined_total"`
			ReplacementContribution  *float64 `json:"replacement_contribution"`
			AmountDecimal            string   `json:"amount_decimal"`
			KnownSubtotalRational    string   `json:"known_subtotal_rational"`
		} `json:"expected"`
	}

	// F01: deltas 3+4+5+2 with prefix through3=12 => total 14
	{
		in := contract.ReconcileInput{Atoms: map[string]float64{"d1": 3, "d2": 4, "d3": 5, "d4": 2}, PrefixValue: fptr(12), PrefixVersions: []string{"d1:v0", "d2:v0", "d3:v0"}, PrefixEnd: 3}
		r := contract.Reconcile(in)
		if !r.TotalKnown || r.State != contract.TotalKnown || *r.Total != 14 {
			t.Fatalf("F01: got state=%s total=%v", r.State, r.Total)
		}
	}
	// F02: correction d4 2→1 => 13; replay stays 13
	{
		in := contract.ReconcileInput{Atoms: map[string]float64{"d1": 3, "d2": 4, "d3": 5, "d4": 1}}
		r := contract.Reconcile(in)
		if !r.TotalKnown || *r.Total != 13 {
			t.Fatalf("F02: %v", r)
		}
		in.Corrections = []contract.CorrectionStep{{ID: "c4", Target: "d4:v0", Old: 2, New: 1, Version: "d4:v1", AdditiveProof: true, CoveredVersions: []string{"d4:v0"}}}
		// Without prefix, correction just sets atom — already 1
		r2 := contract.Reconcile(in)
		if !r2.TotalKnown || *r2.Total != 13 {
			t.Fatalf("F02 replay: %v", r2)
		}
	}
	// F03: incorporating prefix through4=13; late prefix through2=7 adds nothing
	{
		in := contract.ReconcileInput{
			Atoms:         map[string]float64{"d1": 3, "d2": 4, "d3": 5, "d4": 1},
			Incorporating: &contract.PrefixRecord{End: 4, Value: 13, Versions: []string{"d1:v0", "d2:v0", "d3:v0", "d4:v1"}, IncorporatesCorr: true},
			LatePrefixes:  []contract.PrefixRecord{{End: 2, Value: 7, Versions: []string{"d1:v0", "d2:v0"}, Late: true}},
		}
		r := contract.Reconcile(in)
		if !r.TotalKnown || *r.Total != 13 {
			t.Fatalf("F03: %v", r)
		}
	}
	// C01: late-prefix correction 12-4+2=10 with additive proof + covered version
	{
		in := contract.ReconcileInput{
			PrefixValue: fptr(12),
			Corrections: []contract.CorrectionStep{{
				ID: "c1", Target: "d2:v0", Old: 4, New: 2, Version: "d2:v1",
				AdditiveProof: true, CoveredVersions: []string{"d2:v0"},
			}},
		}
		r := contract.Reconcile(in)
		if !r.TotalKnown || *r.Total != 10 {
			t.Fatalf("C01: %v", r)
		}
	}
	// C02: missing covered version => unknown; historical 12 retained
	{
		in := contract.ReconcileInput{
			PrefixValue: fptr(12),
			Corrections: []contract.CorrectionStep{{
				ID: "c2", Target: "d2:v0", Old: 4, New: 2, Version: "d2:v1",
				AdditiveProof: true, CoveredVersions: nil,
			}},
		}
		r := contract.Reconcile(in)
		if r.TotalKnown || r.State != contract.TotalUnknown || r.HistoricalSnapshot == nil || *r.HistoricalSnapshot != 12 {
			t.Fatalf("C02: %v", r)
		}
	}
	// C03: additive proof false => unknown
	{
		in := contract.ReconcileInput{
			PrefixValue: fptr(12),
			Corrections: []contract.CorrectionStep{{
				ID: "c3", Target: "d2:v0", Old: 4, New: 2, Version: "d2:v1",
				AdditiveProof: false, CoveredVersions: []string{"d2:v0"},
			}},
		}
		r := contract.Reconcile(in)
		if r.TotalKnown || r.HistoricalSnapshot == nil || *r.HistoricalSnapshot != 12 {
			t.Fatalf("C03: %v", r)
		}
	}
	// C04: chain 4→2→6 over prefix 12 => 14
	{
		in := contract.ReconcileInput{
			PrefixValue: fptr(12),
			Corrections: []contract.CorrectionStep{
				{ID: "c4a", Target: "d2:v0", Old: 4, New: 2, Version: "d2:v1", AdditiveProof: true, CoveredVersions: []string{"d2:v0"}},
				{ID: "c4b", Target: "d2:v1", Old: 2, New: 6, Version: "d2:v2", AdditiveProof: true, CoveredVersions: []string{"d2:v1"}},
			},
		}
		r := contract.Reconcile(in)
		if !r.TotalKnown || *r.Total != 14 {
			t.Fatalf("C04: %v", r)
		}
	}
	// C05: incorporating snapshot 10 after correction — no second subtraction
	{
		in := contract.ReconcileInput{
			PrefixValue:   fptr(12),
			Incorporating: &contract.PrefixRecord{Value: 10, Versions: []string{"d1:v0", "d2:v1", "d3:v0"}, IncorporatesCorr: true},
			Corrections: []contract.CorrectionStep{{
				ID: "c5", Target: "d2:v0", Old: 4, New: 2, AdditiveProof: true, CoveredVersions: []string{"d2:v0"},
			}},
		}
		r := contract.Reconcile(in)
		if !r.TotalKnown || *r.Total != 10 {
			t.Fatalf("C05: %v", r)
		}
	}
	// C06: missing target pending, replacement contribution 0 to combined total
	{
		r := contract.Reconcile(contract.ReconcileInput{MissingTarget: true})
		if r.State != contract.TotalPending || r.TotalKnown {
			t.Fatalf("C06: %v", r)
		}
	}
	// B01 / B02
	{
		r := contract.Reconcile(contract.ReconcileInput{BaselineKnown: true, Baseline: 100, EndKnown: true, EndCounter: 112, SuffixKnown: true, Suffix: 2})
		if !r.TotalKnown || *r.Total != 14 {
			t.Fatalf("B01: %v", r)
		}
		r2 := contract.Reconcile(contract.ReconcileInput{EndKnown: true, EndCounter: 112, SuffixKnown: true, Suffix: 2})
		if r2.TotalKnown {
			t.Fatalf("B02 invented baseline: %v", r2)
		}
	}
	// E01 / E02 / E03
	{
		r := contract.Reconcile(contract.ReconcileInput{Epochs: []contract.EpochRecord{{Consumption: 13, BaselineOK: true, Disjoint: true}, {Consumption: 2, BaselineOK: true, Disjoint: true}}})
		if !r.TotalKnown || *r.Total != 15 {
			t.Fatalf("E01: %v", r)
		}
		r2 := contract.Reconcile(contract.ReconcileInput{Epochs: []contract.EpochRecord{{Consumption: 13, BaselineOK: true, Disjoint: true}, {Consumption: 2, BaselineOK: true, Disjoint: false}}})
		if r2.TotalKnown {
			t.Fatalf("E02: %v", r2)
		}
		r3 := contract.Reconcile(contract.ReconcileInput{DecreasingPrefixes: true})
		if r3.State != contract.TotalInconsistent {
			t.Fatalf("E03: %v", r3)
		}
	}
	// O01–O05
	{
		r := contract.Reconcile(contract.ReconcileInput{ParentInclusive: fptr(13), Child: fptr(5), ChildMembership: true})
		if !r.TotalKnown || *r.Total != 13 || r.ChildBreakdown == nil || *r.ChildBreakdown != 5 {
			t.Fatalf("O01: %v", r)
		}
		r2 := contract.Reconcile(contract.ReconcileInput{ParentExclusive: fptr(8), Child: fptr(5), ChildMembership: true})
		if !r2.TotalKnown || *r2.Total != 13 {
			t.Fatalf("O02: %v", r2)
		}
		r3 := contract.Reconcile(contract.ReconcileInput{ParentInclusive: fptr(13), Child: fptr(5), InclusionUnknown: true})
		if r3.TotalKnown {
			t.Fatalf("O03: %v", r3)
		}
		r4 := contract.Reconcile(contract.ReconcileInput{
			ParentAtoms: map[string]float64{"a": 3, "b": 5, "c": 5}, ChildAtoms: map[string]float64{"b": 5, "d": 2}, ExactDecomposition: true,
		})
		if !r4.TotalKnown || *r4.Total != 15 {
			t.Fatalf("O04: %v", r4)
		}
		r5 := contract.Reconcile(contract.ReconcileInput{OverlapPartial: true, ExactDecomposition: false})
		if r5.TotalKnown {
			t.Fatalf("O05: %v", r5)
		}
	}
	// P01 / P02 pricing
	{
		rate := func(v float64) *float64 { return &v }
		st, amt, _, e := contract.EstimateCost(
			map[string]float64{"uncached_input": 1000, "cached_input": 500, "output": 200},
			map[string]*float64{"uncached_input": rate(2), "cached_input": rate(1), "output": rate(6)},
		)
		if e != nil || st != "known_estimated" || amt == nil || *amt != "0.0037" {
			t.Fatalf("P01: state=%s amt=%v err=%v", st, amt, e)
		}
		st2, amt2, sub, e2 := contract.EstimateCost(
			map[string]float64{"uncached_input": 1000, "cached_input": 500, "output": 200},
			map[string]*float64{"uncached_input": rate(2), "cached_input": rate(1), "output": nil},
		)
		if e2 != nil || st2 != contract.TotalUnknown || amt2 != nil || sub == nil || *sub != "0.0025" {
			t.Fatalf("P02: state=%s amt=%v sub=%v", st2, amt2, sub)
		}
	}
	// Ensure vectors.json still present as oracle reference when available.
	if raw, e := os.ReadFile("/private/tmp/v4-08-review-probes/vectors.json"); e == nil {
		var doc struct {
			Vectors []vec `json:"vectors"`
		}
		if e = json.Unmarshal(raw, &doc); e != nil {
			t.Fatal(e)
		}
		if len(doc.Vectors) < 10 {
			t.Fatalf("unexpected vectors.json length %d", len(doc.Vectors))
		}
	}
}

func fptr(v float64) *float64 { x := v; return &x }
