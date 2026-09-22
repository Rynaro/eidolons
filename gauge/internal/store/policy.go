package store

import (
	"encoding/json"
	"errors"
	"fmt"
	"reflect"
	"sort"
	"time"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
	bolt "go.etcd.io/bbolt"
)

var policyBuckets = []string{"preferences", "effective_policies", "policy_bindings", "amendment_results"}

type migrationReceipt struct {
	Version    int    `json:"schema_version"`
	From       int    `json:"from"`
	To         int    `json:"to"`
	Controller string `json:"controller"`
	Kind       string `json:"kind"`
}

func putJSON(b *bolt.Bucket, key string, value any) error {
	raw, e := json.Marshal(value)
	if e != nil {
		return e
	}
	return b.Put([]byte(key), raw)
}
func initializePolicy(tx *bolt.Tx, id, kind string) error {
	for _, name := range policyBuckets {
		if _, e := tx.CreateBucket([]byte(name)); e != nil {
			return e
		}
	}
	from := 1
	if kind == "new-store" {
		from = 0
	}
	if e := putJSON(tx.Bucket([]byte("meta")), "migration_receipt", migrationReceipt{1, from, 2, id, kind}); e != nil {
		return e
	}
	for _, layer := range []string{"user", "project"} {
		p := contract.Preferences{Version: 1}
		d := contract.PreferenceDocument{Version: 1, Controller: id, Layer: layer, Values: p, Digest: p.Identity()}
		if e := putJSON(tx.Bucket([]byte("preferences")), layer, d); e != nil {
			return e
		}
	}
	return nil
}
func guardPolicy(tx *bolt.Tx) error {
	for _, name := range policyBuckets {
		if tx.Bucket([]byte(name)) == nil {
			return fmt.Errorf("missing typed namespace %s", name)
		}
	}
	id := string(tx.Bucket([]byte("meta")).Get([]byte("store_id")))
	var receipt migrationReceipt
	if e := contract.StrictJSON(tx.Bucket([]byte("meta")).Get([]byte("migration_receipt")), &receipt); e != nil {
		return errors.New("missing or invalid migration receipt")
	}
	if receipt.Version != 1 || receipt.To != 2 || receipt.Controller != id || !((receipt.From == 0 && receipt.Kind == "new-store") || (receipt.From == 1 && receipt.Kind == "migration")) {
		return errors.New("unsupported migration receipt")
	}
	if _, e := readPreferences(tx); e != nil {
		return e
	}
	if e := tx.Bucket([]byte("effective_policies")).ForEach(func(k, v []byte) error {
		var p contract.Policy
		if e := contract.StrictJSON(v, &p); e != nil {
			return e
		}
		if p.ID != string(k) || p.Controller != id {
			return errors.New("policy identity mismatch")
		}
		return p.Validate()
	}); e != nil {
		return e
	}
	if e := tx.Bucket([]byte("policy_bindings")).ForEach(func(k, v []byte) error {
		var b contract.PolicyBinding
		if e := contract.StrictJSON(v, &b); e != nil {
			return e
		}
		if b.Version != 1 || b.Root != string(k) || tx.Bucket([]byte("roots")).Get(k) == nil {
			return errors.New("invalid policy binding")
		}
		p, e := readPolicy(tx, b.PolicyID)
		if e != nil {
			return e
		}
		if p.Root != b.Root || p.Predecessor != b.Predecessor || p.Activation != b.Activation {
			return errors.New("binding/policy mismatch")
		}
		if b.ActivePolicyID != "" {
			active, e := readPolicy(tx, b.ActivePolicyID)
			if e != nil {
				return e
			}
			if active.Root != b.Root || active.Activation != "active" {
				return errors.New("invalid active policy reference")
			}
		}
		return nil
	}); e != nil {
		return e
	}
	return tx.Bucket([]byte("amendment_results")).ForEach(func(k, v []byte) error {
		var r contract.AmendmentResult
		if e := contract.StrictJSON(v, &r); e != nil {
			return e
		}
		if r.Version != 1 || r.Authorizer != "policy-amendment@1" || r.AuthorizationID == "" || string(k) != authorizationKey(r.Authorizer, r.AuthorizationID) || r.RequestDigest == "" {
			return errors.New("invalid amendment result")
		}
		p, e := readPolicy(tx, r.PolicyID)
		if e != nil {
			return e
		}
		if p.Root != r.Root || p.Predecessor != r.Predecessor || p.Activation != r.Activation {
			return errors.New("amendment result/policy mismatch")
		}
		return nil
	})
}
func readPreferences(tx *bolt.Tx) (map[string]contract.PreferenceDocument, error) {
	result := map[string]contract.PreferenceDocument{}
	b := tx.Bucket([]byte("preferences"))
	if b == nil {
		return result, errors.New("missing preferences")
	}
	// Bucket statistics need not include writes in this transaction. Walk the
	// current keys so migration can validate its newly created layers.
	count := 0
	if e := b.ForEach(func(k, v []byte) error {
		if v == nil || (string(k) != "user" && string(k) != "project") {
			return errors.New("unknown/missing preference layer")
		}
		count++
		return nil
	}); e != nil {
		return result, e
	}
	if count != 2 {
		return result, errors.New("unknown/missing preference layer")
	}
	for _, layer := range []string{"user", "project"} {
		var d contract.PreferenceDocument
		if e := contract.StrictJSON(b.Get([]byte(layer)), &d); e != nil {
			return result, e
		}
		if d.Version != 1 || d.Layer != layer || d.Controller != string(tx.Bucket([]byte("meta")).Get([]byte("store_id"))) || d.Digest != d.Values.Identity() {
			return result, errors.New("invalid typed preference record")
		}
		if e := d.Values.Validate(); e != nil {
			return result, e
		}
		result[layer] = d
	}
	return result, nil
}
func (s *Store) ReadPreferences() (map[string]contract.PreferenceDocument, error) {
	var result map[string]contract.PreferenceDocument
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := guard(tx); e != nil {
			return e
		}
		var e error
		result, e = readPreferences(tx)
		return e
	})
	return result, e
}
func (s *Store) UpdatePreferences(layer string, expected uint64, replacement contract.Preferences) (contract.PreferenceDocument, error) {
	var result contract.PreferenceDocument
	if layer != "user" && layer != "project" {
		return result, errors.New("layer must be controller-local user or project")
	}
	if e := replacement.Validate(); e != nil {
		return result, e
	}
	replacement = replacement.Normalized()
	e := s.db.Update(func(tx *bolt.Tx) error {
		if e := guard(tx); e != nil {
			return e
		}
		layers, e := readPreferences(tx)
		if e != nil {
			return e
		}
		previous := layers[layer]
		if previous.Revision != expected || expected == ^uint64(0) {
			return errors.New("preference revision conflict")
		}
		result = contract.PreferenceDocument{Version: 1, Controller: previous.Controller, Layer: layer, Revision: expected + 1, Values: replacement, Digest: replacement.Identity()}
		if e = putJSON(tx.Bucket([]byte("preferences")), layer, result); e != nil {
			return e
		}
		if s.policyCut != nil {
			return s.policyCut("preferences-written")
		}
		return nil
	})
	if e != nil {
		return contract.PreferenceDocument{}, e
	}
	return result, nil
}

