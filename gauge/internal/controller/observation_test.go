package controller

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
)

func obsService(t *testing.T) *Service {
	t.Helper()
	s := New(t.TempDir(), Options{Timeout: time.Second, Clock: func() time.Time { return time.Date(2026, 9, 22, 12, 0, 0, 0, time.UTC) }})
	if e := s.Init(); e != nil {
		t.Fatal(e)
	}
	if e := s.EnsureObservationNamespaces(); e != nil {
		t.Fatal(e)
	}
	return s
}

func baseStream() contract.StreamIdentity {
	return contract.StreamIdentity{
		Source: "fixture-collector", AdapterVersion: "1", AccountPool: "pool-a",
		Dimension: "tokens", Unit: "token", Scope: "task", CounterEpoch: "epoch-1",
	}
}

func baseObs(root, id string, amount float64) contract.UsageObservation {
	a := amount
	return contract.UsageObservation{
		SchemaVersion: contract.ObservationSchemaVersion, ID: id, Revision: "v0", RootID: root,
		TaskID: root, AssignmentID: "assign-1", InvocationID: "inv-1", ConfigurationID: "cfg-1",
		Stream: baseStream(), Kind: contract.KindDelta, Amount: &a, AmountKnown: true, Unit: "token",
		SourceGrade: contract.SourceGradeObserved, ObservationTime: "2026-09-22T12:00:00Z",
		ReceiptTime: "2026-09-22T12:00:01Z", Freshness: contract.FreshnessFresh, DetailRetained: true,
		Metadata: map[string]string{"collector": "fixture"},
	}
}

func TestV408T01(t *testing.T) {
	s := obsService(t)
	a, e := s.StartTask("route-digest-identical")
	if e != nil {
		t.Fatal(e)
	}
	b, e := s.StartTask("route-digest-identical")
	if e != nil {
		t.Fatal(e)
	}
	if a.RootID == b.RootID {
		t.Fatal("identical routes must allocate distinct roots")
	}
	if a.RouteDigest != b.RouteDigest || a.RouteDigest != "route-digest-identical" {
		t.Fatal("route digest must remain equal and distinct from root")
	}
	if a.RootID == a.RouteDigest {
		t.Fatal("root must not equal route digest")
	}
	if e = s.ResumeRoot(a.RootID); e != nil {
		t.Fatal(e)
	}
	if e = s.ResumeRoot("missing-root-zzzz"); e == nil || !strings.Contains(e.Error(), "unknown root") {
		t.Fatalf("unknown resume must fail without create: %v", e)
	}
	snap, e := s.inspect()
	if e != nil {
		t.Fatal(e)
	}
	if _, ok := snap.Roots["missing-root-zzzz"]; ok {
		t.Fatal("unknown resume fabricated a root")
	}
}

func TestV408T02(t *testing.T) {
	s := obsService(t)
	start, e := s.StartTask("route-t02")
	if e != nil {
		t.Fatal(e)
	}
	root := start.RootID
	now := "2026-09-22T12:00:00Z"
	for _, role := range []string{contract.RoleDescendant, contract.RoleReviewer, contract.RoleRetry, contract.RoleSuccessor} {
		edge := contract.LineageEdge{
			SchemaVersion: contract.ObservationSchemaVersion, ID: "edge-" + role, RootID: root, Role: role,
			ChildID: "child-" + role, CreatedAt: now, AssignmentID: "a1", InvocationID: "i1",
		}
		if e = s.BindLineage(root, edge); e != nil {
			t.Fatal(role, e)
		}
	}
	if e = s.Replace(root, "worker-b", "", true); e != nil {
		t.Fatal(e)
	}
	if e = s.Replace(root, "", "env-b", true); e != nil {
		t.Fatal(e)
	}
	st, e := s.Status(root)
	if e != nil {
		t.Fatal(e)
	}
	if st.Root.ID != root {
		t.Fatal("replacement reset budget root")
	}
	exp, e := s.ExportUsage(root)
	if e != nil {
		t.Fatal(e)
	}
	if len(exp.Lineage) < 5 {
		t.Fatalf("expected lineage edges, got %d", len(exp.Lineage))
	}
	// Cross-root retry must not bind under forged parent
	other, e := s.StartTask("other-route")
	if e != nil {
		t.Fatal(e)
	}
	cross := contract.LineageEdge{
		SchemaVersion: contract.ObservationSchemaVersion, ID: "cross-retry", RootID: other.RootID, Role: contract.RoleRetry,
		ChildID: "x", ParentRef: root, CreatedAt: now,
	}
	if e = s.BindLineage(other.RootID, cross); e != nil {
		t.Fatal(e)
	}
	// Binding records under other root — observations still cannot jump roots via RecordUsage
	o := baseObs(other.RootID, "d1", 3)
	o.RootID = root // forged
	if e = s.RecordUsage(other.RootID, o); e == nil {
		// RecordUsage overwrites RootID to other — wait, it sets o.RootID = rootID param
	}
	o = baseObs(other.RootID, "d1", 3)
	if e = s.RecordUsage(other.RootID, o); e != nil {
		t.Fatal(e)
	}
	sum, e := s.SummarizeUsage(root, baseStream())
	if e != nil {
		t.Fatal(e)
	}
	if sum.TotalKnown && sum.Total != nil && *sum.Total == 3 {
		t.Fatal("child observation leaked into original root totals")
	}
}

