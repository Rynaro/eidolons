package store

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"reflect"
	"sync"
	"testing"
	"time"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
	bolt "go.etcd.io/bbolt"
)

// The only trusted authorizer implementation is compiled into this test binary.
// Serialized labels, CLI flags and ordinary Store constructors cannot instantiate it.
type fixtureAuthorizer struct{ grants map[string]authorization }

func (f fixtureAuthorizer) authorize(id string) (authorization, error) {
	a, ok := f.grants[id]
	if !ok {
		return a, errors.New("missing designated authorizer")
	}
	return a, nil
}
func fixtureDB(t *testing.T) (*Store, string) {
	t.Helper()
	p := filepath.Join(t.TempDir(), "espaço 日本 state.db")
	if e := Create(p, "controller-local"); e != nil {
		t.Fatal(e)
	}
	s, e := Open(p, time.Second)
	if e != nil {
		t.Fatal(e)
	}
	t.Cleanup(func() { s.Close() })
	return s, p
}
func fixtureRoot(t *testing.T, s *Store, id string) {
	t.Helper()
	r := contract.Root{ID: id, Phase: "staged", Generation: "generation", Inventory: "inventory", Intents: []string{"unresolved-exposure"}, Evidence: []string{"consumed-receipt"}, PolicyRefs: []string{"legacy-policy"}}
	if e := s.Stage(r, nil); e != nil {
		t.Fatal(e)
	}
	if e := s.Activate(id, r.Generation, r.Inventory); e != nil {
		t.Fatal(e)
	}
}
func pref(preset string) contract.Preferences {
	return contract.Preferences{Version: 1, Preset: preset}
}
func required() contract.Requirements {
	return contract.Requirements{Checks: []string{"acceptance", "regression"}, Criteria: "criteria-digest", Grade: "fixture-only"}
}
func bound(scope string, n float64) contract.Ceiling {
	return contract.Ceiling{Resource: "tokens", Unit: "token", Pool: "pool", Interval: "run", Scope: scope, Limit: &n}
}
func request(id, pred string) contract.PolicyRequest {
	return contract.PolicyRequest{Version: 1, Root: "root", Predecessor: pred, AuthorizationID: id, Patch: contract.PolicyPatch{Run: pref("Balanced"), Required: required()}}
}
func authorize(t *testing.T, s *Store, r contract.PolicyRequest, quiescent bool) {
	t.Helper()
	d, e := r.Digest()
	if e != nil {
		t.Fatal(e)
	}
	a := authorization{Version: 1, ID: r.AuthorizationID, Root: r.Root, Predecessor: r.Predecessor, PatchDigest: d, Authorizer: "policy-amendment@1", Scope: "controller-local", NotBefore: time.Now().Add(-time.Hour), NotAfter: time.Now().Add(time.Hour), Quiescent: quiescent, Grant: grant{Permissions: []string{"read", "write"}, Billing: []string{"fixture"}, Ceilings: []contract.Ceiling{bound("task", 100)}, Sources: map[string]string{"permissions": "permissions-authorizer@1", "billing": "billing-authorizer@1", "ceilings": "ceilings-authorizer@1"}}}
	f, ok := s.authorizer.(fixtureAuthorizer)
	if !ok {
		f = fixtureAuthorizer{map[string]authorization{}}
	}
	f.grants[r.AuthorizationID] = a
	s.authorizer = f
}

