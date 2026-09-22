package contract

import (
	"encoding/json"
	"errors"
	"fmt"
	"sort"
)

// ConsolidationSchemaVersion is the typed V4-10 consolidation inventory version.
// Inventory is a committed artifact; schema-2 store namespaces are optional and unused here.
const ConsolidationSchemaVersion = 1

// Component kinds that the V4-10 inventory must cover before any import.
const (
	ComponentKindSpecialist      = "specialist"
	ComponentKindContract        = "contract"
	ComponentKindMCP             = "mcp"
	ComponentKindMemory          = "memory"
	ComponentKindEvaluationTool  = "evaluation_tooling"
	ComponentKindOptionalClient  = "optional_client"
)

// Import readiness labels (R01). Missing consumer/provenance blocks readiness.
const (
	ImportNotProposed                 = "not_proposed"
	ImportReady                       = "ready"
	ImportBlockedMissingConsumer      = "blocked_missing_consumer"
	ImportBlockedMissingProvenance    = "blocked_missing_provenance"
	ImportBlockedMissingLicense       = "blocked_missing_license"
	ImportBlockedMissingReplacement   = "blocked_missing_replacement_path"
	ImportBlockedMissingBoundaries    = "blocked_missing_runtime_boundaries"
	ImportDeferredSlice               = "deferred_to_unassigned_slice"
)

// Delivery-effect classifications for consolidation decisions (R07).
// Null/blocked/inconclusive MUST NOT be relabeled as demonstrated performance gains.
const (
	EffectMeasured         = "measured"
	EffectMaintenanceOnly  = "maintenance_only"
	EffectNull             = "null"
	EffectBlocked          = "blocked"
	EffectInconclusive     = "inconclusive"
	EffectNotApplicable    = "not_applicable"
)

// Requirement coverage statuses for the inventory slice.
const (
	ReqCovered              = "covered"
	ReqPartialReadinessOnly = "partial_readiness_only"
	ReqDeferredSlice        = "deferred_slice"
	ReqNotApplicable        = "not_applicable"
)

// Required specialist IDs (ten roster specialists; CRYSTALIUM is inventoried separately).
var RequiredSpecialists = []string{
	"atlas", "ramza", "spectra", "vivi", "apivr", "idg", "forge", "vigil", "kupo", "gilgamesh",
}

// RequiredContracts are the four sibling contracts.
var RequiredContracts = []string{"eiis", "ecl", "esl", "ecm"}

// RequiredSupportComponents are non-specialist inventory obligations from §V4-10.
var RequiredSupportComponents = []string{
	"junction", "tonberry", "atomos", "atlas-aci", "crystalium",
	"evaluation-tooling", "optional-client-acp", "optional-client-a2a",
}

// DeferredV410Slices are assignment slices not yet assigned; must be explicit in the receipt.
var DeferredV410Slices = []string{"one-component-import", "registry-and-discovery-compiler"}

// ConsolidationComponent is one inventoried source (R01 fields).
type ConsolidationComponent struct {
	SchemaVersion              int               `json:"schema_version"`
	ID                         string            `json:"id"`
	Kind                       string            `json:"kind"`
	DisplayName                string            `json:"display_name"`
	SourceRepo                 string            `json:"source_repo"`
	PinnedVersion              string            `json:"pinned_version"`
	License                    string            `json:"license"`
	Provenance                 string            `json:"provenance"`
	Consumers                  []string          `json:"consumers"`
	ReplacementPath            string            `json:"replacement_path"`
	PreservedRuntimeBoundaries []string          `json:"preserved_runtime_boundaries"`
	ImportReadiness            string            `json:"import_readiness"`
	ImportBlockers             []string          `json:"import_blockers,omitempty"`
	DeliveryEffectClass        string            `json:"delivery_effect_class"`
	ComparisonEvidenceRef      string            `json:"comparison_evidence_ref"`
	PerformanceGainClaimed     bool              `json:"performance_gain_claimed"`
	PerformanceGainAllowed     bool              `json:"performance_gain_allowed"`
	Notes                      string            `json:"notes,omitempty"`
	Metadata                   map[string]string `json:"metadata,omitempty"`
}

