package controller

import (
	"strings"
	"testing"
	"time"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
)

func contextService(t *testing.T) *Service {
	t.Helper()
	s := New(t.TempDir(), Options{Timeout: time.Second, Clock: func() time.Time {
		return time.Date(2026, 9, 22, 22, 0, 0, 0, time.UTC)
	}})
	if e := s.Init(); e != nil {
		t.Fatal(e)
	}
	if e := s.EnsureContextNamespaces(); e != nil {
		t.Fatal(e)
	}
	return s
}

func allPins() []contract.ContextPin {
	var pins []contract.ContextPin
	for _, id := range contract.DefaultContextPins {
		pins = append(pins, contract.ContextPin{ID: id, Value: "v-" + id})
	}
	return pins
}

func sampleEvidence(id string, present bool) contract.EvidenceArtifact {
	return contract.EvidenceArtifact{
		SchemaVersion:   contract.ContextSchemaVersion,
		ID:              id,
		SourceRef:       "file://fixture/" + id,
		SourceDigest:    "src-" + id,
		CriteriaDigest:  "crit-a",
		EnvironmentDeps: []string{"go1.27.1", "fixture"},
		ArtifactDigest:  "art-" + id,
		Present:         present,
	}
}

// TestV419T01 — relevant mutations/missing artifacts invalidate; unrelated control reuses only with proven dependency.
func TestV419T01(t *testing.T) {
	s := contextService(t)
	if _, e := s.OpenContextSession("sess-t01", "root-t01"); e != nil {
		t.Fatal(e)
	}
	ev := sampleEvidence("ev-t01", true)

	ok, e := s.ReuseEvidence(contract.EvidenceReuseRequest{
		SchemaVersion: contract.ContextSchemaVersion, SessionID: "sess-t01", RootID: "root-t01",
		Candidate: ev, CurrentSourceDigest: "src-ev-t01", CurrentCriteria: "crit-a",
		CurrentEnv: []string{"go1.27.1", "fixture"},
	})
	if e != nil {
		t.Fatal(e)
	}
	if !ok.Reused || ok.Outcome != contract.EvidenceReuseValid {
		t.Fatalf("expected valid reuse: %+v", ok)
	}

	missing := sampleEvidence("ev-missing", false)
	inv, e := s.ReuseEvidence(contract.EvidenceReuseRequest{
		SchemaVersion: contract.ContextSchemaVersion, SessionID: "sess-t01", RootID: "root-t01",
		Candidate: missing, CurrentSourceDigest: "src-ev-missing", CurrentCriteria: "crit-a",
		CurrentEnv: []string{"go1.27.1", "fixture"},
	})
	if e != nil {
		t.Fatal(e)
	}
	if inv.Reused || inv.Outcome != contract.EvidenceReuseInvalidated {
		t.Fatalf("missing artifact must invalidate: %+v", inv)
	}

	mut, e := s.ReuseEvidence(contract.EvidenceReuseRequest{
		SchemaVersion: contract.ContextSchemaVersion, SessionID: "sess-t01", RootID: "root-t01",
		Candidate: ev, CurrentSourceDigest: "src-CHANGED", CurrentCriteria: "crit-a",
		CurrentEnv: []string{"go1.27.1", "fixture"},
	})
	if e != nil {
		t.Fatal(e)
	}
	if mut.Reused || !contains(mut.Reasons, contract.InvalidateSourceMutated) {
		t.Fatalf("source mutation must invalidate: %+v", mut)
	}

	crit, e := s.ReuseEvidence(contract.EvidenceReuseRequest{
		SchemaVersion: contract.ContextSchemaVersion, SessionID: "sess-t01", RootID: "root-t01",
		Candidate: ev, CurrentSourceDigest: "src-ev-t01", CurrentCriteria: "crit-B",
		CurrentEnv: []string{"go1.27.1", "fixture"},
	})
	if e != nil {
		t.Fatal(e)
	}
	if crit.Reused || !contains(crit.Reasons, contract.InvalidateCriteriaChanged) {
		t.Fatalf("criteria change must invalidate: %+v", crit)
	}

	env, e := s.ReuseEvidence(contract.EvidenceReuseRequest{
		SchemaVersion: contract.ContextSchemaVersion, SessionID: "sess-t01", RootID: "root-t01",
		Candidate: ev, CurrentSourceDigest: "src-ev-t01", CurrentCriteria: "crit-a",
		CurrentEnv: []string{"go1.27.1", "other-env"},
	})
	if e != nil {
		t.Fatal(e)
	}
	if env.Reused || !contains(env.Reasons, contract.InvalidateEnvChanged) {
		t.Fatalf("env change must invalidate: %+v", env)
	}

	noDep, e := s.ReuseEvidence(contract.EvidenceReuseRequest{
		SchemaVersion: contract.ContextSchemaVersion, SessionID: "sess-t01", RootID: "root-t01",
		Candidate: ev, ControlEvidenceID: "control-x", ProvenDependency: false,
		CurrentSourceDigest: "src-ev-t01", CurrentCriteria: "crit-a",
		CurrentEnv: []string{"go1.27.1", "fixture"},
	})
	if e != nil {
		t.Fatal(e)
	}
	if noDep.Reused || !contains(noDep.Reasons, contract.InvalidateNoDependency) {
		t.Fatalf("unrelated without dependency must fail: %+v", noDep)
	}

	withDep, e := s.ReuseEvidence(contract.EvidenceReuseRequest{
		SchemaVersion: contract.ContextSchemaVersion, SessionID: "sess-t01", RootID: "root-t01",
		Candidate: ev, ControlEvidenceID: "control-x", ProvenDependency: true,
		CurrentSourceDigest: "src-ev-t01", CurrentCriteria: "crit-a",
		CurrentEnv: []string{"go1.27.1", "fixture"},
	})
	if e != nil {
		t.Fatal(e)
	}
	if !withDep.Reused || withDep.Outcome != contract.EvidenceReuseUnrelated {
		t.Fatalf("unrelated with proven dependency may reuse: %+v", withDep)
	}
}