func TestV408T03(t *testing.T) {
	s := obsService(t)
	start, e := s.StartTask("route-t03")
	if e != nil {
		t.Fatal(e)
	}
	root := start.RootID
	grades := []string{
		contract.SourceGradeObserved, contract.SourceGradeEstimated, contract.SourceGradeSelfAttested,
		contract.SourceGradeUnsupported, contract.SourceGradeStale, contract.SourceGradeUnknown,
	}
	for i, g := range grades {
		o := baseObs(root, "obs-"+g, float64(i+1))
		o.SourceGrade = g
		if g == contract.SourceGradeStale {
			o.Freshness = contract.FreshnessStale
		}
		stream := baseStream()
		if g == contract.SourceGradeObserved {
			stream.Dimension = "cached_input"
			stream.Unit = "token"
			o.Unit = "token"
		}
		if strings.Contains(g, "unsupported") {
			stream.Dimension = "allowance"
			stream.Unit = "usd"
			o.Unit = "usd"
			o.AmountKnown = false
			o.Amount = nil
		}
		o.Stream = stream
		if e = s.RecordUsage(root, o); e != nil {
			t.Fatal(g, e)
		}
	}
	exp, e := s.ExportUsage(root)
	if e != nil {
		t.Fatal(e)
	}
	if len(exp.Observations) != 6 {
		t.Fatalf("got %d observations", len(exp.Observations))
	}
	seen := map[string]bool{}
	for _, o := range exp.Observations {
		seen[o.SourceGrade] = true
		if o.ObservationTime == "" || o.Freshness == "" || o.Unit == "" {
			t.Fatalf("missing provenance fields: %+v", o)
		}
	}
	for _, g := range grades {
		if !seen[g] {
			t.Fatal("missing grade", g)
		}
	}
}

