package contract

import (
	"errors"
	"math"
	"sort"
)

const ReconciliationRuleVersion = "gauge-observation-reconcile@1"

// ReconcileInput is language-neutral inventory for pure arithmetic oracles.
type ReconcileInput struct {
	// Atom inventory keyed by stable consumption identity (e.g. d1).
	Atoms map[string]float64 `json:"atoms,omitempty"`

	// Optional authoritative prefix over a covered atom set.
	PrefixValue    *float64 `json:"prefix_value,omitempty"`
	PrefixVersions []string `json:"prefix_versions,omitempty"` // "d1:v0"
	PrefixEnd      int      `json:"prefix_end,omitempty"`

	// Late smaller historical prefixes add nothing once a further prefix is validated.
	LatePrefixes []PrefixRecord `json:"late_prefixes,omitempty"`

	// Corrections applied once per correction identity.
	Corrections []CorrectionStep `json:"corrections,omitempty"`

	// Incorporating snapshot after correction becomes authoritative (no second subtraction).
	Incorporating *PrefixRecord `json:"incorporating,omitempty"`

	BaselineKnown bool    `json:"baseline_known"`
	Baseline      float64 `json:"baseline"`
	EndCounter    float64 `json:"end_counter"`
	EndKnown      bool    `json:"end_known"`
	Suffix        float64 `json:"suffix"`
	SuffixKnown   bool    `json:"suffix_known"`

	Epochs []EpochRecord `json:"epochs,omitempty"`

	ParentInclusive    *float64           `json:"parent_inclusive,omitempty"`
	ParentExclusive    *float64           `json:"parent_exclusive,omitempty"`
	Child              *float64           `json:"child,omitempty"`
	ChildMembership    bool               `json:"child_membership"`
	ParentAtoms        map[string]float64 `json:"parent_atoms,omitempty"`
	ChildAtoms         map[string]float64 `json:"child_atoms,omitempty"`
	ExactDecomposition bool               `json:"exact_decomposition"`
	OverlapPartial     bool               `json:"overlap_partial"`
	InclusionUnknown   bool               `json:"inclusion_unknown"`

	MissingTarget bool `json:"missing_target"`
	PendingOnly   bool `json:"pending_only"`

	// Same-epoch decreasing cumulative without correction/reset.
	DecreasingPrefixes bool `json:"decreasing_prefixes"`
}

type PrefixRecord struct {
	End              int      `json:"end"`
	Value            float64  `json:"value"`
	Versions         []string `json:"versions,omitempty"`
	IncorporatesCorr bool     `json:"incorporates_correction,omitempty"`
	Late             bool     `json:"late,omitempty"`
}

type CorrectionStep struct {
	ID              string   `json:"id"`
	Target          string   `json:"target"` // "d2:v0"
	Old             float64  `json:"old"`
	New             float64  `json:"new"`
	Version         string   `json:"version"`
	CoveredVersions []string `json:"covered_versions,omitempty"`
	AdditiveProof   bool     `json:"additive_proof"`
	Fork            bool     `json:"fork,omitempty"`
	Cycle           bool     `json:"cycle,omitempty"`
}

type EpochRecord struct {
	Consumption float64 `json:"consumption"`
	BaselineOK  bool    `json:"baseline_ok"`
	Disjoint    bool    `json:"disjoint"`
}

type ReconcileResult struct {
	State              string          `json:"state"`
	Total              *float64        `json:"total"`
	TotalKnown         bool            `json:"total_known"`
	HistoricalSnapshot *float64        `json:"historical_snapshot,omitempty"`
	ChildBreakdown     *float64        `json:"child_breakdown,omitempty"`
	PendingTargets     []string        `json:"pending_targets,omitempty"`
	RuleVersion        string          `json:"rule_version"`
	AppliedCorrections map[string]bool `json:"applied_corrections,omitempty"`
}

func ptr(v float64) *float64 { x := v; return &x }

func knownTotal(v float64) ReconcileResult {
	return ReconcileResult{State: TotalKnown, Total: ptr(v), TotalKnown: true, RuleVersion: ReconciliationRuleVersion, AppliedCorrections: map[string]bool{}}
}

func unknownTotal(hist *float64, pending ...string) ReconcileResult {
	r := ReconcileResult{State: TotalUnknown, TotalKnown: false, RuleVersion: ReconciliationRuleVersion, PendingTargets: append([]string{}, pending...), AppliedCorrections: map[string]bool{}}
	if hist != nil {
		r.HistoricalSnapshot = ptr(*hist)
	}
	return r
}

func inconsistentTotal() ReconcileResult {
	return ReconcileResult{State: TotalInconsistent, TotalKnown: false, RuleVersion: ReconciliationRuleVersion, AppliedCorrections: map[string]bool{}}
}

func pendingTotal(targets ...string) ReconcileResult {
	return ReconcileResult{State: TotalPending, TotalKnown: false, RuleVersion: ReconciliationRuleVersion, PendingTargets: append([]string{}, targets...), AppliedCorrections: map[string]bool{}}
}

