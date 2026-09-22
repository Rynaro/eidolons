package controller

import (
	"github.com/Rynaro/eidolons/gauge/internal/contract"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestV407ControllerBoundary(t *testing.T) {
	s := New(t.TempDir(), Options{Timeout: time.Second})
	if e := s.Init(); e != nil {
		t.Fatal(e)
	}
	if _, e := s.UpdatePreferences("user", 0, contract.Preferences{Version: 1, Preset: "Conserve"}); e != nil {
		t.Fatal(e)
	}
	if e := s.InitRoot("root"); e != nil {
		t.Fatal(e)
	}
	req := contract.PolicyRequest{Version: 1, Root: "root", AuthorizationID: "copied-operator", Patch: contract.PolicyPatch{Run: contract.Preferences{Version: 1, Preset: "Balanced"}, Required: contract.Requirements{Checks: []string{"regression"}, Criteria: "criteria", Grade: "fixture-only"}}}
	if _, e := s.ApplyPolicy("root", req); e == nil || !strings.Contains(e.Error(), "authorizer_boundary_unqualified") {
		t.Fatal("CLI composition authorized", e)
	}
	claim, e := os.ReadFile(s.claimPath("root"))
	if e != nil {
		t.Fatal(e)
	}
	if e = os.Remove(s.claimPath("root")); e != nil {
		t.Fatal(e)
	}
	if _, e = s.ApplyPolicy("root", req); e == nil || !strings.Contains(e.Error(), "claim") {
		t.Fatal("new mutator bypassed persistent claim", e)
	}
	if e = os.WriteFile(s.claimPath("root"), claim, 0600); e != nil {
		t.Fatal(e)
	}
	events := filepath.Join(s.runDir("root"), "events")
	if e = os.MkdirAll(events, 0700); e != nil {
		t.Fatal(e)
	}
	if e = os.WriteFile(filepath.Join(events, "unexpected"), []byte("drift"), 0600); e != nil {
		t.Fatal(e)
	}
	if _, e = s.ApplyPolicy("root", req); e == nil || !strings.Contains(e.Error(), "legacy events") {
		t.Fatal("new mutator bypassed inventory", e)
	}
}