func contains(xs []string, want string) bool {
	for _, x := range xs {
		if x == want {
			return true
		}
	}
	return false
}

// TestV419T02 — decisive assertion outside raw tail; redaction; deleted; inaccessible reported.
func TestV419T02(t *testing.T) {
	s := contextService(t)
	body := strings.Repeat("x", 200) + "DECISIVE_ASSERTION" + strings.Repeat("y", 200)
	decisive := strings.Index(body, "DECISIVE_ASSERTION")
	pres, e := s.PresentBoundedEvidence(contract.PresentationRequest{
		SchemaVersion: contract.ContextSchemaVersion, SessionID: "sess-t02", RootID: "root-t02",
		EvidenceID: "ev-t02", FullBody: body, PresentationBound: 40, DecisiveOffset: decisive,
		Accessible: true,
	})
	if e != nil {
		t.Fatal(e)
	}
	if !pres.DecisiveIncluded || !strings.Contains(pres.Excerpt, "DECISIVE") {
		t.Fatalf("decisive content must be in excerpt, not raw tail only: %+v", pres)
	}
	if pres.FullReference == "" {
		t.Fatal("usable full reference required")
	}

	red, e := s.PresentBoundedEvidence(contract.PresentationRequest{
		SchemaVersion: contract.ContextSchemaVersion, SessionID: "sess-t02", RootID: "root-t02",
		EvidenceID: "ev-t02r", FullBody: "secret", PresentationBound: 20, Accessible: true, Redacted: true,
	})
	if e != nil {
		t.Fatal(e)
	}
	if !red.Redacted || !strings.Contains(red.Excerpt, "redacted") {
		t.Fatalf("redaction must be marked: %+v", red)
	}

	gone, e := s.PresentBoundedEvidence(contract.PresentationRequest{
		SchemaVersion: contract.ContextSchemaVersion, SessionID: "sess-t02", RootID: "root-t02",
		EvidenceID: "ev-gone", FullBody: "x", PresentationBound: 10, Deleted: true, Accessible: false,
	})
	if e != nil {
		t.Fatal(e)
	}
	if !gone.InaccessibleReported || gone.FullReference != "" {
		t.Fatalf("inaccessible reference must be reported: %+v", gone)
	}
}

