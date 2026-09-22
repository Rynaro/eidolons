package store

import (
	"encoding/json"
	"errors"
	"fmt"
	"github.com/Rynaro/eidolons/gauge/internal/contract"
	bolt "go.etcd.io/bbolt"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"
)

type reviewAuth map[string]authorization

func (a reviewAuth) authorize(id string) (authorization, error) {
	v, ok := a[id]
	if !ok {
		return v, errors.New("absent")
	}
	return v, nil
}
func reviewStore(t *testing.T) (*Store, string) {
	t.Helper()
	path := filepath.Join(t.TempDir(), "db")
	if e := Create(path, "review-controller"); e != nil {
		t.Fatal(e)
	}
	s, e := Open(path, time.Second)
	if e != nil {
		t.Fatal(e)
	}
	t.Cleanup(func() { s.Close() })
	return s, path
}
func reviewRoot(t *testing.T, s *Store, id string) {
	t.Helper()
	r := contract.Root{ID: id, Phase: "staged", Generation: "gen", Inventory: "inventory"}
	if e := s.Stage(r, nil); e != nil {
		t.Fatal(e)
	}
	if e := s.Activate(id, "gen", "inventory"); e != nil {
		t.Fatal(e)
	}
}
func reviewPatch() contract.PolicyPatch {
	return contract.PolicyPatch{Run: contract.Preferences{Version: 1, Preset: "Balanced"}, Required: contract.Requirements{Checks: []string{"verify"}, Criteria: "fixed", Grade: "fixture"}}
}
func reviewGrant() grant {
	return grant{Permissions: []string{"read", "write", "execute"}, Billing: []string{"pool-a", "pool-b"}, Ceilings: []contract.Ceiling{}, Sources: map[string]string{"permissions": "permissions-authorizer@1", "billing": "billing-authorizer@1", "ceilings": "ceilings-authorizer@1"}}
}
func reviewRequest(root, id, prior string) contract.PolicyRequest {
	return contract.PolicyRequest{Version: 1, Root: root, AuthorizationID: id, Predecessor: prior, Patch: reviewPatch()}
}
func reviewAuthorize(t *testing.T, s *Store, r contract.PolicyRequest, g grant) {
	t.Helper()
	d, e := r.Digest()
	if e != nil {
		t.Fatal(e)
	}
	a, ok := s.authorizer.(reviewAuth)
	if !ok {
		a = reviewAuth{}
		s.authorizer = a
	}
	a[r.AuthorizationID] = authorization{Version: 1, ID: r.AuthorizationID, Root: r.Root, Predecessor: r.Predecessor, PatchDigest: d, Authorizer: "policy-amendment@1", Scope: "review-controller", NotBefore: time.Now().Add(-time.Hour), NotAfter: time.Now().Add(time.Hour), Quiescent: true, Grant: g}
}
func reviewApply(t *testing.T, s *Store, r contract.PolicyRequest) contract.AmendmentResult {
	t.Helper()
	reviewAuthorize(t, s, r, reviewGrant())
	v, e := s.ApplyPolicy(r.Root, "gen", r)
	if e != nil {
		t.Fatal(e)
	}
	return v
}
func TestReviewerEmptySetPersistence(t *testing.T) {
	for _, field := range []string{"allowed", "billing"} {
		t.Run(field, func(t *testing.T) {
			p, e := contract.DecodePreferences([]byte(fmt.Sprintf(`{"schema_version":1,"restrictions":[{"%s":[]}]}`, field)))
			if e != nil {
				t.Fatal(e)
			}
			s, _ := reviewStore(t)
			reviewRoot(t, s, "root")
			r := reviewRequest("root", "direct", "")
			r.Patch.Run = p
			v := reviewApply(t, s, r)
			direct, e := s.ReadPolicy(v.PolicyID)
			if e != nil {
				t.Fatal(e)
			}
			_, e = s.UpdatePreferences("user", 0, p)
			if e != nil {
				t.Fatal(e)
			}
			docs, e := s.ReadPreferences()
			if e != nil {
				t.Fatal(e)
			}
			raw, _ := json.Marshal(docs["user"])
			t.Logf("persisted=%s", raw)
			r = reviewRequest("root", "persistent", v.PolicyID)
			v = reviewApply(t, s, r)
			stored, e := s.ReadPolicy(v.PolicyID)
			if e != nil {
				t.Fatal(e)
			}
			if field == "allowed" {
				t.Logf("direct=%v persistent=%v", direct.Permissions, stored.Permissions)
				if !reflect.DeepEqual(direct.Permissions, stored.Permissions) {
					t.Error("empty allow restriction widened after persistence")
				}
			} else {
				t.Logf("direct=%v persistent=%v", direct.Billing, stored.Billing)
				if !reflect.DeepEqual(direct.Billing, stored.Billing) {
					t.Error("empty billing restriction widened after persistence")
				}
			}
		})
	}
}
func TestReviewerEmptySetRequestIdentity(t *testing.T) {
	a := reviewRequest("root", "same", "")
	a.Patch.Run.Restrictions = []contract.Restriction{{Allowed: []string{}}}
	b := a
	b.Patch.Run.Restrictions = []contract.Restriction{{}}
	ad, _ := a.Digest()
	bd, _ := b.Digest()
	t.Logf("empty=%s absent=%s", ad, bd)
	if ad == bd {
		t.Error("semantically distinct deny-all and absent allow restriction collide")
	}
}
func TestReviewerRestrictedSetsControls(t *testing.T) {
	s, _ := reviewStore(t)
	reviewRoot(t, s, "root")
	p := contract.Preferences{Version: 1, Restrictions: []contract.Restriction{{Allowed: []string{"read", "write"}, Billing: []string{"pool-a"}}, {Allowed: []string{"read", "execute"}, Denied: []string{"write"}}}}
	if _, e := s.UpdatePreferences("user", 0, p); e != nil {
		t.Fatal(e)
	}
	r := reviewRequest("root", "good", "")
	v := reviewApply(t, s, r)
	out, e := s.ReadPolicy(v.PolicyID)
	if e != nil {
		t.Fatal(e)
	}
	if !reflect.DeepEqual(out.Permissions, []string{"read"}) || !reflect.DeepEqual(out.Billing, []string{"pool-a"}) {
		t.Fatalf("bad intersection %+v", out)
	}
	r = reviewRequest("root", "missing", v.PolicyID)
	g := reviewGrant()
	delete(g.Sources, "permissions")
	reviewAuthorize(t, s, r, g)
	if _, e = s.ApplyPolicy("root", "gen", r); e == nil {
		t.Fatal("missing designated source accepted")
	}
}
func TestReviewerReplayRollbackReopen(t *testing.T) {
	s, path := reviewStore(t)
	reviewRoot(t, s, "root")
	reviewRoot(t, s, "other")
	r0 := reviewRequest("root", "initial", "")
	v0 := reviewApply(t, s, r0)
	r1 := reviewRequest("root", "later", v0.PolicyID)
	r1.Patch.Run.Preset = "Accelerate"
	v1 := reviewApply(t, s, r1)
	got, e := s.ApplyPolicy("root", "gen", r0)
	if e != nil || got != v0 {
		t.Fatalf("exact retry %+v %v", got, e)
	}
	b, e := s.ReadBinding("root")
	if e != nil || b.ActivePolicyID != v1.PolicyID {
		t.Fatal("retry reactivated old result", b, e)
	}
	cross := r0
	cross.Root = "other"
	if _, e = s.ApplyPolicy("other", "gen", cross); e == nil {
		t.Fatal("crossroot ID reuse")
	}
	for _, cut := range []string{"snapshot-written", "authorization-consumed", "binding-written"} {
		r := reviewRequest("root", "cut-"+cut, v1.PolicyID)
		reviewAuthorize(t, s, r, reviewGrant())
		s.policyCut = func(p string) error {
			if p == cut {
				return errors.New("review cut")
			}
			return nil
		}
		if _, e = s.ApplyPolicy("root", "gen", r); e == nil {
			t.Fatal("cut ignored")
		}
		s.policyCut = nil
		if _, e = s.ReadAmendment("policy-amendment@1", r.AuthorizationID); e == nil {
			t.Fatal("result leaked")
		}
		b, _ = s.ReadBinding("root")
		if b.PolicyID != v1.PolicyID {
			t.Fatal("binding leaked")
		}
	}
	s.Close()
	s2, e := Open(path, time.Second)
	if e != nil {
		t.Fatal(e)
	}
	defer s2.Close()
	got, e = s2.ApplyPolicy("root", "gen", r0)
	if e != nil || got != v0 {
		t.Fatalf("durable retry %+v %v", got, e)
	}
}
func TestReviewerNumericIdentity(t *testing.T) {
	s, path := reviewStore(t)
	reviewRoot(t, s, "root")
	r := reviewRequest("root", "precision", "")
	r.Patch.Run.Restrictions = []contract.Restriction{{Denied: []string{"execute"}}}
	if e := s.db.Update(func(tx *bolt.Tx) error {
		docs, e := readPreferences(tx)
		if e != nil {
			return e
		}
		d := docs["user"]
		d.Revision = 9007199254740993
		d.Values.Preset = "Conserve"
		d.Digest = d.Values.Identity()
		return putJSON(tx.Bucket([]byte("preferences")), "user", d)
	}); e != nil {
		t.Fatal(e)
	}
	v := reviewApply(t, s, r)
	p, e := s.ReadPolicy(v.PolicyID)
	if e != nil {
		t.Fatal(e)
	}
	raw, _ := json.Marshal(p)
	if !strings.Contains(string(raw), "9007199254740993") {
		t.Fatal("revision provenance rounded")
	}
	s.Close()
	s2, e := Open(path, time.Second)
	if e != nil {
		t.Fatal(e)
	}
	defer s2.Close()
	p, e = s2.ReadPolicy(v.PolicyID)
	if e != nil || p.ID != p.Identity() {
		t.Fatal("identity drift", e)
	}
}
func TestReviewerScopes(t *testing.T) {
	s, _ := reviewStore(t)
	reviewRoot(t, s, "root")
	r := reviewRequest("root", "scopes", "")
	g := reviewGrant()
	limit := func(f float64) *float64 { return &f }
	for _, scope := range []string{"task", "project", "account", "window", "concurrency"} {
		g.Ceilings = append(g.Ceilings, contract.Ceiling{Resource: "tokens", Unit: "token", Pool: "pool", Interval: "run", Scope: scope, Limit: limit(100)})
	}
	r.Patch.Run.Restrictions = []contract.Restriction{{Ceilings: []contract.Ceiling{{Resource: "tokens", Unit: "token", Pool: "pool", Interval: "run", Scope: "task", Limit: limit(20)}, {Resource: "usd", Unit: "dollar", Pool: "pool", Interval: "run", Scope: "task", Limit: limit(2)}}}}
	reviewAuthorize(t, s, r, g)
	v, e := s.ApplyPolicy("root", "gen", r)
	if e != nil {
		t.Fatal(e)
	}
	p, e := s.ReadPolicy(v.PolicyID)
	if e != nil {
		t.Fatal(e)
	}
	if len(p.Ceilings) != 6 {
		t.Fatalf("lost scope %+v", p.Ceilings)
	}
	for _, c := range p.Ceilings {
		if c.Scope == "task" && c.Resource == "tokens" && *c.Limit != 20 {
			t.Fatal("bad minimum")
		}
	}
}
func TestReviewerAuthorizedEmptyPatchSubstitution(t *testing.T) {
	s, _ := reviewStore(t)
	reviewRoot(t, s, "root")
	r := reviewRequest("root", "restricted-auth", "")
	r.Patch.Run.Restrictions = []contract.Restriction{{Allowed: []string{}, Billing: []string{}}}
	reviewAuthorize(t, s, r, reviewGrant())
	changed := r
	changed.Patch.Run.Restrictions = []contract.Restriction{{}}
	v, e := s.ApplyPolicy("root", "gen", changed)
	if e != nil {
		t.Log("altered request rejected", e)
		return
	}
	p, e := s.ReadPolicy(v.PolicyID)
	if e != nil {
		t.Fatal(e)
	}
	t.Fatalf("authorization for empty sets accepted omitted sets: permissions=%v billing=%v", p.Permissions, p.Billing)
}
func TestReviewerNegativeUnderflow(t *testing.T) {
	for _, limit := range []string{"-1", "-1e-1000"} {
		raw := []byte(fmt.Sprintf(`{"schema_version":1,"restrictions":[{"ceilings":[{"resource":"tokens","unit":"token","pool":"p","interval":"run","scope":"task","limit":%s}]}]}`, limit))
		p, e := contract.DecodePreferences(raw)
		if e == nil {
			t.Errorf("negative JSON limit %s accepted as %v", limit, *p.Restrictions[0].Ceilings[0].Limit)
		} else {
			t.Logf("negative control %s rejected: %v", limit, e)
		}
	}
}
