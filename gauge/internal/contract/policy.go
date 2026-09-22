package contract

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"sort"
)

// Preferences are controller-local logical layers, not OS identities or grants.
type Preferences struct {
	Version      int           `json:"schema_version"`
	Preset       string        `json:"preset,omitempty"`
	Restrictions []Restriction `json:"restrictions,omitempty"`
}
type PreferenceDocument struct {
	Version    int         `json:"schema_version"`
	Controller string      `json:"controller"`
	Layer      string      `json:"layer"`
	Revision   uint64      `json:"revision"`
	Digest     string      `json:"digest"`
	Values     Preferences `json:"values"`
}
type Ceiling struct {
	Resource string   `json:"resource"`
	Unit     string   `json:"unit"`
	Pool     string   `json:"pool"`
	Interval string   `json:"interval"`
	Scope    string   `json:"scope"`
	Limit    *float64 `json:"limit"`
}

func (c Ceiling) Key() string {
	b, _ := json.Marshal([]string{c.Resource, c.Unit, c.Pool, c.Interval, c.Scope})
	return string(b)
}
func (c Ceiling) Validate() error {
	if c.Resource == "" || c.Unit == "" || c.Pool == "" || c.Interval == "" {
		return errors.New("incomplete ceiling dimensions")
	}
	switch c.Scope {
	case "task", "project", "account", "window", "concurrency":
	default:
		return errors.New("unknown ceiling scope")
	}
	// Preserve the negative sign when JSON underflow rounds a limit to -0.
	if c.Limit != nil && (math.Signbit(*c.Limit) || math.IsNaN(*c.Limit) || math.IsInf(*c.Limit, 0)) {
		return errors.New("ceiling must be finite and nonnegative")
	}
	return nil
}

// Nil sets impose no restriction; explicit empty sets allow nothing.
// omitzero preserves that distinction in persistence and every semantic digest.
type Restriction struct {
	Allowed  []string  `json:"allowed,omitzero"`
	Denied   []string  `json:"denied,omitempty"`
	Billing  []string  `json:"billing,omitzero"`
	Ceilings []Ceiling `json:"ceilings,omitempty"`
}

func (r Restriction) Validate() error {
	for _, xs := range [][]string{r.Allowed, r.Denied, r.Billing} {
		for _, x := range xs {
			if x == "" {
				return errors.New("empty restriction")
			}
		}
	}
	for _, c := range r.Ceilings {
		if e := c.Validate(); e != nil {
			return e
		}
	}
	return nil
}
func (p Preferences) Validate() error {
	if p.Version != 1 {
		return errors.New("unknown preference schema version")
	}
	switch p.Preset {
	case "", "Conserve", "Balanced", "Accelerate":
	default:
		return errors.New("unknown Gauge preset")
	}
	for _, r := range p.Restrictions {
		if e := r.Validate(); e != nil {
			return e
		}
	}
	return nil
}
func normalizeRestrictions(rs []Restriction) []Restriction {
	out := append([]Restriction(nil), rs...)
	for i := range out {
		out[i].Allowed = SortedSet(out[i].Allowed)
		out[i].Denied = SortedSet(out[i].Denied)
		out[i].Billing = SortedSet(out[i].Billing)
		out[i].Ceilings = append([]Ceiling(nil), out[i].Ceilings...)
		sort.Slice(out[i].Ceilings, func(a, b int) bool {
			aa, _ := json.Marshal(out[i].Ceilings[a])
			bb, _ := json.Marshal(out[i].Ceilings[b])
			return string(aa) < string(bb)
		})
	}
	sort.Slice(out, func(i, j int) bool {
		a, _ := json.Marshal(out[i])
		b, _ := json.Marshal(out[j])
		return string(a) < string(b)
	})
	return out
}
func (p Preferences) Normalized() Preferences {
	p.Restrictions = normalizeRestrictions(p.Restrictions)
	return p
}
func (p Preferences) Identity() string { b, _ := json.Marshal(p.Normalized()); return Digest(b) }
func SortedSet(xs []string) []string {
	if xs == nil {
		return nil
	}
	m := map[string]bool{}
	for _, x := range xs {
		m[x] = true
	}
	out := make([]string, 0, len(m))
	for x := range m {
		out = append(out, x)
	}
	sort.Strings(out)
	return out
}