func TestV407T01(t *testing.T) {
	s, _ := fixtureDB(t)
	other, _ := fixtureDB(t)
	for _, x := range []struct{ layer, preset string }{{"user", "Conserve"}, {"project", "Accelerate"}} {
		if _, e := s.UpdatePreferences(x.layer, 0, pref(x.preset)); e != nil {
			t.Fatal(e)
		}
	}
	p, e := s.Compile(contract.PolicyPatch{Run: pref("Balanced"), Required: required()})
	if e != nil {
		t.Fatal(e)
	}
	q, e := s.Compile(contract.PolicyPatch{Run: pref("Balanced"), Required: required()})
	if e != nil {
		t.Fatal(e)
	}
	if !reflect.DeepEqual(p, q) || p.Preferences.Preset != "Balanced" || len(p.Provenance["preset"].Contributions) != 4 {
		t.Fatalf("nondeterministic or incomplete provenance: %+v", p)
	}
	for i, c := range p.Provenance["preset"].Contributions {
		if c.Class != []string{"builtin", "user", "project", "run"}[i] || c.Digest == "" || c.Reference == "" {
			t.Fatalf("source attribution: %+v", c)
		}
	}
	if p.Activation != "authorizer_boundary_unqualified" {
		t.Fatal(p.Activation)
	}
	layers, e := other.ReadPreferences()
	if e != nil || layers["user"].Revision != 0 || layers["project"].Revision != 0 {
		t.Fatal("cross-controller preference leak")
	}
	snap, e := s.Snapshot()
	if e != nil || len(snap.Roots) != 0 {
		t.Fatal("preferences fabricated root")
	}
}
func TestV407T02(t *testing.T) {
	s, _ := fixtureDB(t)
	fixtureRoot(t, s, "root")
	r := request("grant", "")
	authorize(t, s, r, true)
	f := s.authorizer.(fixtureAuthorizer)
	a := f.grants["grant"]
	a.Grant.Ceilings = []contract.Ceiling{bound("task", 100), bound("project", 80), bound("account", 60), bound("window", 40), bound("concurrency", 4)}
	f.grants["grant"] = a
	s.authorizer = f
	r.Patch.Restrictions = []contract.Restriction{{Ceilings: []contract.Ceiling{bound("task", 30), bound("project", 20)}}}
	authorize(t, s, r, true)
	f = s.authorizer.(fixtureAuthorizer)
	a = f.grants["grant"]
	a.Grant.Ceilings = []contract.Ceiling{bound("task", 100), bound("project", 80), bound("account", 60), bound("window", 40), bound("concurrency", 4)}
	f.grants["grant"] = a
	result, e := s.ApplyPolicy("root", "generation", r)
	if e != nil {
		t.Fatal(e)
	}
	p, e := s.ReadPolicy(result.PolicyID)
	if e != nil {
		t.Fatal(e)
	}
	limits := map[string]float64{}
	for _, c := range p.Ceilings {
		limits[c.Scope] = *c.Limit
	}
	want := map[string]float64{"task": 30, "project": 20, "account": 60, "window": 40, "concurrency": 4}
	if !reflect.DeepEqual(limits, want) {
		t.Fatalf("ceilings collapsed/expanded: %v", limits)
	}
	unknown := request("unknown", result.PolicyID)
	unknown.Patch.Restrictions = []contract.Restriction{{Ceilings: []contract.Ceiling{{Resource: "tokens", Unit: "token", Pool: "pool", Interval: "run", Scope: "task"}}}}
	authorize(t, s, unknown, true)
	if _, e = s.ApplyPolicy("root", "generation", unknown); e == nil {
		t.Fatal("unknown bound admitted")
	}
}
func TestV407T03(t *testing.T) {
	s, _ := fixtureDB(t)
	fixtureRoot(t, s, "root")
	r := request("forged", "")
	if _, e := s.ApplyPolicy("root", "generation", r); e == nil || !bytes.Contains([]byte(e.Error()), []byte("authorizer_boundary_unqualified")) {
		t.Fatal("production accepted unqualified authorizer", e)
	}
	for _, source := range []string{"model", "repository", "recalled-note", "tool", "operator"} {
		raw := fmt.Sprintf(`{"schema_version":1,"preset":"Balanced","source":%q,"permissions":["write"]}`, source)
		if _, e := contract.DecodePreferences([]byte(raw)); e == nil {
			t.Fatalf("forged %s label supplied grants", source)
		}
	}
	authorize(t, s, r, true)
	first, e := s.ApplyPolicy("root", "generation", r)
	if e != nil {
		t.Fatal(e)
	}
	wider := request("wider", first.PolicyID)
	wider.Patch.Restrictions = []contract.Restriction{{Allowed: []string{"read", "admin"}}}
	authorize(t, s, wider, true)
	if _, e = s.ApplyPolicy("root", "generation", wider); e == nil {
		t.Fatal("restriction widened permissions")
	}
	ceiling := request("ceiling", first.PolicyID)
	ceiling.Patch.Restrictions = []contract.Restriction{{Ceilings: []contract.Ceiling{bound("task", 101)}}}
	authorize(t, s, ceiling, true)
	if _, e = s.ApplyPolicy("root", "generation", ceiling); e == nil {
		t.Fatal("restriction widened ceiling")
	}
}
func TestV407T04(t *testing.T) {
	s, p := fixtureDB(t)
	fixtureRoot(t, s, "root")
	fixtureRoot(t, s, "other")
	before, _ := s.Snapshot()
	r := request("first", "")
	authorize(t, s, r, true)
	first, e := s.ApplyPolicy("root", "generation", r)
	if e != nil {
		t.Fatal(e)
	}
	old, _ := s.ReadPolicy(first.PolicyID)
	if _, e = s.UpdatePreferences("project", 0, pref("Conserve")); e != nil {
		t.Fatal(e)
	}
	unchanged, _ := s.ReadPolicy(first.PolicyID)
	if !reflect.DeepEqual(old, unchanged) {
		t.Fatal("preferences mutated snapshot")
	}
	next := request("second", first.PolicyID)
	next.Patch.Run = pref("Accelerate")
	authorize(t, s, next, false)
	second, e := s.ApplyPolicy("root", "generation", next)
	if e != nil {
		t.Fatal(e)
	}
	b, e := s.ReadBinding("root")
	if e != nil || b.PolicyID != second.PolicyID || b.ActivePolicyID != first.PolicyID || b.Activation != "pending" {
		t.Fatalf("restriction implicitly revoked active worker: %+v %v", b, e)
	}
	replay, e := s.ApplyPolicy("root", "generation", r)
	if e != nil || !reflect.DeepEqual(replay, first) {
		t.Fatal("historical retry failed", e)
	}
	b, _ = s.ReadBinding("root")
	if b.PolicyID != second.PolicyID {
		t.Fatal("retry reactivated historical policy")
	}
	conflict := r
	conflict.Patch.Run = pref("Conserve")
	if _, e = s.ApplyPolicy("root", "generation", conflict); e == nil {
		t.Fatal("changed-patch ID reuse accepted")
	}
	cross := r
	cross.Root = "other"
	if _, e = s.ApplyPolicy("other", "generation", cross); e == nil {
		t.Fatal("cross-root authorization reuse accepted")
	}
	stale := request("stale", first.PolicyID)
	authorize(t, s, stale, true)
	if _, e = s.ApplyPolicy("root", "generation", stale); e == nil {
		t.Fatal("stale predecessor accepted")
	}
	after, _ := s.Snapshot()
	if !reflect.DeepEqual(before.Roots, after.Roots) {
		t.Fatal("policy changed consumption/exposure/root history")
	}
	cut := request("cut", second.PolicyID)
	authorize(t, s, cut, true)
	s.policyCut = func(phase string) error {
		if phase == "binding-written" {
			return errors.New("interrupted")
		}
		return nil
	}
	if _, e = s.ApplyPolicy("root", "generation", cut); e == nil {
		t.Fatal("cut failed to interrupt")
	}
	if _, e = s.ReadAmendment("policy-amendment@1", "cut"); e == nil {
		t.Fatal("rolled-back authorization consumed")
	}
	s.policyCut = nil
	if _, e = s.ApplyPolicy("root", "generation", cut); e != nil {
		t.Fatal(e)
	}
	s.Close()
	reopened, e := Open(p, time.Second)
	if e != nil {
		t.Fatal(e)
	}
	defer reopened.Close()
	if got, e := reopened.ReadPolicy(first.PolicyID); e != nil || !reflect.DeepEqual(got, old) {
		t.Fatal("policy missing after reopen", e)
	}
	if got, e := reopened.ReadAmendment("policy-amendment@1", "first"); e != nil || !reflect.DeepEqual(got, first) {
		t.Fatal("original result missing after reopen", e)
	}
}
func TestV407T05(t *testing.T) {
	var first contract.Policy
	for _, preset := range []string{"Conserve", "Balanced", "Accelerate"} {
		s, _ := fixtureDB(t)
		fixtureRoot(t, s, "root")
		r := request("preset", "")
		r.Patch.Run = pref(preset)
		authorize(t, s, r, true)
		res, e := s.ApplyPolicy("root", "generation", r)
		if e != nil {
			t.Fatal(e)
		}
		p, _ := s.ReadPolicy(res.PolicyID)
		if first.ID == "" {
			first = p
		} else if !reflect.DeepEqual(first.Required, p.Required) || !reflect.DeepEqual(first.Permissions, p.Permissions) || !reflect.DeepEqual(first.Billing, p.Billing) || !reflect.DeepEqual(first.Ceilings, p.Ceilings) {
			t.Fatal("preset changed mandatory contract")
		}
		if p.Registry == "" || len(p.Strategies) == 0 {
			t.Fatal("unpinned strategies")
		}
	}
}
func TestV407T06(t *testing.T) {
	s, _ := fixtureDB(t)
	if _, e := s.UpdatePreferences("user", 0, pref("Balanced")); e != nil {
		t.Fatal(e)
	}
	before, _ := s.ReadPreferences()
	invalid := []string{`{"schema_version":1,"preset":"Balanced","preset":"Conserve"}`, `{"schema_version":1,"preset":"Balanced","restrictions":[{"denied":["write"],"denied":[]}]}`, `{"schema_version":99}`, `{"schema_version":1,"preset":"turbo"}`, `{"schema_version":1,"ceilings":[{"limit":-1}]}`, `{"schema_version":1,"preset":NaN}`, `{"schema_version":1} {"schema_version":1}`, `{"schema_version":1,"source":"operator"}`}
	for _, raw := range invalid {
		if _, e := contract.DecodePreferences([]byte(raw)); e == nil {
			t.Fatalf("invalid config accepted: %s", raw)
		}
	}
	bad := pref("Balanced")
	bad.Restrictions = []contract.Restriction{{Ceilings: []contract.Ceiling{bound("task", math.Inf(1))}}}
	if _, e := s.UpdatePreferences("user", 1, bad); e == nil {
		t.Fatal("nonfinite accepted")
	}
	if _, e := s.UpdatePreferences("user", 0, pref("Conserve")); e == nil {
		t.Fatal("CAS lost update")
	}
	s.policyCut = func(string) error { return errors.New("interrupt") }
	if _, e := s.UpdatePreferences("user", 1, pref("Conserve")); e == nil {
		t.Fatal("interrupted persisted")
	}
	s.policyCut = nil
	after, _ := s.ReadPreferences()
	if !reflect.DeepEqual(before, after) {
		t.Fatal("failed write mutated preferences")
	}
	var wg sync.WaitGroup
	results := make(chan error, 2)
	for _, preset := range []string{"Conserve", "Accelerate"} {
		wg.Add(1)
		go func(p string) { defer wg.Done(); _, e := s.UpdatePreferences("user", 1, pref(p)); results <- e }(preset)
	}
	wg.Wait()
	close(results)
	success := 0
	for e := range results {
		if e == nil {
			success++
		}
	}
	if success != 1 {
		t.Fatal("concurrent CAS accepted", success)
	}
}
func TestV407T07(t *testing.T) {
	s, _ := fixtureDB(t)
	fixtureRoot(t, s, "root")
	r := request("missing", "")
	r.Patch.Restrictions = []contract.Restriction{{Allowed: []string{"read"}, Denied: []string{"write"}}}
	authorize(t, s, r, true)
	f := s.authorizer.(fixtureAuthorizer)
	a := f.grants["missing"]
	delete(a.Grant.Sources, "permissions")
	f.grants["missing"] = a
	if _, e := s.ApplyPolicy("root", "generation", r); e == nil {
		t.Fatal("restriction populated missing grant")
	}
	r.AuthorizationID = "wrong"
	authorize(t, s, r, true)
	f = s.authorizer.(fixtureAuthorizer)
	a = f.grants["wrong"]
	a.Grant.Sources["permissions"] = "billing-authorizer@1"
	f.grants["wrong"] = a
	if _, e := s.ApplyPolicy("root", "generation", r); e == nil {
		t.Fatal("wrong designated authorizer accepted")
	}
	r.AuthorizationID = "good"
	authorize(t, s, r, true)
	res, e := s.ApplyPolicy("root", "generation", r)
	if e != nil {
		t.Fatal(e)
	}
	p, _ := s.ReadPolicy(res.PolicyID)
	if !reflect.DeepEqual(p.Permissions, []string{"read"}) || !reflect.DeepEqual(p.Denied, []string{"write"}) {
		t.Fatal("restriction composition failed")
	}
	for _, fault := range []string{"root", "digest", "scope", "expired"} {
		q := request(fault, res.PolicyID)
		authorize(t, s, q, true)
		f = s.authorizer.(fixtureAuthorizer)
		a = f.grants[fault]
		switch fault {
		case "root":
			a.Root = "other"
		case "digest":
			a.PatchDigest = "forged"
		case "scope":
			a.Scope = "account-global"
		case "expired":
			a.NotAfter = time.Now().Add(-time.Hour)
		}
		f.grants[fault] = a
		if _, e := s.ApplyPolicy("root", "generation", q); e == nil {
			t.Fatal("authorization binding accepted", fault)
		}
	}
}
func TestV407T08(t *testing.T) {
	s, _ := fixtureDB(t)
	p, e := s.Compile(contract.PolicyPatch{Run: pref("Balanced"), Required: required()})
	if e != nil {
		t.Fatal(e)
	}
	good := []byte(`{"schema_version":1,"strategy":"focused@1","parameters":{"breadth":1},"reason":"observable remaining budget"}`)
	proposal, e := contract.DecodeStrategy(good)
	if e != nil {
		t.Fatal(e)
	}
	selection, e := contract.SelectStrategy(p, proposal)
	if e != nil || selection.Selected != "focused@1" || selection.Rule == "" || len(selection.Alternatives) == 0 {
		t.Fatal("registered selection failed", e)
	}
	for _, raw := range []string{`{"schema_version":1,"strategy":"execute@1","reason":"x"}`, `{"schema_version":1,"strategy":"focused@1","parameters":{"breadth":999},"reason":"x"}`, `{"schema_version":1,"strategy":"focused@1","code":"exec(x)","reason":"x"}`, `{"schema_version":1,"strategy":"focused@1","permissions":["admin"],"reason":"x"}`, `{"schema_version":1,"strategy":"focused@1","criteria":"weaker","reason":"x"}`, `{"schema_version":1,"strategy":"focused@1","parameters":{"breadth":1,"breadth":2},"reason":"x"}`} {
		v, e := contract.DecodeStrategy([]byte(raw))
		if e == nil {
			_, e = contract.SelectStrategy(p, v)
		}
		if e == nil {
			t.Fatal("protected proposal accepted", raw)
		}
	}
}