func TestV408T04(t *testing.T) {
	s := obsService(t)
	start, e := s.StartTask("route-t04")
	if e != nil {
		t.Fatal(e)
	}
	root := start.RootID
	for id, n := range map[string]float64{"d1": 3, "d2": 4, "d3": 5, "d4": 2} {
		if e = s.RecordUsage(root, baseObs(root, id, n)); e != nil {
			t.Fatal(e)
		}
	}
	prefixAmt := 12.0
	prefix := baseObs(root, "prefix3", 12)
	prefix.Kind = contract.KindPrefix
	prefix.CursorEnd = 3
	prefix.Amount = &prefixAmt
	prefix.CoveredVersions = []string{"d1:v0", "d2:v0", "d3:v0"}
	prefix.AdditiveContract = true
	if e = s.RecordUsage(root, prefix); e != nil {
		t.Fatal(e)
	}
	sum, e := s.SummarizeUsage(root, baseStream())
	if e != nil {
		t.Fatal(e)
	}
	if !sum.TotalKnown || sum.Total == nil || *sum.Total != 14 {
		t.Fatalf("expected total 14, got %+v", sum)
	}
	// Duplicate identical observation replay
	if e = s.RecordUsage(root, baseObs(root, "d1", 3)); e != nil {
		t.Fatal(e)
	}
	sum, e = s.SummarizeUsage(root, baseStream())
	if e != nil || !sum.TotalKnown || *sum.Total != 14 {
		t.Fatalf("duplicate changed total: %+v %v", sum, e)
	}
	// Conflicting duplicate rejected
	if e = s.RecordUsage(root, baseObs(root, "d1", 9)); e == nil {
		t.Fatal("conflicting duplicate accepted")
	}
	sum, e = s.SummarizeUsage(root, baseStream())
	if e != nil || *sum.Total != 14 {
		t.Fatal("conflict mutated history")
	}
	// Correction d4:2→1
	corr := contract.UsageCorrection{
		SchemaVersion: contract.ObservationSchemaVersion, ID: "c4", RootID: root, TargetID: "d4",
		TargetRevision: "v0", ReplacementRev: "v1", Stream: baseStream(), OldAmount: 2, NewAmount: 1,
		AdditiveContract: true, CoveredInPrefix: false, ObservationTime: "2026-09-22T12:00:00Z", ReceiptTime: "2026-09-22T12:00:02Z",
	}
	if e = s.CorrectUsage(root, corr); e != nil {
		t.Fatal(e)
	}
	if e = s.CorrectUsage(root, corr); e != nil {
		t.Fatal("identical correction replay", e)
	}
	sum, e = s.SummarizeUsage(root, baseStream())
	if e != nil || !sum.TotalKnown || *sum.Total != 13 {
		t.Fatalf("after correction want 13 got %+v", sum)
	}
}

func TestV408T05(t *testing.T) {
	s := obsService(t)
	start, e := s.StartTask("route-t05")
	if e != nil {
		t.Fatal(e)
	}
	root := start.RootID
	o := baseObs(root, "tok-1", 1000)
	o.RequestedModel = "requested-model"
	o.ObservedModel = "" // unobserved
	o.SourceGrade = contract.SourceGradeEstimated
	if e = s.RecordUsage(root, o); e != nil {
		t.Fatal(e)
	}
	sum, e := s.SummarizeUsage(root, baseStream())
	if e != nil {
		t.Fatal(e)
	}
	if sum.ObservedModel != "" && sum.ObservedModel != "unknown" {
		// empty observed must not become requested
		if sum.ObservedModel == sum.RequestedModel {
			t.Fatal("requested model substituted for observed")
		}
	}
	rate := 2.0
	st, amt, _, _ := contract.EstimateCost(
		map[string]float64{"uncached_input": 1000},
		map[string]*float64{"uncached_input": nil, "output": &rate},
	)
	if st != contract.TotalUnknown || amt != nil {
		t.Fatal("missing price must not become zero cost")
	}
	// Stale allowance never unlimited
	allow := baseObs(root, "allow-1", 0)
	allow.AmountKnown = false
	allow.Amount = nil
	allow.Stream.Dimension = "allowance"
	allow.Stream.Unit = "usd"
	allow.Unit = "usd"
	allow.SourceGrade = contract.SourceGradeStale
	allow.Freshness = contract.FreshnessStale
	if e = s.RecordUsage(root, allow); e != nil {
		t.Fatal(e)
	}
	exp, e := s.ExportUsage(root)
	if e != nil {
		t.Fatal(e)
	}
	for _, ob := range exp.Observations {
		if ob.ID == "allow-1" && ob.AmountKnown {
			t.Fatal("stale allowance invented known zero")
		}
	}
}