func (c ConsolidationComponent) Validate() error {
	if c.SchemaVersion != ConsolidationSchemaVersion {
		return errors.New("unknown consolidation component schema version")
	}
	if e := validateID("component", c.ID, true); e != nil {
		return e
	}
	switch c.Kind {
	case ComponentKindSpecialist, ComponentKindContract, ComponentKindMCP,
		ComponentKindMemory, ComponentKindEvaluationTool, ComponentKindOptionalClient:
	default:
		return fmt.Errorf("unknown component kind %q", c.Kind)
	}
	if c.DisplayName == "" || c.SourceRepo == "" || c.License == "" || c.Provenance == "" {
		return errors.New("display_name, source_repo, license, and provenance are required")
	}
	if c.ReplacementPath == "" {
		return errors.New("replacement_path required (retain_external or proposed path)")
	}
	if len(c.PreservedRuntimeBoundaries) == 0 {
		return errors.New("preserved_runtime_boundaries required")
	}
	for _, b := range c.PreservedRuntimeBoundaries {
		if b == "" {
			return errors.New("empty runtime boundary")
		}
	}
	switch c.ImportReadiness {
	case ImportNotProposed, ImportReady, ImportBlockedMissingConsumer, ImportBlockedMissingProvenance,
		ImportBlockedMissingLicense, ImportBlockedMissingReplacement, ImportBlockedMissingBoundaries,
		ImportDeferredSlice:
	default:
		return fmt.Errorf("unknown import_readiness %q", c.ImportReadiness)
	}
	switch c.DeliveryEffectClass {
	case EffectMeasured, EffectMaintenanceOnly, EffectNull, EffectBlocked, EffectInconclusive, EffectNotApplicable:
	default:
		return fmt.Errorf("unknown delivery_effect_class %q", c.DeliveryEffectClass)
	}
	if c.ComparisonEvidenceRef == "" {
		return errors.New("comparison_evidence_ref required")
	}
	if e := ValidateMetadata(c.Metadata); e != nil {
		return e
	}
	if e := c.validateImportGate(); e != nil {
		return e
	}
	if e := c.validateDeliveryEffect(); e != nil {
		return e
	}
	return nil
}

// validateImportGate — missing consumer/provenance/license/replacement/boundaries prevent ready (R01).
func (c ConsolidationComponent) validateImportGate() error {
	missingConsumer := len(c.Consumers) == 0
	missingProvenance := c.Provenance == "" || c.Provenance == "unknown" || c.Provenance == "missing"
	missingLicense := c.License == "" || c.License == "unknown" || c.License == "missing"
	missingReplacement := c.ReplacementPath == ""
	missingBoundaries := len(c.PreservedRuntimeBoundaries) == 0

	if c.ImportReadiness == ImportReady {
		if missingConsumer || missingProvenance || missingLicense || missingReplacement || missingBoundaries {
			return errors.New("import_readiness ready requires consumers, provenance, license, replacement_path, and boundaries")
		}
		if len(c.ImportBlockers) != 0 {
			return errors.New("ready components must not list import blockers")
		}
		return nil
	}

	if c.ImportReadiness == ImportBlockedMissingConsumer && !missingConsumer {
		return errors.New("blocked_missing_consumer requires empty consumers")
	}
	if c.ImportReadiness == ImportBlockedMissingProvenance && !missingProvenance {
		return errors.New("blocked_missing_provenance requires missing provenance")
	}
	if missingConsumer && c.ImportReadiness != ImportBlockedMissingConsumer &&
		c.ImportReadiness != ImportNotProposed && c.ImportReadiness != ImportDeferredSlice {
		return errors.New("missing consumers must block import readiness")
	}
	if missingProvenance && c.ImportReadiness != ImportBlockedMissingProvenance &&
		c.ImportReadiness != ImportNotProposed && c.ImportReadiness != ImportDeferredSlice {
		return errors.New("missing provenance must block import readiness")
	}
	return nil
}

// validateDeliveryEffect — null/blocked/inconclusive cannot become performance gains (R07).
func (c ConsolidationComponent) validateDeliveryEffect() error {
	switch c.DeliveryEffectClass {
	case EffectMeasured:
		if !c.PerformanceGainAllowed {
			return errors.New("measured effect requires performance_gain_allowed")
		}
		if c.ComparisonEvidenceRef == "" || c.ComparisonEvidenceRef == "none" {
			return errors.New("measured effect requires comparison evidence")
		}
	case EffectMaintenanceOnly, EffectNull, EffectBlocked, EffectInconclusive, EffectNotApplicable:
		if c.PerformanceGainClaimed {
			return errors.New("null, blocked, inconclusive, maintenance-only, or N/A effects cannot claim performance gains")
		}
		if c.PerformanceGainAllowed {
			return errors.New("performance_gain_allowed only for measured delivery effects")
		}
	}
	return nil
}