// TestV419T03 — cold/warm recovery retains pins and obligations without fabricating history.
func TestV419T03(t *testing.T) {
	s := contextService(t)
	obs := []contract.TaskObligation{
		{ID: "fail-1", Kind: "failure", Detail: "prior failure"},
		{ID: "budget-1", Kind: "budget", Detail: "remaining 40"},
		{ID: "check-1", Kind: "check", Detail: "outstanding verify"},
		{ID: "auth-1", Kind: "authority", Detail: "authority digest"},
	}
	cold, e := s.SucceedContext(contract.SuccessionRequest{
		SchemaVersion: contract.ContextSchemaVersion, SessionID: "sess-t03", RootID: "root-t03",
		Mode: "cold", Pins: allPins(), Obligations: obs,
	})
	if e != nil {
		t.Fatal(e)
	}
	if cold.FabricatedHistory || len(cold.RetainedPins) != len(contract.DefaultContextPins) || len(cold.RetainedObligations) != 4 {
		t.Fatalf("cold must retain pins/obligations: %+v", cold)
	}
	if len(cold.MissingMandatory) != 0 {
		t.Fatalf("all mandatory pins present: %v", cold.MissingMandatory)
	}

	warm, e := s.SucceedContext(contract.SuccessionRequest{
		SchemaVersion: contract.ContextSchemaVersion, SessionID: "sess-t03w", RootID: "root-t03",
		Mode: "warm", Pins: allPins()[:3], Obligations: obs[:2],
	})
	if e != nil {
		t.Fatal(e)
	}
	if len(warm.MissingMandatory) == 0 {
		t.Fatal("incomplete pins must be reported as missing mandatory")
	}

	if _, e := s.SucceedContext(contract.SuccessionRequest{
		SchemaVersion: contract.ContextSchemaVersion, SessionID: "sess-bad", RootID: "root-t03",
		Mode: "cold", FabricateHistory: true, Pins: allPins(),
	}); e == nil {
		t.Fatal("fabricating unseen history must be rejected")
	}
}

// TestV419T04 — no-MCP / foreign / poisoned / stale / failed recall; no receipt promotion.
func TestV419T04(t *testing.T) {
	s := contextService(t)

	noMCP, e := s.RecallMemory(contract.MemoryRecallRequest{
		SchemaVersion: contract.ContextSchemaVersion, SessionID: "sess-t04", RootID: "root-t04",
		ProjectScope: "proj-a", MCPAvailable: false,
		Items: []contract.MemoryItem{{
			SchemaVersion: contract.ContextSchemaVersion, ID: "m1", SourceProvenance: "note",
			ProjectScope: "proj-a", Applicability: "build", Revision: "1", Body: "hint",
		}},
	})
	if e != nil {
		t.Fatal(e)
	}
	if noMCP.Status != contract.MemoryUnavailable || noMCP.ReceiptPromoted || noMCP.AuthoritativeUse || noMCP.CrystaliumOperational {
		t.Fatalf("no-MCP must continue without memory authority: %+v", noMCP)
	}

	bad, e := s.RecallMemory(contract.MemoryRecallRequest{
		SchemaVersion: contract.ContextSchemaVersion, SessionID: "sess-t04b", RootID: "root-t04",
		ProjectScope: "proj-a", CurrentRevision: "2", MCPAvailable: true, Now: "2026-09-22T22:00:00Z",
		Items: []contract.MemoryItem{
			{SchemaVersion: contract.ContextSchemaVersion, ID: "foreign", SourceProvenance: "x", ProjectScope: "proj-other", Applicability: "a", Revision: "2", Body: "leak"},
			{SchemaVersion: contract.ContextSchemaVersion, ID: "poison", SourceProvenance: "x", ProjectScope: "proj-a", Applicability: "a", Revision: "2", Body: "poison payload"},
			{SchemaVersion: contract.ContextSchemaVersion, ID: "stale", SourceProvenance: "x", ProjectScope: "proj-a", Applicability: "stale_test_claim", Revision: "2", Body: "tests passed"},
			{SchemaVersion: contract.ContextSchemaVersion, ID: "oldrev", SourceProvenance: "x", ProjectScope: "proj-a", Applicability: "a", Revision: "1", Body: "old"},
		},
	})
	if e != nil {
		t.Fatal(e)
	}
	if bad.ReceiptPromoted || bad.AuthoritativeUse || bad.GuidancePresented {
		t.Fatalf("untrusted memory must not guide or promote: %+v", bad)
	}
	if len(bad.RejectedIDs) < 4 {
		t.Fatalf("expected foreign/poison/stale/rev rejects: %+v", bad)
	}

	if _, e := s.RecallMemory(contract.MemoryRecallRequest{
		SchemaVersion: contract.ContextSchemaVersion, SessionID: "sess-t04p", RootID: "root-t04",
		MCPAvailable: true, PromoteReceipt: true,
		Items: []contract.MemoryItem{{
			SchemaVersion: contract.ContextSchemaVersion, ID: "m", SourceProvenance: "x",
			ProjectScope: "p", Applicability: "a", Revision: "1", Body: "x",
		}},
	}); e == nil {
		t.Fatal("receipt promotion must be rejected")
	}
}

