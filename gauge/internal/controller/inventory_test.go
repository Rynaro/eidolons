package controller

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
)

func inventoryPath(t *testing.T) string {
	t.Helper()
	repo := os.Getenv("GAUGE_REPO")
	if repo == "" {
		// Prefer checkout root when running via inventory-anchors.sh / make gauge-test.
		wd, err := os.Getwd()
		if err != nil {
			t.Fatal(err)
		}
		// gauge/internal/controller → repo root
		repo = filepath.Clean(filepath.Join(wd, "../../.."))
	}
	p := filepath.Join(repo, "docs/campaigns/gauge/inventory/v4-10.json")
	if _, err := os.Stat(p); err != nil {
		t.Fatalf("inventory artifact missing at %s: %v", p, err)
	}
	return p
}

func loadInventory(t *testing.T) contract.ConsolidationInventory {
	t.Helper()
	raw, err := os.ReadFile(inventoryPath(t))
	if err != nil {
		t.Fatal(err)
	}
	inv, err := contract.ParseConsolidationInventory(raw)
	if err != nil {
		t.Fatalf("committed inventory must validate: %v", err)
	}
	return inv
}

func sampleComponent(id string) contract.ConsolidationComponent {
	return contract.ConsolidationComponent{
		SchemaVersion:              contract.ConsolidationSchemaVersion,
		ID:                         id,
		Kind:                       contract.ComponentKindSpecialist,
		DisplayName:                id,
		SourceRepo:                 "Rynaro/" + id,
		PinnedVersion:              "0.0.0",
		License:                    "Apache-2.0",
		Provenance:                 "fixture-provenance",
		Consumers:                  []string{"fixture-consumer"},
		ReplacementPath:            "retain_external",
		PreservedRuntimeBoundaries: []string{"separate_repo"},
		ImportReadiness:            contract.ImportNotProposed,
		DeliveryEffectClass:        contract.EffectBlocked,
		ComparisonEvidenceRef:      "fixture-comparison",
		PerformanceGainClaimed:     false,
		PerformanceGainAllowed:     false,
	}
}

// TestV410T01 — Cover every active roster/support component and third-party rights;
// missing consumer/provenance prevents import readiness.
func TestV410T01(t *testing.T) {
	inv := loadInventory(t)

	if inv.Slice != "inventory" || inv.Package != contract.PackageV410 {
		t.Fatalf("unexpected package/slice: %+v", inv)
	}
	for _, id := range contract.RequiredSpecialists {
		c, ok := componentByID(inv, id)
		if !ok || c.Kind != contract.ComponentKindSpecialist {
			t.Fatalf("missing specialist %s", id)
		}
		if c.License == "" || c.Provenance == "" || len(c.Consumers) == 0 ||
			c.ReplacementPath == "" || len(c.PreservedRuntimeBoundaries) == 0 {
			t.Fatalf("specialist %s missing R01 fields", id)
		}
	}
	for _, id := range contract.RequiredContracts {
		c, ok := componentByID(inv, id)
		if !ok || c.Kind != contract.ComponentKindContract {
			t.Fatalf("missing contract %s", id)
		}
	}
	for _, id := range contract.RequiredSupportComponents {
		if _, ok := componentByID(inv, id); !ok {
			t.Fatalf("missing support component %s", id)
		}
	}

	// Explicit deferred slices — not a silent pass.
	if _, err := contract.ParseConsolidationInventory(mustMarshal(t, withDeferred(inv, nil))); err == nil {
		t.Fatal("empty deferred_slices must fail")
	}
	if _, err := contract.ParseConsolidationInventory(mustMarshal(t, withDeferred(inv, []string{"one-component-import"}))); err == nil {
		t.Fatal("partial deferred_slices must fail")
	}

	// Missing consumers prevent import readiness.
	ready := sampleComponent("import-candidate")
	ready.ImportReadiness = contract.ImportReady
	if err := ready.Validate(); err != nil {
		t.Fatal(err)
	}
	ready.Consumers = nil
	if err := contract.RejectImportWithoutEvidence(ready); err == nil {
		t.Fatal("ready without consumers must be rejected")
	}
	ready.Consumers = nil
	ready.ImportReadiness = contract.ImportBlockedMissingConsumer
	if err := ready.Validate(); err != nil {
		t.Fatalf("blocked_missing_consumer should validate: %v", err)
	}

	// Missing provenance prevents import readiness.
	prov := sampleComponent("import-no-prov")
	prov.Provenance = "missing"
	prov.ImportReadiness = contract.ImportReady
	if err := contract.RejectImportWithoutEvidence(prov); err == nil {
		t.Fatal("ready with missing provenance must be rejected")
	}
	prov.ImportReadiness = contract.ImportBlockedMissingProvenance
	if err := prov.Validate(); err != nil {
		t.Fatalf("blocked_missing_provenance should validate: %v", err)
	}

	// Assert no component in the committed inventory is falsely marked ready without fields.
	for _, c := range inv.Components {
		if c.ImportReadiness == contract.ImportReady {
			if err := contract.RejectImportWithoutEvidence(c); err != nil {
				t.Fatalf("committed ready component %s fails gate: %v", c.ID, err)
			}
		}
	}
}