// No production constructor supplies this private capability. Fixture tests
// implement it in _test.go only. Database ownership and serialized records are
// deliberately insufficient to create authority.
type policyAuthorizer interface {
	authorize(string) (authorization, error)
}
type grant struct {
	Permissions []string
	Billing     []string
	Ceilings    []contract.Ceiling
	Sources     map[string]string
}
type authorization struct {
	Version                                               int
	ID, Root, Predecessor, PatchDigest, Authorizer, Scope string
	NotBefore, NotAfter                                   time.Time
	Quiescent                                             bool
	Grant                                                 grant
}

func (a authorization) validate(r contract.PolicyRequest, digest, controller string) error {
	now := time.Now()
	if a.Version != 1 || a.ID != r.AuthorizationID || a.Root != r.Root || a.Predecessor != r.Predecessor || a.PatchDigest != digest || a.Authorizer != "policy-amendment@1" || a.Scope != controller || now.Before(a.NotBefore) || !now.Before(a.NotAfter) {
		return errors.New("authorization request/scope/validity mismatch")
	}
	for field, id := range map[string]string{"permissions": "permissions-authorizer@1", "billing": "billing-authorizer@1", "ceilings": "ceilings-authorizer@1"} {
		if a.Grant.Sources[field] != id {
			return fmt.Errorf("missing designated authorizer for %s", field)
		}
	}
	if a.Grant.Permissions == nil || a.Grant.Billing == nil || a.Grant.Ceilings == nil {
		return errors.New("missing trusted field grant")
	}
	for _, c := range a.Grant.Ceilings {
		if e := c.Validate(); e != nil {
			return e
		}
		if c.Limit == nil {
			return errors.New("unknown hard bound blocks admission")
		}
	}
	return nil
}
func contribution(class, ref, digest string, value any) contract.Contribution {
	return contract.Contribution{Class: class, Reference: ref, Digest: digest, Value: value, Disposition: "intersected"}
}
func intersection(current, restriction []string) ([]string, error) {
	if restriction == nil {
		return current, nil
	}
	set := map[string]bool{}
	for _, v := range current {
		set[v] = true
	}
	for _, v := range restriction {
		if !set[v] {
			return nil, errors.New("restriction requested privilege escalation")
		}
	}
	return contract.SortedSet(restriction), nil
}
func intersectSets(a, b []string) []string {
	if b == nil {
		return a
	}
	keep := map[string]bool{}
	for _, v := range b {
		keep[v] = true
	}
	out := []string{}
	for _, v := range a {
		if keep[v] {
			out = append(out, v)
		}
	}
	return out
}
func compile(tx *bolt.Tx, patch contract.PolicyPatch, g *grant) (contract.Policy, error) {
	var p contract.Policy
	if e := patch.Validate(); e != nil {
		return p, e
	}
	patch = patch.Normalized()
	layers, e := readPreferences(tx)
	if e != nil {
		return p, e
	}
	id := string(tx.Bucket([]byte("meta")).Get([]byte("store_id")))
	p = contract.Policy{Version: 1, Controller: id, Activation: "authorizer_boundary_unqualified", Preferences: contract.Preferences{Version: 1, Preset: "Balanced"}, Required: patch.Required, Registry: contract.RegistryID(), Provenance: map[string]contract.Resolution{}}
	docs := []struct {
		class, ref, digest string
		values             contract.Preferences
	}{{"builtin", "builtin-preferences@1", contract.Preferences{Version: 1, Preset: "Balanced"}.Identity(), contract.Preferences{Version: 1, Preset: "Balanced"}}}
	for _, layer := range []string{"user", "project"} {
		d := layers[layer]
		docs = append(docs, struct {
			class, ref, digest string
			values             contract.Preferences
		}{layer, fmt.Sprintf("%s/%s/%d", id, layer, d.Revision), d.Digest, d.Values})
	}
	docs = append(docs, struct {
		class, ref, digest string
		values             contract.Preferences
	}{"run", "explicit-run@1", patch.Run.Identity(), patch.Run})
	resolution := contract.Resolution{Category: "preference", Rule: "builtin < user < project < run"}
	winner := -1
	type sourcedRestriction struct {
		r contract.Restriction
		c contract.Contribution
	}
	restrictions := []sourcedRestriction{}
	for _, d := range docs {
		if d.values.Preset != "" {
			c := contribution(d.class, d.ref, d.digest, d.values.Preset)
			c.Disposition = "overridden"
			resolution.Contributions = append(resolution.Contributions, c)
			winner = len(resolution.Contributions) - 1
			p.Preferences.Preset = d.values.Preset
		}
		for _, r := range d.values.Restrictions {
			restrictions = append(restrictions, sourcedRestriction{r, contribution(d.class, d.ref, d.digest, r)})
		}
	}
	resolution.Contributions[winner].Disposition = "winner"
	p.Provenance["preset"] = resolution
	b, _ := json.Marshal(patch.Restrictions)
	for _, r := range patch.Restrictions {
		restrictions = append(restrictions, sourcedRestriction{r, contribution("run", "explicit-restriction@1", contract.Digest(b), r)})
	}
	p.Strategies = contract.PresetStrategies(p.Preferences.Preset)
	reqBytes, _ := json.Marshal(p.Required)
	p.Provenance["required"] = contract.Resolution{Category: "mandatory", Rule: "immutable acceptance contract; not a grant", Contributions: []contract.Contribution{contribution("run", "required-acceptance@1", contract.Digest(reqBytes), p.Required)}}
	p.Provenance["strategies"] = contract.Resolution{Category: "optional", Rule: "preset selection within pinned registry", Contributions: []contract.Contribution{contribution("builtin", p.Registry, contract.Digest([]byte(p.Registry)), p.Strategies)}}
	for _, field := range []string{"permissions", "billing", "ceilings", "denied"} {
		p.Provenance[field] = contract.Resolution{Category: "authority", Rule: "designated grant then intersection; denies accumulate"}
	}
	bounds := map[string]contract.Ceiling{}
	trustedBounds := map[string]contract.Ceiling{}
	if g != nil {
		for _, c := range g.Ceilings {
			if old, ok := trustedBounds[c.Key()]; !ok || *c.Limit < *old.Limit {
				trustedBounds[c.Key()] = c
			}
		}
		p.Permissions = contract.SortedSet(g.Permissions)
		p.Billing = contract.SortedSet(g.Billing)
		for _, c := range g.Ceilings {
			if old, ok := bounds[c.Key()]; !ok || *c.Limit < *old.Limit {
				bounds[c.Key()] = c
			}
		}
		for field, value := range map[string]any{"permissions": p.Permissions, "billing": p.Billing, "ceilings": g.Ceilings} {
			raw, _ := json.Marshal(value)
			r := p.Provenance[field]
			r.Contributions = append(r.Contributions, contribution("trusted-authorizer", g.Sources[field], contract.Digest(raw), value))
			p.Provenance[field] = r
		}
	}
	for _, item := range restrictions {
		r := item.r
		for field, value := range map[string]any{"permissions": r.Allowed, "denied": r.Denied, "billing": r.Billing, "ceilings": r.Ceilings} {
			c := item.c
			c.Value = value
			res := p.Provenance[field]
			res.Contributions = append(res.Contributions, c)
			p.Provenance[field] = res
		}
		if g != nil {
			if _, e = intersection(g.Permissions, r.Allowed); e != nil {
				return p, e
			}
			if _, e = intersection(g.Billing, r.Billing); e != nil {
				return p, e
			}
			p.Permissions = intersectSets(p.Permissions, r.Allowed)
			p.Billing = intersectSets(p.Billing, r.Billing)
		}
		p.Denied = append(p.Denied, r.Denied...)
		for _, c := range r.Ceilings {
			if trusted, ok := trustedBounds[c.Key()]; ok && c.Limit != nil && *c.Limit > *trusted.Limit {
				return p, errors.New("restriction requested ceiling escalation")
			}
			if old, ok := bounds[c.Key()]; ok {
				if c.Limit == nil || old.Limit == nil {
					c.Limit = nil
				} else if *old.Limit < *c.Limit {
					c = old
				}
			}
			bounds[c.Key()] = c
		}
	}
	p.Denied = contract.SortedSet(p.Denied)
	denied := map[string]bool{}
	for _, v := range p.Denied {
		denied[v] = true
	}
	allowed := []string{}
	for _, v := range p.Permissions {
		if !denied[v] {
			allowed = append(allowed, v)
		}
	}
	p.Permissions = allowed
	keys := make([]string, 0, len(bounds))
	for k := range bounds {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		p.Ceilings = append(p.Ceilings, bounds[k])
	}
	if g != nil {
		for _, c := range p.Ceilings {
			if c.Limit == nil {
				return p, errors.New("unknown hard bound blocks admission")
			}
		}
	}
	p.ID = p.Identity()
	return p, nil
}
func (s *Store) Compile(patch contract.PolicyPatch) (contract.Policy, error) {
	var result contract.Policy
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := guard(tx); e != nil {
			return e
		}
		var e error
		result, e = compile(tx, patch, nil)
		return e
	})
	return result, e
}
func authorizationKey(authorizer, id string) string {
	raw, _ := json.Marshal([]string{authorizer, id})
	return string(raw)
}
func readPolicy(tx *bolt.Tx, id string) (contract.Policy, error) {
	var p contract.Policy
	raw := tx.Bucket([]byte("effective_policies")).Get([]byte(id))
	if raw == nil {
		return p, errors.New("unknown typed policy")
	}
	if e := contract.StrictJSON(raw, &p); e != nil {
		return p, e
	}
	return p, p.Validate()
}
func (s *Store) ReadPolicy(id string) (contract.Policy, error) {
	var p contract.Policy
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := guard(tx); e != nil {
			return e
		}
		var e error
		p, e = readPolicy(tx, id)
		return e
	})
	return p, e
}
func (s *Store) ReadBinding(root string) (contract.PolicyBinding, error) {
	var b contract.PolicyBinding
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := guard(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("policy_bindings")).Get([]byte(root))
		if raw == nil {
			return errors.New("root has no V4-07 binding")
		}
		return contract.StrictJSON(raw, &b)
	})
	return b, e
}
func (s *Store) ReadAmendment(authorizer, id string) (contract.AmendmentResult, error) {
	var r contract.AmendmentResult
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := guard(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("amendment_results")).Get([]byte(authorizationKey(authorizer, id)))
		if raw == nil {
			return errors.New("unknown authorization result")
		}
		return contract.StrictJSON(raw, &r)
	})
	return r, e
}