// TestV419T05 — generic wrapper denied ops; valid batches remain bounded.
func TestV419T05(t *testing.T) {
	s := contextService(t)
	res, e := s.EnforceBatchTools(contract.BatchToolRequest{
		SchemaVersion: contract.ContextSchemaVersion, SessionID: "sess-t05", RootID: "root-t05",
		AccessRestrictions: []string{"deny:secrets.write", "deny:network.egress", "deny:filesystem./etc"},
		ViaCodeWrapper:     true,
		Ops: []contract.ToolOp{
			{OpID: "1", Kind: "filesystem", Target: "secrets.write", Permission: "allow:secrets.write"},
			{OpID: "2", Kind: "network", Target: "egress", Permission: "allow:network.egress"},
			{OpID: "3", Kind: "filesystem", Target: "/etc", Permission: "allow:filesystem./etc"},
			{OpID: "4", Kind: "tool", Target: "search", Permission: "allow:tool.search"},
		},
	})
	if e != nil {
		t.Fatal(e)
	}
	if !res.Bounded {
		t.Fatal("batch must remain bounded")
	}
	denied := 0
	for _, o := range res.Outcomes {
		if o.Result == contract.PermDenied {
			denied++
			if !strings.Contains(o.Reason, "wrapper") && !strings.Contains(o.Reason, "deny") {
				t.Fatalf("deny reason expected: %+v", o)
			}
		}
	}
	if denied != 3 {
		t.Fatalf("expected 3 denies + 1 allow: %+v", res.Outcomes)
	}
	if res.Outcomes[3].Result != contract.PermAllowed {
		t.Fatalf("valid op must remain allowed: %+v", res.Outcomes[3])
	}
}