func TestV407Migration(t *testing.T) {
	// Construct the exact schema1 namespaces and historical records, independently
	// of the new Create implementation. Old-binary integration runs separately.
	makeOld := func() string {
		p := filepath.Join(t.TempDir(), "old.db")
		d, e := bolt.Open(p, 0600, nil)
		if e != nil {
			t.Fatal(e)
		}
		e = d.Update(func(tx *bolt.Tx) error {
			for _, name := range []string{"meta", "roots", "legacy", "history", "context", "knowledge", "policy", "operations"} {
				if _, e := tx.CreateBucket([]byte(name)); e != nil {
					return e
				}
			}
			tx.Bucket([]byte("meta")).Put([]byte("schema"), []byte("1"))
			return tx.Bucket([]byte("meta")).Put([]byte("store_id"), []byte("old-controller"))
		})
		d.Close()
		if e != nil {
			t.Fatal(e)
		}
		return p
	}
	p := makeOld()
	before, _ := os.ReadFile(p)
	if _, e := Inspect(p, time.Second); e == nil || !bytes.Contains([]byte(e.Error()), []byte("migration_required")) {
		t.Fatal("ordinary open migrated", e)
	}
	after, _ := os.ReadFile(p)
	if !bytes.Equal(before, after) {
		t.Fatal("read changed schema1")
	}
	if e := migrate(p, time.Second, nil, func(string) error { return errors.New("cut") }); e == nil {
		t.Fatal("cut migration accepted")
	}
	if _, e := InspectPredecessor(p, time.Second); e != nil {
		t.Fatal("migration failure lost old state", e)
	}
	if e := Migrate(p, time.Second, nil); e != nil {
		t.Fatal(e)
	}
	if _, e := Inspect(p, time.Second); e != nil {
		t.Fatal(e)
	}
	if e := Migrate(p, time.Second, nil); e == nil {
		t.Fatal("migration reaccepted nonpredecessor")
	}
	for _, fault := range []string{"receipt", "namespace", "version"} {
		s, path := fixtureDB(t)
		if e := s.db.Update(func(tx *bolt.Tx) error {
			switch fault {
			case "receipt":
				return tx.Bucket([]byte("meta")).Delete([]byte("migration_receipt"))
			case "namespace":
				return tx.DeleteBucket([]byte("preferences"))
			default:
				r := contract.PreferenceDocument{Version: 99, Layer: "user", Controller: "controller-local", Values: pref("Balanced")}
				raw, _ := json.Marshal(r)
				return tx.Bucket([]byte("preferences")).Put([]byte("user"), raw)
			}
		}); e != nil {
			t.Fatal(e)
		}
		s.Close()
		raw, _ := os.ReadFile(path)
		if _, e := Inspect(path, time.Second); e == nil {
			t.Fatal("invalid typed state opened", fault)
		}
		got, _ := os.ReadFile(path)
		if !bytes.Equal(raw, got) {
			t.Fatal("refusal repaired store")
		}
	}
}