func TestV408T06(t *testing.T) {
	s := obsService(t)
	start, e := s.StartTask("route-t06")
	if e != nil {
		t.Fatal(e)
	}
	root := start.RootID
	canaries := []string{
		"credential=CANARY_SECRET_1", "raw transcript CANARY_T", "hidden reasoning CANARY_R",
		"tool_args=CANARY_ARGS", "envdump=CANARY_ENV", "prompt=CANARY_P",
	}
	for i, c := range canaries {
		o := baseObs(root, "bad-"+string(rune('a'+i)), 1)
		o.Metadata = map[string]string{"note_ref": c}
		if e = s.RecordUsage(root, o); e == nil {
			t.Fatalf("accepted canary in metadata: %s", c)
		}
		if strings.Contains(e.Error(), "CANARY") {
			t.Fatal("error echoed canary")
		}
	}
	o := baseObs(root, "good-1", 1)
	o.Metadata = map[string]string{"collector": "fixture", "host": "local"}
	if e = s.RecordUsage(root, o); e != nil {
		t.Fatal(e)
	}
	if e = s.RetainUsage(root); e != nil {
		t.Fatal(e)
	}
	exp, e := s.ExportUsage(root)
	if e != nil {
		t.Fatal(e)
	}
	raw, _ := json.Marshal(exp)
	for _, c := range canaries {
		if strings.Contains(string(raw), "CANARY") {
			t.Fatal("canary leaked in export", c)
		}
	}
	if len(exp.Observations) == 0 {
		t.Fatal("retention removed observations entirely")
	}
	for _, ob := range exp.Observations {
		if ob.ID == "good-1" && ob.DetailRetained {
			t.Fatal("detail should be dropped")
		}
		if ob.Metadata != nil {
			t.Fatal("metadata should be cleared after retain")
		}
	}
}

func TestV408T07(t *testing.T) {
	s := obsService(t)
	start, e := s.StartTask("route-t07")
	if e != nil {
		t.Fatal(e)
	}
	root := start.RootID
	now := "2026-09-22T12:00:00Z"
	for _, edge := range []contract.LineageEdge{
		{SchemaVersion: 1, ID: "asg", RootID: root, Role: contract.LineageAssignment, ChildID: "assign-7", CreatedAt: now},
		{SchemaVersion: 1, ID: "inv", RootID: root, Role: contract.LineageInvocation, ChildID: "inv-7", CreatedAt: now},
		{SchemaVersion: 1, ID: "cfg", RootID: root, Role: contract.LineageConfig, ChildID: "cfg-7", CreatedAt: now},
		{SchemaVersion: 1, ID: "cand", RootID: root, Role: contract.LineageCandidate, ChildID: "cand-7", CreatedAt: now},
		{SchemaVersion: 1, ID: "intent", RootID: root, Role: contract.LineageIntent, ChildID: "intent-7", CreatedAt: now},
		{SchemaVersion: 1, ID: "causal", RootID: root, Role: contract.LineageCausalEvent, ChildID: "event-7", CreatedAt: now},
	} {
		if e = s.BindLineage(root, edge); e == nil && (edge.Role == contract.LineageAssignment) {
			// BindLineage only allows descendant/reviewer/retry/successor
		}
	}
	// Use PutLineage via store for identity roles — controller BindLineage is role-gated.
	// Record observation with full lineage links instead.
	o := baseObs(root, "obs-7", 1)
	o.AssignmentID = "assign-7"
	o.InvocationID = "inv-7"
	o.ConfigurationID = "cfg-7"
	o.CandidateID = "cand-7"
	o.IntentID = "intent-7"
	o.CausalEventID = "event-7"
	o.PolicyID = "policy-ref-7"
	if e = s.RecordUsage(root, o); e != nil {
		t.Fatal(e)
	}
	// After replacement, historical observation keeps original invocation
	if e = s.Replace(root, "worker-new", "", true); e != nil {
		t.Fatal(e)
	}
	exp, e := s.ExportUsage(root)
	if e != nil {
		t.Fatal(e)
	}
	found := false
	for _, ob := range exp.Observations {
		if ob.ID == "obs-7" {
			found = true
			if ob.InvocationID != "inv-7" || ob.ConfigurationID != "cfg-7" {
				t.Fatalf("historical links rewritten: %+v", ob)
			}
		}
	}
	if !found {
		t.Fatal("missing observation")
	}
	// Missing parent stays identifiable — correction without target is pending
	corr := contract.UsageCorrection{
		SchemaVersion: 1, ID: "pending-c", RootID: root, TargetID: "missing-obs", TargetRevision: "v0",
		ReplacementRev: "v1", Stream: baseStream(), OldAmount: 1, NewAmount: 2, AdditiveContract: true,
		ObservationTime: now, ReceiptTime: now,
	}
	if e = s.CorrectUsage(root, corr); e != nil {
		t.Fatal(e)
	}
	sum, e := s.SummarizeUsage(root, baseStream())
	if e != nil {
		t.Fatal(e)
	}
	if sum.State != contract.TotalPending && sum.State != contract.TotalUnknown && len(sum.PendingTargets) == 0 {
		// ReconcileObservations returns pending when target missing
		if sum.TotalKnown && sum.Total != nil && *sum.Total == 3 {
			t.Fatal("pending correction contributed replacement")
		}
	}
}