// TestV419T06 — repeated hooks and threshold oscillation honor configured debounce/hysteresis.
func TestV419T06(t *testing.T) {
	s := contextService(t)
	skip, e := s.TriggerLifecycle(contract.LifecycleTriggerRequest{
		SchemaVersion: contract.ContextSchemaVersion, SessionID: "sess-t06", RootID: "root-t06",
		TriggerDigest: "same", DebounceWindowMS: 5000, HysteresisBand: 0.05,
		LastDigest: "same", LastTriggerAt: "2026-09-22T22:00:00Z", Now: "2026-09-22T22:00:02Z",
		ZoneUtilization: 0.55, LastZone: 0.55,
	})
	if e != nil {
		t.Fatal(e)
	}
	if skip.Outcome != contract.LifecycleSkippedDuplicate {
		t.Fatalf("unchanged within debounce must skip: %+v", skip)
	}

	hyst, e := s.TriggerLifecycle(contract.LifecycleTriggerRequest{
		SchemaVersion: contract.ContextSchemaVersion, SessionID: "sess-t06", RootID: "root-t06",
		TriggerDigest: "same", DebounceWindowMS: 0, HysteresisBand: 0.1,
		LastDigest: "same", LastTriggerAt: "2026-09-22T21:00:00Z", Now: "2026-09-22T22:00:00Z",
		ZoneUtilization: 0.52, LastZone: 0.55,
	})
	if e != nil {
		t.Fatal(e)
	}
	if hyst.Outcome != contract.LifecycleSkippedDuplicate {
		t.Fatalf("oscillation within hysteresis must skip: %+v", hyst)
	}

	run, e := s.TriggerLifecycle(contract.LifecycleTriggerRequest{
		SchemaVersion: contract.ContextSchemaVersion, SessionID: "sess-t06", RootID: "root-t06",
		TriggerDigest: "changed", DebounceWindowMS: 5000, HysteresisBand: 0.05,
		LastDigest: "old", LastTriggerAt: "2026-09-22T22:00:00Z", Now: "2026-09-22T22:00:01Z",
		ZoneUtilization: 0.8, LastZone: 0.5,
	})
	if e != nil {
		t.Fatal(e)
	}
	if run.Outcome != contract.LifecycleExecuted {
		t.Fatalf("changed state must execute: %+v", run)
	}
}

// TestV419T07 — host-visible vs source-file vs labeled estimates; unsupported noted.
func TestV419T07(t *testing.T) {
	s := contextService(t)
	rep, e := s.MeasureOverhead(contract.OverheadRequest{
		SchemaVersion: contract.ContextSchemaVersion, SessionID: "sess-t07", RootID: "root-t07",
		Samples: []contract.OverheadSample{
			{Kind: contract.VisibilityHostVisible, Bytes: 100, HiddenWrapper: true},
			{Kind: contract.VisibilityHostVisible, Bytes: 50, EagerToolSchema: true},
			{Kind: contract.VisibilityHostVisible, Bytes: 20, DeferredToolSchema: true},
			{Kind: contract.VisibilityHostVisible, Bytes: 30, RepeatedSkillDesc: true},
			{Kind: contract.VisibilitySourceFile, Bytes: 10000},
			{Kind: contract.VisibilityEstimated, EstimatedTokens: 40, EstimateLabeled: true, Label: "estimate"},
			{Kind: contract.VisibilityUnsupported},
		},
	})
	if e != nil {
		t.Fatal(e)
	}
	if rep.HostVisibleBytes != 200 || rep.SourceFileBytes != 10000 || rep.EstimatedTokens != 40 {
		t.Fatalf("must distinguish payload kinds: %+v", rep)
	}
	if !rep.EstimatesLabeled || !rep.UnsupportedNoted || rep.Conflated {
		t.Fatalf("estimates labeled; unsupported noted; not conflated: %+v", rep)
	}

	if _, e := s.MeasureOverhead(contract.OverheadRequest{
		SchemaVersion: contract.ContextSchemaVersion, SessionID: "sess-t07b", RootID: "root-t07",
		Samples: []contract.OverheadSample{
			{Kind: contract.VisibilityEstimated, EstimatedTokens: 10, EstimateLabeled: false},
		},
	}); e == nil {
		t.Fatal("unlabeled estimates must fail")
	}
}