// Reconcile derives qualified totals from explicit coverage — never invents zeros.
func Reconcile(in ReconcileInput) ReconcileResult {
	if in.PendingOnly || in.MissingTarget {
		return pendingTotal("missing-target")
	}
	for _, c := range in.Corrections {
		if c.Fork || c.Cycle {
			return unknownTotal(nil)
		}
	}
	if in.DecreasingPrefixes {
		return inconsistentTotal()
	}
	if in.InclusionUnknown {
		return unknownTotal(nil)
	}
	if in.OverlapPartial && !in.ExactDecomposition {
		return unknownTotal(nil)
	}

	if len(in.ParentAtoms) > 0 || len(in.ChildAtoms) > 0 {
		if !in.ExactDecomposition {
			return unknownTotal(nil)
		}
		union := map[string]float64{}
		for k, v := range in.ParentAtoms {
			union[k] = v
		}
		for k, v := range in.ChildAtoms {
			if prev, ok := union[k]; ok && prev != v {
				return unknownTotal(nil)
			}
			union[k] = v
		}
		var total float64
		keys := make([]string, 0, len(union))
		for k := range union {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		for _, k := range keys {
			total += union[k]
		}
		r := knownTotal(total)
		if c, ok := sumMap(in.ChildAtoms); ok {
			r.ChildBreakdown = ptr(c)
		}
		return r
	}
	if in.ParentInclusive != nil && in.Child != nil {
		if !in.ChildMembership {
			return unknownTotal(nil)
		}
		r := knownTotal(*in.ParentInclusive)
		r.ChildBreakdown = ptr(*in.Child)
		return r
	}
	if in.ParentExclusive != nil && in.Child != nil {
		if !in.ChildMembership {
			return unknownTotal(nil)
		}
		return knownTotal(*in.ParentExclusive + *in.Child)
	}

	if len(in.Epochs) > 0 {
		var total float64
		for _, ep := range in.Epochs {
			if !ep.Disjoint || !ep.BaselineOK {
				return unknownTotal(nil)
			}
			total += ep.Consumption
		}
		return knownTotal(total)
	}

	if in.EndKnown {
		if !in.BaselineKnown {
			return unknownTotal(nil)
		}
		prefix := in.EndCounter - in.Baseline
		if prefix < 0 {
			return inconsistentTotal()
		}
		total := prefix
		if in.SuffixKnown {
			total += in.Suffix
		}
		return knownTotal(total)
	}

	atoms := map[string]float64{}
	for k, v := range in.Atoms {
		atoms[k] = v
	}
	applied := map[string]bool{}
	var hist *float64
	if in.PrefixValue != nil {
		hist = ptr(*in.PrefixValue)
	}

	// Late historical prefixes never shrink the frontier.
	_ = in.LatePrefixes

	// Incorporating snapshot after known correction: authoritative, no re-subtraction.
	if in.Incorporating != nil {
		r := knownTotal(in.Incorporating.Value)
		r.HistoricalSnapshot = hist
		r.AppliedCorrections = applied
		return r
	}

	// Late-prefix correction rule (covered versions + additive contract).
	if len(in.Corrections) > 0 && in.PrefixValue != nil {
		usesPrefixRule := false
		for _, c := range in.Corrections {
			if c.AdditiveProof || len(c.CoveredVersions) > 0 {
				usesPrefixRule = true
				break
			}
		}
		if usesPrefixRule {
			current := *in.PrefixValue
			for _, c := range in.Corrections {
				if applied[c.ID] {
					continue
				}
				if c.Target == "" {
					return pendingTotal(c.ID)
				}
				covered := false
				for _, ver := range c.CoveredVersions {
					if ver == c.Target {
						covered = true
						break
					}
				}
				if !c.AdditiveProof || !covered {
					return unknownTotal(hist)
				}
				current = current - c.Old + c.New
				atoms[atomOf(c.Target)] = c.New
				applied[c.ID] = true
			}
			r := knownTotal(current)
			r.HistoricalSnapshot = hist
			r.AppliedCorrections = applied
			return r
		}
	}

	// Corrections against atom inventory (suffix / non-covered).
	if len(in.Corrections) > 0 {
		for _, c := range in.Corrections {
			if applied[c.ID] {
				continue
			}
			atom := atomOf(c.Target)
			if _, ok := atoms[atom]; !ok {
				return pendingTotal(c.Target)
			}
			atoms[atom] = c.New
			applied[c.ID] = true
		}
	}

	if len(atoms) == 0 {
		if in.PrefixValue != nil {
			return knownTotal(*in.PrefixValue)
		}
		return unknownTotal(hist)
	}
	keys := make([]string, 0, len(atoms))
	for k := range atoms {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	var sum float64
	for _, k := range keys {
		sum += atoms[k]
	}
	r := knownTotal(sum)
	r.AppliedCorrections = applied
	r.HistoricalSnapshot = hist
	return r
}

func atomOf(version string) string {
	for i := 0; i < len(version); i++ {
		if version[i] == ':' {
			return version[:i]
		}
	}
	return version
}

func sumMap(m map[string]float64) (float64, bool) {
	if len(m) == 0 {
		return 0, false
	}
	var s float64
	for _, v := range m {
		s += v
	}
	return s, true
}

// EstimateCost computes estimated currency from token components; missing rates => unknown aggregate.
func EstimateCost(tokens map[string]float64, rates map[string]*float64) (state string, amount *string, knownSubtotal *string, err error) {
	if tokens == nil {
		return TotalUnknown, nil, nil, errors.New("missing tokens")
	}
	const den int64 = 1_000_000
	var num int64
	knownAll := true
	var knownNum int64
	keys := make([]string, 0, len(tokens))
	for k := range tokens {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		tok := tokens[k]
		rate, ok := rates[k]
		if !ok || rate == nil {
			knownAll = false
			continue
		}
		contrib := int64(math.Round(tok * (*rate)))
		num += contrib
		knownNum += contrib
	}
	if !knownAll {
		if knownNum > 0 {
			s := decimalFromMillionths(knownNum)
			return TotalUnknown, nil, &s, nil
		}
		return TotalUnknown, nil, nil, nil
	}
	s := decimalFromMillionths(num)
	return "known_estimated", &s, &s, nil
}

func decimalFromMillionths(millionths int64) string {
	// millionths of a dollar: 3700 -> 0.0037
	neg := millionths < 0
	if neg {
		millionths = -millionths
	}
	whole := millionths / 1_000_000
	frac := millionths % 1_000_000
	// trim to significant decimals without trailing noise for fixtures (4 places for 0.0037)
	s := formatInt(whole) + "." + padDigits(frac, 6)
	for len(s) > 0 && s[len(s)-1] == '0' {
		s = s[:len(s)-1]
	}
	if s[len(s)-1] == '.' {
		s += "0"
	}
	if neg {
		return "-" + s
	}
	return s
}

func padDigits(n int64, width int) string {
	s := formatInt(n)
	for len(s) < width {
		s = "0" + s
	}
	return s
}

func formatInt(n int64) string {
	if n == 0 {
		return "0"
	}
	neg := n < 0
	if neg {
		n = -n
	}
	var digits []byte
	for n > 0 {
		digits = append([]byte{byte('0' + n%10)}, digits...)
		n /= 10
	}
	if neg {
		return "-" + string(digits)
	}
	return string(digits)
}

// ReconcileObservations reduces persisted observations for one stream.
func ReconcileObservations(obs []UsageObservation, corrections []UsageCorrection) ReconcileResult {
	in := ReconcileInput{Atoms: map[string]float64{}}
	var prefix *UsageObservation
	for i := range obs {
		o := obs[i]
		switch o.Kind {
		case KindDelta:
			if !o.AmountKnown {
				return unknownTotal(nil)
			}
			in.Atoms[o.ID] = *o.Amount
		case KindPrefix:
			if !o.AmountKnown {
				return unknownTotal(nil)
			}
			if prefix == nil || o.CursorEnd >= prefix.CursorEnd {
				cp := o
				prefix = &cp
			}
		case KindCumulative:
			if !o.BaselineKnown || !o.AmountKnown {
				return unknownTotal(nil)
			}
			in.BaselineKnown = true
			in.Baseline = *o.Baseline
			in.EndKnown = true
			in.EndCounter = *o.Amount
		}
		if o.ParentScope == ParentUnknown {
			in.InclusionUnknown = true
		}
	}
	if prefix != nil {
		in.PrefixValue = ptr(*prefix.Amount)
		in.PrefixEnd = prefix.CursorEnd
		in.PrefixVersions = append([]string{}, prefix.CoveredVersions...)
	}
	seen := map[string]UsageCorrection{}
	for _, c := range corrections {
		if prev, ok := seen[c.ID]; ok {
			if prev.TargetID != c.TargetID || prev.NewAmount != c.NewAmount || prev.TargetRevision != c.TargetRevision {
				return unknownTotal(nil)
			}
			continue
		}
		seen[c.ID] = c
		targetOK := false
		for _, o := range obs {
			if o.ID == c.TargetID && (o.Revision == c.TargetRevision || o.Kind == KindDelta) {
				targetOK = true
				break
			}
		}
		if !targetOK {
			return pendingTotal(c.TargetID + ":" + c.TargetRevision)
		}
		step := CorrectionStep{
			ID: c.ID, Target: c.TargetID + ":" + c.TargetRevision,
			Old: c.OldAmount, New: c.NewAmount, Version: c.ReplacementRev,
			AdditiveProof:   c.AdditiveContract && c.CoveredInPrefix,
			CoveredVersions: append([]string{}, c.CoveredVersions...),
		}
		if c.CoveredInPrefix && len(step.CoveredVersions) == 0 && prefix != nil {
			step.CoveredVersions = append([]string{}, prefix.CoveredVersions...)
		}
		if c.CoveredInPrefix && len(c.CoveredVersions) > 0 {
			step.CoveredVersions = append([]string{}, c.CoveredVersions...)
		}
		in.Corrections = append(in.Corrections, step)
	}
	return Reconcile(in)
}