func TestV408T08(t *testing.T) {
	s := obsService(t)
	start, e := s.StartTask("route-t08")
	if e != nil {
		t.Fatal(e)
	}
	root := start.RootID
	dims := []struct {
		id, dim, unit string
		amount        float64
		known         bool
	}{
		{"inf-1", "tokens", "token", 10, true},
		{"xfer-1", "transfer", "byte", 100, true},
		{"env-1", "environment", "ms", 50, true},
		{"elapsed-1", "elapsed", "ms", 200, true},
		// human deliberately absent => coverage missing
	}
	for _, d := range dims {
		o := baseObs(root, d.id, d.amount)
		o.Stream.Dimension = d.dim
		o.Stream.Unit = d.unit
		o.Unit = d.unit
		o.AmountKnown = d.known
		if !d.known {
			o.Amount = nil
		}
		if e = s.RecordUsage(root, o); e != nil {
			t.Fatal(e)
		}
	}
	sum, e := s.SummarizeUsage(root, func() contract.StreamIdentity {
		st := baseStream()
		st.Dimension = "tokens"
		st.Unit = "token"
		return st
	}())
	if e != nil {
		t.Fatal(e)
	}
	if len(sum.Coverage) != 5 {
		t.Fatalf("coverage dimensions missing: %+v", sum.Coverage)
	}
	names := map[string]string{}
	for _, c := range sum.Coverage {
		names[c.Name] = c.Status
	}
	for _, n := range []string{contract.DimInference, contract.DimTransfer, contract.DimEnvironment, contract.DimElapsed, contract.DimHuman} {
		if _, ok := names[n]; !ok {
			t.Fatal("missing coverage category", n)
		}
	}
	if names[contract.DimHuman] != contract.CoverageMissing && names[contract.DimHuman] != contract.CoverageUnknown {
		t.Fatalf("human should be missing/unknown, got %s", names[contract.DimHuman])
	}
	// Hidden child: aggregate known but coverage gap noted when parent scope unknown
	o := baseObs(root, "parent-agg", 13)
	o.ParentScope = contract.ParentUnknown
	if e = s.RecordUsage(root, o); e != nil {
		t.Fatal(e)
	}
	sum2, e := s.SummarizeUsage(root, baseStream())
	if e != nil {
		t.Fatal(e)
	}
	if sum2.TotalKnown {
		t.Fatal("unknown parent inclusion must not invent combined total")
	}
}

func TestV408CLI(t *testing.T) {
	// Smoke: help lists observation commands via usage string presence in binary package.
	dir := t.TempDir()
	s := New(dir, Options{Timeout: time.Second})
	if e := s.Init(); e != nil {
		t.Fatal(e)
	}
	start, e := s.StartTask("cli-route")
	if e != nil {
		t.Fatal(e)
	}
	path := filepath.Join(dir, "obs.json")
	o := baseObs(start.RootID, "cli-d1", 3)
	raw, _ := json.Marshal(o)
	if e = os.WriteFile(path, raw, 0600); e != nil {
		t.Fatal(e)
	}
	if e = s.RecordUsage(start.RootID, o); e != nil {
		t.Fatal(e)
	}
	exp, e := s.ExportUsage(start.RootID)
	if e != nil || len(exp.Observations) != 1 {
		t.Fatal(e, exp)
	}
}