// ApplyPolicy is a narrow typed transaction. Even direct callers cannot grant
// policy using root generations or JSON: production stores have no authorizer.
func (s *Store) ApplyPolicy(id, generation string, request contract.PolicyRequest) (contract.AmendmentResult, error) {
	var result contract.AmendmentResult
	digest, e := request.Digest()
	if e != nil {
		return result, e
	}
	if request.Root != id {
		return result, errors.New("request root mismatch")
	}
	e = s.db.Update(func(tx *bolt.Tx) error {
		if e := guard(tx); e != nil {
			return e
		}
		root, e := getRoot(tx, id)
		if e != nil {
			return e
		}
		if root.Phase != "active" || root.Generation != generation {
			return errors.New("execution authority unavailable")
		}
		key := authorizationKey("policy-amendment@1", request.AuthorizationID)
		results := tx.Bucket([]byte("amendment_results"))
		// Durable historical result lookup precedes today's predecessor comparison.
		if old := results.Get([]byte(key)); old != nil {
			if e := contract.StrictJSON(old, &result); e != nil {
				return e
			}
			if result.Root != id || result.RequestDigest != digest || result.Predecessor != request.Predecessor {
				return errors.New("authorization identity conflict")
			}
			return nil
		}
		if s.authorizer == nil {
			return errors.New("authorizer_boundary_unqualified")
		}
		a, e := s.authorizer.authorize(request.AuthorizationID)
		if e != nil {
			return e
		}
		if e = a.validate(request, digest, string(tx.Bucket([]byte("meta")).Get([]byte("store_id")))); e != nil {
			return e
		}
		var binding contract.PolicyBinding
		if raw := tx.Bucket([]byte("policy_bindings")).Get([]byte(id)); raw != nil {
			if e = contract.StrictJSON(raw, &binding); e != nil {
				return e
			}
		}
		if binding.PolicyID != request.Predecessor {
			return errors.New("expected predecessor conflict")
		}
		if binding.PolicyID != "" {
			previous, e := readPolicy(tx, binding.PolicyID)
			if e != nil {
				return e
			}
			if !reflect.DeepEqual(previous.Required, request.Patch.Normalized().Required) {
				return errors.New("acceptance changes require separate lifecycle and evidence invalidation")
			}
		}
		p, e := compile(tx, request.Patch, &a.Grant)
		if e != nil {
			return e
		}
		p.Root = id
		p.Predecessor = request.Predecessor
		p.Activation = "pending"
		if a.Quiescent {
			p.Activation = "active"
		}
		p.ID = p.Identity()
		if e = p.Validate(); e != nil {
			return e
		}
		policies := tx.Bucket([]byte("effective_policies"))
		if policies.Get([]byte(p.ID)) != nil {
			return errors.New("immutable policy identity conflict")
		}
		if e = putJSON(policies, p.ID, p); e != nil {
			return e
		}
		if s.policyCut != nil {
			if e = s.policyCut("snapshot-written"); e != nil {
				return e
			}
		}
		result = contract.AmendmentResult{Version: 1, Authorizer: a.Authorizer, AuthorizationID: a.ID, Root: id, RequestDigest: digest, PolicyID: p.ID, Predecessor: p.Predecessor, Activation: p.Activation}
		if e = putJSON(results, key, result); e != nil {
			return e
		}
		if s.policyCut != nil {
			if e = s.policyCut("authorization-consumed"); e != nil {
				return e
			}
		}
		active := binding.ActivePolicyID
		if a.Quiescent {
			active = p.ID
		}
		binding = contract.PolicyBinding{Version: 1, Root: id, PolicyID: p.ID, Predecessor: p.Predecessor, ActivePolicyID: active, Activation: p.Activation}
		if e = putJSON(tx.Bucket([]byte("policy_bindings")), id, binding); e != nil {
			return e
		}
		if s.policyCut != nil {
			return s.policyCut("binding-written")
		}
		return nil
	})
	if e != nil {
		return contract.AmendmentResult{}, e
	}
	return result, nil
}