// StrictJSON checks duplicate keys before decoding, including unknown/nested
// objects. A map-based parser would irreversibly lose equal-key duplicates.
func StrictJSON(raw []byte, v any) error {
	d := json.NewDecoder(bytes.NewReader(raw))
	d.UseNumber()
	var value func() error
	value = func() error {
		tok, e := d.Token()
		if e != nil {
			return e
		}
		delim, ok := tok.(json.Delim)
		if !ok {
			return nil
		}
		switch delim {
		case '{':
			seen := map[string]bool{}
			for d.More() {
				key, e := d.Token()
				if e != nil {
					return e
				}
				s, ok := key.(string)
				if !ok || seen[s] {
					return errors.New("duplicate or invalid JSON key")
				}
				seen[s] = true
				if e = value(); e != nil {
					return e
				}
			}
			end, e := d.Token()
			if e != nil || end != json.Delim('}') {
				return errors.New("invalid JSON object")
			}
		case '[':
			for d.More() {
				if e = value(); e != nil {
					return e
				}
			}
			end, e := d.Token()
			if e != nil || end != json.Delim(']') {
				return errors.New("invalid JSON array")
			}
		default:
			return errors.New("unexpected JSON delimiter")
		}
		return nil
	}
	if e := value(); e != nil {
		return e
	}
	if _, e := d.Token(); e != io.EOF {
		return errors.New("trailing JSON content")
	}
	d = json.NewDecoder(bytes.NewReader(raw))
	d.UseNumber()
	d.DisallowUnknownFields()
	if e := d.Decode(v); e != nil {
		return e
	}
	return nil
}
func DecodePreferences(raw []byte) (Preferences, error) {
	var p Preferences
	if e := StrictJSON(raw, &p); e != nil {
		return p, e
	}
	if e := p.Validate(); e != nil {
		return p, e
	}
	return p.Normalized(), nil
}

type Requirements struct {
	Checks   []string `json:"checks"`
	Criteria string   `json:"criteria"`
	Grade    string   `json:"grade"`
}

func (r Requirements) Validate() error {
	if len(r.Checks) == 0 || r.Criteria == "" || r.Grade == "" {
		return errors.New("mandatory acceptance contract required")
	}
	for _, c := range r.Checks {
		if c == "" {
			return errors.New("empty mandatory check")
		}
	}
	return nil
}

type PolicyPatch struct {
	Run          Preferences   `json:"run"`
	Restrictions []Restriction `json:"restrictions,omitempty"`
	Required     Requirements  `json:"required"`
}

func (p PolicyPatch) Validate() error {
	if e := p.Run.Validate(); e != nil {
		return e
	}
	if e := p.Required.Validate(); e != nil {
		return e
	}
	for _, r := range p.Restrictions {
		if e := r.Validate(); e != nil {
			return e
		}
	}
	return nil
}
func (p PolicyPatch) Normalized() PolicyPatch {
	p.Run = p.Run.Normalized()
	p.Restrictions = normalizeRestrictions(p.Restrictions)
	p.Required.Checks = SortedSet(p.Required.Checks)
	return p
}

type PolicyRequest struct {
	Version         int         `json:"schema_version"`
	Root            string      `json:"root"`
	Predecessor     string      `json:"predecessor"`
	AuthorizationID string      `json:"authorization_id"`
	Patch           PolicyPatch `json:"patch"`
}

func (r PolicyRequest) Digest() (string, error) {
	if r.Version != 1 || !ValidRoot(r.Root) || r.AuthorizationID == "" {
		return "", errors.New("invalid policy authorization request")
	}
	if e := r.Patch.Validate(); e != nil {
		return "", e
	}
	r.Patch = r.Patch.Normalized()
	b, e := json.Marshal(r)
	return Digest(b), e
}

type Contribution struct {
	Class       string `json:"class"`
	Reference   string `json:"reference"`
	Digest      string `json:"digest"`
	Value       any    `json:"value"`
	Disposition string `json:"disposition"`
}
type Resolution struct {
	Category      string         `json:"category"`
	Rule          string         `json:"rule"`
	Contributions []Contribution `json:"contributions"`
}
type Policy struct {
	Version     int                   `json:"schema_version"`
	ID          string                `json:"id"`
	Controller  string                `json:"controller"`
	Root        string                `json:"root"`
	Predecessor string                `json:"predecessor"`
	Activation  string                `json:"activation"`
	Preferences Preferences           `json:"preferences"`
	Required    Requirements          `json:"required"`
	Permissions []string              `json:"permissions"`
	Denied      []string              `json:"denied"`
	Billing     []string              `json:"billing"`
	Ceilings    []Ceiling             `json:"ceilings"`
	Registry    string                `json:"registry"`
	Strategies  []string              `json:"strategies"`
	Provenance  map[string]Resolution `json:"provenance"`
}