// ImportProposed reports whether this component is a candidate for the deferred import slice.
func (c ConsolidationComponent) ImportProposed() bool {
	return c.ImportReadiness == ImportReady ||
		c.ImportReadiness == ImportBlockedMissingConsumer ||
		c.ImportReadiness == ImportBlockedMissingProvenance ||
		c.ImportReadiness == ImportBlockedMissingLicense ||
		c.ImportReadiness == ImportBlockedMissingReplacement ||
		c.ImportReadiness == ImportBlockedMissingBoundaries
}

// RequirementCoverage records how each V4-10 requirement is treated in this inventory slice.
type RequirementCoverage struct {
	ID     string `json:"id"`
	Status string `json:"status"`
	Notes  string `json:"notes"`
}

func (r RequirementCoverage) Validate() error {
	if r.ID == "" || r.Notes == "" {
		return errors.New("requirement coverage id and notes required")
	}
	switch r.Status {
	case ReqCovered, ReqPartialReadinessOnly, ReqDeferredSlice, ReqNotApplicable:
	default:
		return fmt.Errorf("unknown requirement coverage status %q", r.Status)
	}
	return nil
}

// ConsolidationDecision records the package-level interpretation of early comparison evidence (R07).
type ConsolidationDecision struct {
	EarlyComparisonRef     string   `json:"early_comparison_ref"`
	StructuralArmStatus    string   `json:"structural_arm_status"`
	MeasuredPerformance    bool     `json:"measured_performance"`
	MaintenanceJustification string `json:"maintenance_justification"`
	ForbiddenRelabelings   []string `json:"forbidden_relabelings"`
	NoAutomaticArchive     bool     `json:"no_automatic_archive"`
	NoPrivilegedToolMerger bool     `json:"no_privileged_tool_merger"`
	NoProtocolRewrite      bool     `json:"no_protocol_rewrite"`
}

func (d ConsolidationDecision) Validate() error {
	if d.EarlyComparisonRef == "" || d.StructuralArmStatus == "" || d.MaintenanceJustification == "" {
		return errors.New("consolidation decision fields incomplete")
	}
	if d.MeasuredPerformance {
		return errors.New("inventory slice must not claim measured consolidation performance")
	}
	if len(d.ForbiddenRelabelings) == 0 {
		return errors.New("forbidden_relabelings required")
	}
	if !d.NoAutomaticArchive || !d.NoPrivilegedToolMerger || !d.NoProtocolRewrite {
		return errors.New("stop conditions must remain explicit (no archive/merger/protocol rewrite)")
	}
	return nil
}

// ConsolidationInventory is the machine-readable V4-10 inventory artifact.
type ConsolidationInventory struct {
	SchemaVersion   int                      `json:"schema_version"`
	Package         string                   `json:"package"`
	Slice           string                   `json:"slice"`
	PlanCommit      string                   `json:"plan_commit"`
	BaseCommit      string                   `json:"base_commit"`
	DeferredSlices  []string                 `json:"deferred_slices"`
	Components      []ConsolidationComponent `json:"components"`
	Requirements    []RequirementCoverage    `json:"requirements"`
	Decision        ConsolidationDecision    `json:"decision"`
	Metadata        map[string]string        `json:"metadata,omitempty"`
}

func (inv ConsolidationInventory) Validate() error {
	if inv.SchemaVersion != ConsolidationSchemaVersion {
		return errors.New("unknown consolidation inventory schema version")
	}
	if inv.Package != PackageV410 {
		return errors.New("inventory package must be V4-10")
	}
	if inv.Slice != "inventory" {
		return errors.New("inventory slice must be inventory")
	}
	if inv.PlanCommit == "" || inv.BaseCommit == "" {
		return errors.New("plan_commit and base_commit required")
	}
	if e := validateDeferredSlices(inv.DeferredSlices); e != nil {
		return e
	}
	if e := inv.Decision.Validate(); e != nil {
		return e
	}
	if e := ValidateMetadata(inv.Metadata); e != nil {
		return e
	}
	if len(inv.Components) == 0 {
		return errors.New("components required")
	}
	seen := map[string]bool{}
	for _, c := range inv.Components {
		if e := c.Validate(); e != nil {
			return fmt.Errorf("component %s: %w", c.ID, e)
		}
		if seen[c.ID] {
			return fmt.Errorf("duplicate component id %s", c.ID)
		}
		seen[c.ID] = true
	}
	if e := inv.requireCoverage(); e != nil {
		return e
	}
	if e := inv.validateRequirements(); e != nil {
		return e
	}
	return nil
}