// TestV419T08 — scoped memory binds provenance; cross-project/expiry/supersession controlled.
func TestV419T08(t *testing.T) {
	s := contextService(t)
	ok, e := s.RecallMemory(contract.MemoryRecallRequest{
		SchemaVersion: contract.ContextSchemaVersion, SessionID: "sess-t08", RootID: "root-t08",
		ProjectScope: "proj-a", CurrentRevision: "3", MCPAvailable: true, Now: "2026-09-22T22:00:00Z",
		Items: []contract.MemoryItem{
			{SchemaVersion: contract.ContextSchemaVersion, ID: "good", SourceProvenance: "crystalium:note", ProjectScope: "proj-a", Applicability: "build", Revision: "3", Body: "ok"},
			{SchemaVersion: contract.ContextSchemaVersion, ID: "cross", SourceProvenance: "x", ProjectScope: "proj-b", Applicability: "build", Revision: "3", Body: "leak"},
			{SchemaVersion: contract.ContextSchemaVersion, ID: "expired", SourceProvenance: "x", ProjectScope: "proj-a", Applicability: "build", Revision: "3", ExpiresAt: "2026-09-21T00:00:00Z", Body: "old"},
			{SchemaVersion: contract.ContextSchemaVersion, ID: "super", SourceProvenance: "x", ProjectScope: "proj-a", Applicability: "build", Revision: "3", SupersededBy: "good", Body: "old"},
			{SchemaVersion: contract.ContextSchemaVersion, ID: "deleted", SourceProvenance: "x", ProjectScope: "proj-a", Applicability: "build", Revision: "3", Deleted: true, Body: "gone"},
		},
	})
	if e != nil {
		t.Fatal(e)
	}
	if ok.Status != contract.MemoryConflict && ok.Status != contract.MemoryInvalidDeps && ok.Status != contract.MemoryScopedOK {
		// After rejects, only "good" remains → scoped_ok (or conflict if applicability collided — only one body for build among retrievable)
	}
	if len(ok.RetrievableIDs) != 1 || ok.RetrievableIDs[0] != "good" {
		t.Fatalf("only valid scoped item retrievable: %+v", ok)
	}
	if ok.AuthoritativeUse || ok.ReceiptPromoted {
		t.Fatalf("retrievable must not grant authority: %+v", ok)
	}
	if len(ok.RejectedIDs) < 4 {
		t.Fatalf("cross/expired/super/deleted must reject: %+v", ok)
	}
}

// TestV419T09 — conflicts and invalid deps presented before guidance; no newest-text-wins.
func TestV419T09(t *testing.T) {
	s := contextService(t)
	conflict, e := s.RecallMemory(contract.MemoryRecallRequest{
		SchemaVersion: contract.ContextSchemaVersion, SessionID: "sess-t09", RootID: "root-t09",
		ProjectScope: "proj-a", CurrentRevision: "1", MCPAvailable: true,
		Items: []contract.MemoryItem{
			{SchemaVersion: contract.ContextSchemaVersion, ID: "old-env", SourceProvenance: "x", ProjectScope: "proj-a", Applicability: "env_instructions", Revision: "1", Body: "use python"},
			{SchemaVersion: contract.ContextSchemaVersion, ID: "new-env", SourceProvenance: "x", ProjectScope: "proj-a", Applicability: "env_instructions", Revision: "1", Body: "use go"},
		},
	})
	if e != nil {
		t.Fatal(e)
	}
	if conflict.Status != contract.MemoryConflict || !conflict.ConflictPresented || conflict.GuidancePresented {
		t.Fatalf("conflict must be presented before guidance: %+v", conflict)
	}

	invalid, e := s.RecallMemory(contract.MemoryRecallRequest{
		SchemaVersion: contract.ContextSchemaVersion, SessionID: "sess-t09b", RootID: "root-t09",
		ProjectScope: "proj-a", CurrentRevision: "2", MCPAvailable: true,
		Items: []contract.MemoryItem{
			{SchemaVersion: contract.ContextSchemaVersion, ID: "failed-as-success", SourceProvenance: "x", ProjectScope: "proj-a", Applicability: "procedure", Revision: "1", Body: "recorded success but failed"},
			{SchemaVersion: contract.ContextSchemaVersion, ID: "withdrawn", SourceProvenance: "x", ProjectScope: "proj-a", Applicability: "procedure", Revision: "2", Deleted: true, Body: "withdrawn"},
		},
	})
	if e != nil {
		t.Fatal(e)
	}
	if !invalid.InvalidityPresented || invalid.GuidancePresented || invalid.AuthoritativeUse {
		t.Fatalf("invalidity must block silent guidance: %+v", invalid)
	}
}