func (p Policy) Identity() string {
	p.ID = ""
	b, e := json.Marshal(p)
	if e != nil {
		return ""
	}
	// Provenance values can be typed structs before persistence and maps after
	// decoding. Normalize object ordering without rounding numeric tokens.
	d := json.NewDecoder(bytes.NewReader(b))
	d.UseNumber()
	var value any
	if e = d.Decode(&value); e != nil {
		return ""
	}
	b, e = json.Marshal(value)
	if e != nil {
		return ""
	}
	return Digest(b)
}
func (p Policy) Validate() error {
	if p.Version != 1 || p.Controller == "" || p.ID == "" || p.ID != p.Identity() || p.Registry != RegistryID() {
		return errors.New("invalid typed policy identity/version/registry")
	}
	if p.Activation != "authorizer_boundary_unqualified" && p.Activation != "pending" && p.Activation != "active" {
		return errors.New("invalid policy activation")
	}
	if e := p.Preferences.Validate(); e != nil {
		return e
	}
	if e := p.Required.Validate(); e != nil {
		return e
	}
	for _, c := range p.Ceilings {
		if e := c.Validate(); e != nil {
			return e
		}
	}
	for _, id := range p.Strategies {
		if _, ok := registry[id]; !ok {
			return errors.New("unknown pinned strategy")
		}
	}
	return nil
}

type PolicyBinding struct {
	Version        int    `json:"schema_version"`
	Root           string `json:"root"`
	PolicyID       string `json:"policy_id"`
	Predecessor    string `json:"predecessor"`
	ActivePolicyID string `json:"active_policy_id"`
	Activation     string `json:"activation"`
}
type AmendmentResult struct {
	Version         int    `json:"schema_version"`
	Authorizer      string `json:"authorizer"`
	AuthorizationID string `json:"authorization_id"`
	Root            string `json:"root"`
	RequestDigest   string `json:"request_digest"`
	PolicyID        string `json:"policy_id"`
	Predecessor     string `json:"predecessor"`
	Activation      string `json:"activation"`
}

// Registry entries are data-only selections. The registry cannot be replaced by
// configuration, retrieved playbooks or runtime code. Bounds are fixture rules,
// not calibrated quality or cost promises.
type strategyRule struct {
	Min     int      `json:"min_breadth"`
	Max     int      `json:"max_breadth"`
	Effects []string `json:"effects"`
}

var registry = map[string]strategyRule{"focused@1": {1, 1, []string{"optional-exploration"}}, "balanced@1": {1, 2, []string{"optional-exploration"}}, "exploratory@1": {1, 3, []string{"optional-exploration"}}}

func RegistryID() string { b, _ := json.Marshal(registry); return "strategy-registry@1:" + Digest(b) }
func PresetStrategies(preset string) []string {
	switch preset {
	case "Conserve":
		return []string{"focused@1"}
	case "Accelerate":
		return []string{"balanced@1", "exploratory@1", "focused@1"}
	default:
		return []string{"balanced@1", "focused@1"}
	}
}

type StrategyProposal struct {
	Version    int    `json:"schema_version"`
	Strategy   string `json:"strategy"`
	Parameters struct {
		Breadth int `json:"breadth"`
	} `json:"parameters"`
	Reason string `json:"reason"`
}
type StrategySelection struct {
	Selected     string   `json:"selected"`
	Alternatives []string `json:"alternatives"`
	Rule         string   `json:"rule"`
	Reason       string   `json:"reason"`
	Parameters   any      `json:"parameters"`
}

func DecodeStrategy(raw []byte) (StrategyProposal, error) {
	var p StrategyProposal
	e := StrictJSON(raw, &p)
	return p, e
}
func SelectStrategy(p Policy, proposal StrategyProposal) (StrategySelection, error) {
	var result StrategySelection
	if e := p.Validate(); e != nil {
		return result, e
	}
	r, ok := registry[proposal.Strategy]
	allowed := false
	for _, id := range p.Strategies {
		if id == proposal.Strategy {
			allowed = true
		}
	}
	if proposal.Version != 1 || !ok || !allowed || proposal.Reason == "" || proposal.Parameters.Breadth < r.Min || proposal.Parameters.Breadth > r.Max {
		return result, fmt.Errorf("strategy outside immutable policy envelope")
	}
	result = StrategySelection{Selected: proposal.Strategy, Alternatives: append([]string(nil), p.Strategies...), Rule: p.Registry + "/" + proposal.Strategy, Reason: proposal.Reason, Parameters: proposal.Parameters}
	return result, nil
}