func validateDeferredSlices(deferred []string) error {
	want := append([]string{}, DeferredV410Slices...)
	sort.Strings(want)
	got := append([]string{}, deferred...)
	sort.Strings(got)
	if len(got) != len(want) {
		return errors.New("deferred_slices must explicitly list one-component-import and registry-and-discovery-compiler")
	}
	for i := range want {
		if got[i] != want[i] {
			return errors.New("deferred_slices must explicitly list one-component-import and registry-and-discovery-compiler")
		}
	}
	return nil
}

func (inv ConsolidationInventory) requireCoverage() error {
	for _, id := range RequiredSpecialists {
		c, ok := inv.component(id)
		if !ok || c.Kind != ComponentKindSpecialist {
			return fmt.Errorf("missing specialist inventory for %s", id)
		}
	}
	for _, id := range RequiredContracts {
		c, ok := inv.component(id)
		if !ok || c.Kind != ComponentKindContract {
			return fmt.Errorf("missing contract inventory for %s", id)
		}
	}
	for _, id := range RequiredSupportComponents {
		if _, ok := inv.component(id); !ok {
			return fmt.Errorf("missing support inventory for %s", id)
		}
	}
	return nil
}

func (inv ConsolidationInventory) component(id string) (ConsolidationComponent, bool) {
	for _, c := range inv.Components {
		if c.ID == id {
			return c, true
		}
	}
	return ConsolidationComponent{}, false
}

func (inv ConsolidationInventory) validateRequirements() error {
	need := map[string]bool{
		"V4-10-R01": false, "V4-10-R02": false, "V4-10-R03": false, "V4-10-R04": false,
		"V4-10-R05": false, "V4-10-R06": false, "V4-10-R07": false,
	}
	for _, r := range inv.Requirements {
		if e := r.Validate(); e != nil {
			return e
		}
		if _, ok := need[r.ID]; !ok {
			return fmt.Errorf("unknown requirement %s", r.ID)
		}
		need[r.ID] = true
		switch r.ID {
		case "V4-10-R01", "V4-10-R07":
			if r.Status != ReqCovered {
				return fmt.Errorf("%s must be covered by the inventory slice", r.ID)
			}
		case "V4-10-R02", "V4-10-R03":
			if r.Status != ReqDeferredSlice {
				return fmt.Errorf("%s belongs to registry-and-discovery-compiler; must be deferred_slice", r.ID)
			}
		case "V4-10-R04", "V4-10-R05", "V4-10-R06":
			if r.Status != ReqPartialReadinessOnly && r.Status != ReqDeferredSlice && r.Status != ReqNotApplicable {
				return fmt.Errorf("%s must be partial_readiness_only, deferred_slice, or not_applicable in inventory", r.ID)
			}
		}
	}
	for id, seen := range need {
		if !seen {
			return fmt.Errorf("missing requirement coverage for %s", id)
		}
	}
	return nil
}

// ParseConsolidationInventory decodes and validates a consolidation inventory document.
func ParseConsolidationInventory(raw []byte) (ConsolidationInventory, error) {
	var inv ConsolidationInventory
	if e := StrictJSON(raw, &inv); e != nil {
		return inv, e
	}
	if e := inv.Validate(); e != nil {
		return inv, e
	}
	return inv, nil
}

// MarshalCanonical returns stable JSON for digests / fixtures.
func (inv ConsolidationInventory) MarshalCanonical() ([]byte, error) {
	if e := inv.Validate(); e != nil {
		return nil, e
	}
	return json.Marshal(inv)
}

// RejectPerformanceRelabel returns an error when a non-measured effect is labeled as a gain (R07).
func RejectPerformanceRelabel(effectClass string, claimedGain bool) error {
	switch effectClass {
	case EffectNull, EffectBlocked, EffectInconclusive, EffectMaintenanceOnly, EffectNotApplicable:
		if claimedGain {
			return errors.New("null, blocked, or inconclusive results cannot be relabeled as demonstrated performance gains")
		}
	case EffectMeasured:
		return nil
	default:
		return fmt.Errorf("unknown delivery_effect_class %q", effectClass)
	}
	return nil
}

// RejectImportWithoutEvidence returns an error when import readiness is asserted without R01 fields.
func RejectImportWithoutEvidence(c ConsolidationComponent) error {
	c.SchemaVersion = ConsolidationSchemaVersion
	if c.ImportReadiness != ImportReady {
		return nil
	}
	return c.validateImportGate()
}