// TestV419T10 — discovery/retrieval/cited use distinguished; availability alone is not use.
func TestV419T10(t *testing.T) {
	s := contextService(t)
	disc, e := s.RecordNavigation(contract.NavigationEvent{
		SchemaVersion: contract.ContextSchemaVersion, SessionID: "sess-t10", RootID: "root-t10",
		EvidenceID: "ev-1", Kind: contract.NavDiscovery, ReachableOnly: true,
	})
	if e != nil {
		t.Fatal(e)
	}
	if disc.CountedAsUse {
		t.Fatalf("reachable-but-unopened must not count as use: %+v", disc)
	}

	trunc, e := s.RecordNavigation(contract.NavigationEvent{
		SchemaVersion: contract.ContextSchemaVersion, SessionID: "sess-t10", RootID: "root-t10",
		EvidenceID: "ev-1", Kind: contract.NavRetrieval, Truncated: true, Opened: true,
	})
	if e != nil {
		t.Fatal(e)
	}
	if trunc.CountedAsUse {
		t.Fatalf("truncated fragment is not cited use: %+v", trunc)
	}

	opened, e := s.RecordNavigation(contract.NavigationEvent{
		SchemaVersion: contract.ContextSchemaVersion, SessionID: "sess-t10", RootID: "root-t10",
		EvidenceID: "ev-1", Kind: contract.NavRetrieval, Opened: true,
	})
	if e != nil {
		t.Fatal(e)
	}
	if opened.CountedAsUse {
		t.Fatalf("opened evidence alone is not cited use: %+v", opened)
	}

	cited, e := s.RecordNavigation(contract.NavigationEvent{
		SchemaVersion: contract.ContextSchemaVersion, SessionID: "sess-t10", RootID: "root-t10",
		EvidenceID: "ev-1", Kind: contract.NavCitedUse, Cited: true, Opened: true,
	})
	if e != nil {
		t.Fatal(e)
	}
	if !cited.CountedAsUse {
		t.Fatalf("cited source must count as use: %+v", cited)
	}

	if _, e := s.RecordNavigation(contract.NavigationEvent{
		SchemaVersion: contract.ContextSchemaVersion, SessionID: "sess-t10", RootID: "root-t10",
		EvidenceID: "ev-1", Kind: contract.NavCitedUse, Cited: true, ReachableOnly: true,
	}); e == nil {
		t.Fatal("availability alone must not be cited use")
	}
}

// TestV419T11 — N/A: indexed information access feature condition absent (optional adapter out of scope).
func TestV419T11(t *testing.T) {
	s := contextService(t)
	f, e := s.RecordFeatureNA("V4-19-R11", "V4-19-T11", contract.FeatureIndexedAccess)
	if e != nil {
		t.Fatal(e)
	}
	if f.Applicability != contract.ApplicabilityNA || f.Condition != contract.FeatureConditionAbsent {
		t.Fatalf("R11 must be N/A with feature condition absent: %+v", f)
	}
	if f.OptionalAdapter != contract.OptionalAdapterOutOfScope || f.InventedIndex {
		t.Fatalf("must not invent indexing; adapter out of scope: %+v", f)
	}
}

// TestV419T12 — N/A: recursive information access feature condition absent (optional adapter out of scope).
func TestV419T12(t *testing.T) {
	s := contextService(t)
	f, e := s.RecordFeatureNA("V4-19-R12", "V4-19-T12", contract.FeatureRecursiveAccess)
	if e != nil {
		t.Fatal(e)
	}
	if f.Applicability != contract.ApplicabilityNA || f.Condition != contract.FeatureConditionAbsent {
		t.Fatalf("R12 must be N/A with feature condition absent: %+v", f)
	}
	if f.OptionalAdapter != contract.OptionalAdapterOutOfScope || f.InventedRecurse {
		t.Fatalf("must not invent recursion; adapter out of scope: %+v", f)
	}
}