// TestV410T07 — Reference the early comparison record; null, blocked, or inconclusive
// results cannot be relabeled as demonstrated performance gains.
func TestV410T07(t *testing.T) {
	inv := loadInventory(t)

	if inv.Decision.MeasuredPerformance {
		t.Fatal("inventory slice must not claim measured consolidation performance")
	}
	if inv.Decision.EarlyComparisonRef == "" {
		t.Fatal("early comparison reference required")
	}
	if !inv.Decision.NoAutomaticArchive || !inv.Decision.NoPrivilegedToolMerger || !inv.Decision.NoProtocolRewrite {
		t.Fatal("stop conditions must remain explicit")
	}

	var r07 okCoverage
	for _, r := range inv.Requirements {
		if r.ID == "V4-10-R07" {
			r07.seen = true
			if r.Status != contract.ReqCovered {
				t.Fatalf("R07 must be covered, got %s", r.Status)
			}
		}
		if r.ID == "V4-10-R02" || r.ID == "V4-10-R03" {
			if r.Status != contract.ReqDeferredSlice {
				t.Fatalf("%s must be deferred_slice, got %s", r.ID, r.Status)
			}
		}
	}
	if !r07.seen {
		t.Fatal("missing R07 coverage")
	}

	for _, class := range []string{
		contract.EffectNull, contract.EffectBlocked, contract.EffectInconclusive,
		contract.EffectMaintenanceOnly, contract.EffectNotApplicable,
	} {
		if err := contract.RejectPerformanceRelabel(class, true); err == nil {
			t.Fatalf("%s claimed as performance gain must be rejected", class)
		}
		if err := contract.RejectPerformanceRelabel(class, false); err != nil {
			t.Fatalf("%s without claim should pass: %v", class, err)
		}
	}
	if err := contract.RejectPerformanceRelabel(contract.EffectMeasured, true); err != nil {
		t.Fatalf("measured may claim gain: %v", err)
	}

	for _, c := range inv.Components {
		if c.DeliveryEffectClass != contract.EffectMeasured && c.PerformanceGainClaimed {
			t.Fatalf("component %s relabeled non-measured effect as performance gain", c.ID)
		}
		if err := contract.RejectPerformanceRelabel(c.DeliveryEffectClass, c.PerformanceGainClaimed); err != nil {
			t.Fatalf("component %s: %v", c.ID, err)
		}
		// Mutate a copy: blocked + claimed gain must fail Validate.
		bad := c
		if bad.DeliveryEffectClass == contract.EffectMeasured {
			continue
		}
		bad.PerformanceGainClaimed = true
		if err := bad.Validate(); err == nil {
			t.Fatalf("component %s accepted claimed gain on %s", c.ID, c.DeliveryEffectClass)
		}
	}

	// Decision cannot flip measured_performance true while structural arm is pending.
	badDec := inv
	badDec.Decision.MeasuredPerformance = true
	if err := badDec.Decision.Validate(); err == nil {
		t.Fatal("measured_performance true must fail decision validation")
	}
}

type okCoverage struct{ seen bool }

func componentByID(inv contract.ConsolidationInventory, id string) (contract.ConsolidationComponent, bool) {
	for _, c := range inv.Components {
		if c.ID == id {
			return c, true
		}
	}
	return contract.ConsolidationComponent{}, false
}

func withDeferred(inv contract.ConsolidationInventory, deferred []string) contract.ConsolidationInventory {
	out := inv
	out.DeferredSlices = deferred
	return out
}

func mustMarshal(t *testing.T, inv contract.ConsolidationInventory) []byte {
	t.Helper()
	// Bypass Validate on marshal for negative fixtures — encode manually.
	type alias contract.ConsolidationInventory
	raw, err := json.Marshal(alias(inv))
	if err != nil {
		t.Fatal(err)
	}
	return raw
}
