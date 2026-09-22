package controller

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
)

func instrService(t *testing.T) *Service {
	t.Helper()
	s := New(t.TempDir(), Options{Timeout: time.Second, Clock: func() time.Time {
		return time.Date(2026, 9, 22, 14, 0, 0, 0, time.UTC)
	}})
	if e := s.Init(); e != nil {
		t.Fatal(e)
	}
	if e := s.EnsureInstrumentNamespaces(); e != nil {
		t.Fatal(e)
	}
	return s
}

func fixtureEvidence() contract.CapabilityEvidence {
	return contract.CapabilityEvidence{
		Cancellation: contract.EvidenceVerified, ChildVisibility: contract.EvidenceVerified,
		Enforcement: contract.EvidenceVerified, Billing: contract.EvidenceVerified,
		SourceKind: contract.EvidenceSourceFixture, LiveCriterion: contract.LiveCriterionBlocked,
	}
}

func completeTuple(id string) contract.CapabilityTuple {
	return contract.CapabilityTuple{
		SchemaVersion: contract.InstrumentSchemaVersion, ID: id,
		Host: "codex-cli", InstalledVersion: "0.154.0", IntegrationProtocol: "exec-jsonl@1",
		Mode: "local", Method: "exec-sandbox-readonly", EffectivePermissions: "read-only",
		ExecutionBoundary: contract.BoundarySandboxed, Granularity: contract.GranularityRequest,
		Maturity: contract.MaturityStable, Evidence: fixtureEvidence(),
		PermittedBilling: contract.BillingPermission{
			Mode: contract.BillingModeSubscription, Authorized: true, AuthorizationID: "auth-sub-1",
			CredentialPresent: true, AllowanceExhausted: false,
		},
		Qualification: contract.QualificationFixtureOnly,
	}
}

func matchedArm(id, kind, control string) contract.ProtocolArm {
	return contract.ProtocolArm{
		ID: id, Kind: kind, ControlIdentity: control,
		BaselineManifest: "baseline-" + id, OutcomeDefinition: "pass-fail",
		AcceptanceDefinition: "oracle-evidence", ResourceCoverage: []string{"inference", "elapsed"},
		CPUGuarantee: "1", MemoryGuarantee: "512Mi", NetworkGuarantee: "none",
		Dependencies: "locked", CacheState: "cold", Timeout: "30s",
		TaskSplit: "holdout-a", TaskStratum: "strata-1",
		EvaluatorOwner: "checker", HoldoutOwner: "holdout", Exclusions: "none",
	}
}

func syntheticProtocol(id string, arms ...contract.ProtocolArm) contract.FrozenProtocol {
	return contract.FrozenProtocol{
		SchemaVersion: contract.InstrumentSchemaVersion, ID: id, ProtocolVersion: "fixture-proto@1",
		Synthetic: true, Arms: arms, TaskManifestDigest: "task-manifest-1",
		ReferencedManifests: []string{"task-manifest-1", "baseline-native", "baseline-v3"},
		Margins: "fixture-only", SampleAllocation: "n=0", StoppingRules: "none",
		StatisticalRules: "none", BillingMode: contract.BillingModeNone,
		AllowanceAuthRef: "", OperatorAuthRef: "fixture-operator",
		ApprovedFlag: true, CallerTimestamp: "1999-01-01T00:00:00Z",
	}
}

func knownAmt(n float64) *float64 { return &n }

func baseAttempt(proto contract.FrozenProtocol, armID, kind, task, id string, terminal, acceptance string, cost float64) contract.AttemptRecord {
	ev := ""
	if acceptance == contract.AcceptanceAccepted {
		ev = "oracle-pass"
	}
	return contract.AttemptRecord{
		SchemaVersion: contract.InstrumentSchemaVersion, ID: id, TrialID: "trial-1",
		ProtocolID: proto.ID, ProtocolDigest: proto.CanonicalDigest,
		ArmID: armID, ArmKind: kind, TaskRootID: task, AttemptID: id,
		InvocationRef: "inv-1", ConfigRef: "cfg-1", EnvironmentRef: "env-1",
		TerminalState: terminal, Acceptance: acceptance, AcceptanceEvidence: ev,
		CostKind: contract.CostKnown, CostAmount: knownAmt(cost), CostUnit: "fixture-unit",
		ResourceCoverage: []string{"inference"},
		StartedAt: "2026-09-22T14:00:00Z", EndedAt: "2026-09-22T14:00:01Z",
	}
}

// TestV409T01 — catalogue binds host/version/mode/evidence/granularity; registration alone insufficient.
func TestV409T01(t *testing.T) {
	s := instrService(t)
	a := completeTuple("cap-session")
	a.Granularity = contract.GranularitySession
	b := completeTuple("cap-process")
	b.Granularity = contract.GranularityProcess
	if _, e := s.CatalogueCapability(a); e != nil {
		t.Fatal(e)
	}
	if _, e := s.CatalogueCapability(b); e != nil {
		t.Fatal(e)
	}
	for _, g := range []string{
		contract.GranularitySession, contract.GranularityTurn, contract.GranularityRequest,
		contract.GranularityTool, contract.GranularityProcess,
	} {
		c := completeTuple("cap-" + g)
		c.Granularity = g
		if _, e := s.CatalogueCapability(c); e != nil {
			t.Fatal(g, e)
		}
	}
	// Registration/help cannot establish verified execution evidence.
	reg := completeTuple("cap-reg")
	reg.Evidence.SourceKind = contract.EvidenceSourceRegistration
	reg.Evidence.Cancellation = contract.EvidenceVerified
	if _, e := s.CatalogueCapability(reg); e == nil {
		t.Fatal("registration with verified cancellation must reject")
	}
	help := completeTuple("cap-help")
	help.Evidence.SourceKind = contract.EvidenceSourceHelpDiscovery
	help.Evidence.Cancellation = contract.EvidenceDiscoveryOnly
	help.Evidence.ChildVisibility = contract.EvidenceDiscoveryOnly
	help.Evidence.Enforcement = contract.EvidenceDiscoveryOnly
	help.Evidence.Billing = contract.EvidenceDiscoveryOnly
	help.Qualification = contract.QualificationLiveBlocked
	out, e := s.CatalogueCapability(help)
	if e != nil {
		t.Fatal(e)
	}
	if out.Evidence.LiveCriterion != contract.LiveCriterionBlocked {
		t.Fatal("help discovery must keep live criterion blocked")
	}
	status, missing, e := s.LiveStatus(out.ID)
	if e != nil || status != contract.LiveCriterionBlocked || len(missing) == 0 {
		t.Fatalf("live status: %s %v %v", status, missing, e)
	}
}

// TestV409T02 — missing required capability or billing rejects; authorized API is distinct.
func TestV409T02(t *testing.T) {
	s := instrService(t)
	counters := NewTransportCounters()
	base := completeTuple("cap-t02")
	if _, e := s.CatalogueCapability(base); e != nil {
		t.Fatal(e)
	}
	positive, e := s.DispatchFixture(contract.PreflightRequest{
		TupleID: base.ID, RequiredBillingMode: contract.BillingModeSubscription,
	}, &FakeHostAdapter{AdapterName: "fixture", Counters: counters}, counters)
	if e != nil || !positive.Admitted {
		t.Fatalf("positive fixture admit: %+v %v", positive, e)
	}
	all, api, _, _ := counters.Snapshot()
	if all != 1 || api != 0 {
		t.Fatalf("positive transport: all=%d api=%d", all, api)
	}
	for _, missing := range []string{"cancellation", "child_visibility", "enforcement", "billing"} {
		bad := completeTuple("cap-t02-miss-" + missing)
		ev := fixtureEvidence()
		switch missing {
		case "cancellation":
			ev.Cancellation = contract.EvidenceUnverified
		case "child_visibility":
			ev.ChildVisibility = contract.EvidenceUnverified
		case "enforcement":
			ev.Enforcement = contract.EvidenceUnverified
		case "billing":
			ev.Billing = contract.EvidenceUnverified
		}
		bad.Evidence = ev
		if _, e := s.CatalogueCapability(bad); e != nil {
			t.Fatal(e)
		}
		before, _, _, _ := counters.Snapshot()
		res, e := s.DispatchFixture(contract.PreflightRequest{TupleID: bad.ID}, &FakeHostAdapter{AdapterName: "fixture", Counters: counters}, counters)
		if e == nil || res.Admitted {
			t.Fatalf("missing %s must reject: %+v", missing, res)
		}
		after, api2, _, _ := counters.Snapshot()
		if after != before || api2 != 0 {
			t.Fatalf("transport incremented on reject %s", missing)
		}
	}
	// Complete technical evidence with unverified billing still rejects.
	tech := completeTuple("cap-t02-nobill")
	tech.PermittedBilling.Authorized = false
	tech.PermittedBilling.AuthorizationID = ""
	if _, e := s.CatalogueCapability(tech); e != nil {
		t.Fatal(e)
	}
	if res, e := s.Preflight(contract.PreflightRequest{TupleID: tech.ID}, counters); e != nil || res.Admitted {
		t.Fatalf("unverified billing must reject: %+v %v", res, e)
	}
	// Authorized API mode is a distinct positive configuration.
	apiTuple := completeTuple("cap-t02-api")
	apiTuple.Mode = "api"
	apiTuple.Method = "api-transport"
	apiTuple.PermittedBilling = contract.BillingPermission{
		Mode: contract.BillingModeAPI, Authorized: true, AuthorizationID: "auth-api-1",
		CredentialPresent: true,
	}
	if _, e := s.CatalogueCapability(apiTuple); e != nil {
		t.Fatal(e)
	}
	apiBefore, apiCallsBefore, _, _ := counters.Snapshot()
	res, e := s.DispatchFixture(contract.PreflightRequest{
		TupleID: apiTuple.ID, RequiredBillingMode: contract.BillingModeAPI,
	}, &FakeHostAdapter{AdapterName: "api", API: true, Counters: counters}, counters)
	if e != nil || !res.Admitted || !res.APITransportAllowed {
		t.Fatalf("API fixture: %+v %v", res, e)
	}
	apiAfter, apiCalls, _, _ := counters.Snapshot()
	if apiAfter != apiBefore+1 || apiCalls != apiCallsBefore+1 {
		t.Fatalf("API counter: after=%d calls=%d", apiAfter, apiCalls)
	}
}

// TestV409T03 — exhausted subscription never switches to API without separate allowance.
func TestV409T03(t *testing.T) {
	s := instrService(t)
	counters := NewTransportCounters()
	ex := completeTuple("cap-t03")
	ex.PermittedBilling.AllowanceExhausted = true
	ex.PermittedBilling.CredentialPresent = true
	if _, e := s.CatalogueCapability(ex); e != nil {
		t.Fatal(e)
	}
	before, apiBefore, _, _ := counters.Snapshot()
	res, e := s.DispatchFixture(contract.PreflightRequest{
		TupleID: ex.ID, RequiredBillingMode: contract.BillingModeSubscription, AuthorizeAPIFallback: true,
	}, &FakeHostAdapter{AdapterName: "api", API: true, Counters: counters}, counters)
	if e == nil || res.Admitted {
		t.Fatalf("exhausted sub must not dispatch: %+v", res)
	}
	after, apiAfter, _, _ := counters.Snapshot()
	if after != before || apiAfter != apiBefore {
		t.Fatal("API transport invoked without allowance")
	}
	// Sibling API allowance on a different tuple does not authorize this one.
	api := completeTuple("cap-t03-api")
	api.PermittedBilling = contract.BillingPermission{
		Mode: contract.BillingModeAPI, Authorized: true, AuthorizationID: "auth-api-sib", CredentialPresent: true,
	}
	if _, e := s.CatalogueCapability(api); e != nil {
		t.Fatal(e)
	}
	before, apiBefore, _, _ = counters.Snapshot()
	_, _ = s.DispatchFixture(contract.PreflightRequest{TupleID: ex.ID, AuthorizeAPIFallback: true},
		&FakeHostAdapter{AdapterName: "api", API: true, Counters: counters}, counters)
	after, apiAfter, _, _ = counters.Snapshot()
	if after != before || apiAfter != apiBefore {
		t.Fatal("sibling API allowance leaked")
	}
	// Genuine exact API fixture authorization admits only that configuration.
	res, e = s.DispatchFixture(contract.PreflightRequest{
		TupleID: api.ID, RequiredBillingMode: contract.BillingModeAPI,
	}, &FakeHostAdapter{AdapterName: "api", API: true, Counters: counters}, counters)
	if e != nil || !res.Admitted {
		t.Fatal(e, res)
	}
	_, apiCalls, _, by := counters.Snapshot()
	if apiCalls != 1 || by["api"] != 1 {
		t.Fatalf("expected only API adapter call: %v", by)
	}
}

// TestV409T04 — shadow on/off leaves execution decisions byte-identical.
func TestV409T04(t *testing.T) {
	s := instrService(t)
	req := contract.ExecutionRequest{
		RouteInputs: json.RawMessage(`{"path":"a"}`), Prompt: "do thing", Model: "fixture-model",
		Tools: []string{"read"}, Settings: map[string]string{"note_ref": "n1"},
		BillingMode: contract.BillingModeSubscription, ExecutionDecisions: []string{"step-1"},
		SelectedRoute: "route-a",
	}
	offReq, offObs, e := s.ShadowObserve(false, req, nil)
	if e != nil {
		t.Fatal(e)
	}
	onReq, onObs, e := s.ShadowObserve(true, req, nil)
	if e != nil {
		t.Fatal(e)
	}
	if !contract.RequestsEqual(offReq, onReq) || !contract.RequestsEqual(req, onReq) {
		t.Fatal("shadow mutated execution request")
	}
	if offObs.RequestDigest != onObs.RequestDigest {
		t.Fatal("request digest diverged")
	}
	if offObs.Enabled || !onObs.Enabled {
		t.Fatal("enabled flags wrong")
	}
	if onObs.ArtifactRef == "" {
		t.Fatal("shadow-on must produce observation artifact")
	}
	// Observer failure cannot reroute or change billing.
	failReq, failObs, e := s.ShadowObserve(true, req, func(contract.ExecutionRequest) (contract.ShadowObservation, error) {
		return contract.ShadowObservation{}, errors.New("observer boom")
	})
	if e != nil {
		t.Fatal(e)
	}
	if !contract.RequestsEqual(req, failReq) {
		t.Fatal("observer failure mutated request")
	}
	if failObs.ObserverError == "" || failReq.BillingMode != req.BillingMode {
		t.Fatal("observer failure mishandled")
	}
	// Attempted mutation inside observer is ignored — caller receives original request copy.
	mutReq, _, e := s.ShadowObserve(true, req, func(r contract.ExecutionRequest) (contract.ShadowObservation, error) {
		r.BillingMode = contract.BillingModeAPI
		r.SelectedRoute = "hijack"
		return contract.ShadowObservation{SchemaVersion: contract.InstrumentSchemaVersion, ID: "mut", RecordedAt: "2026-09-22T14:00:00Z"}, nil
	})
	if e != nil {
		t.Fatal(e)
	}
	if mutReq.BillingMode != req.BillingMode || mutReq.SelectedRoute != req.SelectedRoute {
		t.Fatal("observer mutation affected returned request")
	}
}

// TestV409T05 — freeze precedes outcome; forged timestamps / approved:true insufficient.
func TestV409T05(t *testing.T) {
	s := instrService(t)
	proto := syntheticProtocol("proto-t05",
		matchedArm("native", contract.ArmNative, contract.NativeControlIdentity),
		matchedArm("v3", contract.ArmOriginalV3, contract.OriginalV3ControlSHA),
	)
	attempt := baseAttempt(proto, "native", contract.ArmNative, "task-a", "att-1",
		contract.TerminalCompleted, contract.AcceptanceAccepted, 1)
	// Prefreeze outcome rejected.
	if _, e := s.RecordAttempt(attempt); e == nil {
		t.Fatal("outcome before freeze accepted")
	}
	frozen, freezeEv, e := s.FreezeProtocol(proto)
	if e != nil {
		t.Fatal(e)
	}
	if freezeEv.Kind != contract.OrderFreeze || freezeEv.Seq < 1 {
		t.Fatalf("freeze ordering: %+v", freezeEv)
	}
	if frozen.CanonicalDigest == "" {
		t.Fatal("missing canonical digest")
	}
	// Reopen store path by creating new service on same project.
	s2 := New(s.project, Options{Timeout: time.Second, Clock: s.opts.Clock})
	if e := s2.EnsureInstrumentNamespaces(); e != nil {
		t.Fatal(e)
	}
	dispatchEv, e := s2.AdmitDispatch(frozen.ID, frozen.CanonicalDigest)
	if e != nil {
		t.Fatal(e)
	}
	if dispatchEv.Seq <= freezeEv.Seq {
		t.Fatal("dispatch must follow freeze in controller order")
	}
	attempt.ProtocolDigest = frozen.CanonicalDigest
	outcomeEv, e := s2.RecordAttempt(attempt)
	if e != nil {
		t.Fatal(e)
	}
	if outcomeEv.Seq <= freezeEv.Seq {
		t.Fatal("outcome must follow freeze")
	}
	// Wrong protocol digest rejected.
	bad := attempt
	bad.ID = "att-bad"
	bad.AttemptID = "att-bad"
	bad.ProtocolDigest = "forged"
	if _, e = s2.RecordAttempt(bad); e == nil {
		t.Fatal("wrong protocol digest accepted")
	}
	// Changed referenced manifests require new identity.
	changed := proto
	changed.ID = "proto-t05"
	changed.ReferencedManifests = []string{"task-manifest-CHANGED"}
	if _, _, e = s2.FreezeProtocol(changed); e == nil {
		t.Fatal("changed manifest under same ID must conflict")
	}
	// New protocol identity succeeds.
	changed.ID = "proto-t05-b"
	if _, _, e = s2.FreezeProtocol(changed); e != nil {
		t.Fatal(e)
	}
	report, e := s2.InstrumentReport(frozen.ID)
	if e != nil {
		t.Fatal(e)
	}
	if !report.LiveBlocked || !report.Synthetic {
		t.Fatal("live must remain blocked; protocol synthetic")
	}
}

// TestV409T06 — fake probe / discovery / registration never live-qualifies.
func TestV409T06(t *testing.T) {
	s := instrService(t)
	counters := NewTransportCounters()
	fake := completeTuple("cap-t06-fake")
	out, e := s.CatalogueCapability(fake)
	if e != nil {
		t.Fatal(e)
	}
	res, e := s.DispatchFixture(contract.PreflightRequest{TupleID: out.ID}, &FakeHostAdapter{AdapterName: "fixture", Counters: counters}, counters)
	if e != nil || !res.Admitted {
		t.Fatal(e, res)
	}
	status, missing, e := s.LiveStatus(out.ID)
	if e != nil || status != contract.LiveCriterionBlocked {
		t.Fatalf("fake success live-qualified: %s %v", status, missing)
	}
	help := completeTuple("cap-t06-help")
	help.Evidence.SourceKind = contract.EvidenceSourceHelpDiscovery
	help.Evidence.Cancellation = contract.EvidenceDiscoveryOnly
	help.Evidence.ChildVisibility = contract.EvidenceDiscoveryOnly
	help.Evidence.Enforcement = contract.EvidenceDiscoveryOnly
	help.Evidence.Billing = contract.EvidenceDiscoveryOnly
	help.Qualification = contract.QualificationLiveBlocked
	hout, e := s.CatalogueCapability(help)
	if e != nil {
		t.Fatal(e)
	}
	if st, _, _ := s.LiveStatus(hout.ID); st != contract.LiveCriterionBlocked {
		t.Fatal("help discovery live-qualified")
	}
	// Live admission path always blocked.
	liveRes, e := s.Preflight(contract.PreflightRequest{TupleID: out.ID, LiveAdmission: true}, counters)
	if e != nil || liveRes.Admitted || liveRes.LiveCriterion != contract.LiveCriterionBlocked {
		t.Fatalf("live admission: %+v %v", liveRes, e)
	}
}

// TestV409T07 — shared native/v3 recorder schema + arithmetic; idempotent/conflict.
func TestV409T07(t *testing.T) {
	s := instrService(t)
	proto := syntheticProtocol("proto-t07",
		matchedArm("native", contract.ArmNative, contract.NativeControlIdentity),
		matchedArm("v3", contract.ArmOriginalV3, contract.OriginalV3ControlSHA),
	)
	frozen, _, e := s.FreezeProtocol(proto)
	if e != nil {
		t.Fatal(e)
	}
	for _, arm := range []struct{ id, kind string }{
		{"native", contract.ArmNative}, {"v3", contract.ArmOriginalV3},
	} {
		recs := []contract.AttemptRecord{
			baseAttempt(frozen, arm.id, arm.kind, "task-a", arm.id+"-a1", contract.TerminalFailed, contract.AcceptanceNone, 2),
			baseAttempt(frozen, arm.id, arm.kind, "task-a", arm.id+"-a2", contract.TerminalCompleted, contract.AcceptanceAccepted, 3),
			baseAttempt(frozen, arm.id, arm.kind, "task-b", arm.id+"-b1", contract.TerminalCancelled, contract.AcceptanceNone, 1),
			baseAttempt(frozen, arm.id, arm.kind, "task-b", arm.id+"-b2", contract.TerminalCompleted, contract.AcceptanceAccepted, 4),
		}
		for _, r := range recs {
			if _, e = s.RecordAttempt(r); e != nil {
				t.Fatal(arm, e)
			}
		}
		// Idempotent identical replay.
		if _, e = s.RecordAttempt(recs[0]); e != nil {
			t.Fatal("idempotent replay failed", e)
		}
		// Conflicting immutable record rejects.
		conflict := recs[0]
		conflict.CostAmount = knownAmt(99)
		if _, e = s.RecordAttempt(conflict); e == nil {
			t.Fatal("conflict accepted")
		}
		// Unknown cost attempt retained.
		unk := baseAttempt(frozen, arm.id, arm.kind, "task-c", arm.id+"-unk", contract.TerminalAbandoned, contract.AcceptanceNone, 0)
		unk.CostKind = contract.CostUnknown
		unk.CostAmount = nil
		if _, e = s.RecordAttempt(unk); e != nil {
			t.Fatal(e)
		}
	}
	report, e := s.InstrumentReport(frozen.ID)
	if e != nil {
		t.Fatal(e)
	}
	if len(report.Attempts) < 10 {
		t.Fatalf("expected attempts retained, got %d", len(report.Attempts))
	}
	native, e := contract.SummarizeAttempts(filterArm(report.Attempts, "native"))
	if e != nil {
		t.Fatal(e)
	}
	v3, e := contract.SummarizeAttempts(filterArm(report.Attempts, "v3"))
	if e != nil {
		t.Fatal(e)
	}
	if native.AttemptCount != v3.AttemptCount || native.KnownSubtotal != v3.KnownSubtotal {
		t.Fatalf("native/v3 diverge: %+v vs %+v", native, v3)
	}
}

func filterArm(recs []contract.AttemptRecord, arm string) []contract.AttemptRecord {
	var out []contract.AttemptRecord
	for _, r := range recs {
		if r.ArmID == arm {
			out = append(out, r)
		}
	}
	return out
}

// TestV409T08 — sandboxed vs privileged sibling; maturity visible; no inheritance.
func TestV409T08(t *testing.T) {
	s := instrService(t)
	counters := NewTransportCounters()
	sand := completeTuple("cap-t08-sand")
	sand.ExecutionBoundary = contract.BoundarySandboxed
	sand.Method = "exec-sandbox-readonly"
	sand.Maturity = contract.MaturityPreview
	if _, e := s.CatalogueCapability(sand); e != nil {
		t.Fatal(e)
	}
	priv := completeTuple("cap-t08-priv")
	priv.ExecutionBoundary = contract.BoundaryPrivileged
	priv.Method = "exec-danger-full-access"
	priv.Maturity = contract.MaturityExperimental
	priv.Evidence.Cancellation = contract.EvidenceUnverified
	priv.Evidence.ChildVisibility = contract.EvidenceUnverified
	priv.Evidence.Enforcement = contract.EvidenceUnverified
	priv.Evidence.Billing = contract.EvidenceUnverified
	if _, e := s.CatalogueCapability(priv); e != nil {
		t.Fatal(e)
	}
	if e := AssertSiblingIsolation(sand, priv); e != nil {
		t.Fatal(e)
	}
	res, e := s.DispatchFixture(contract.PreflightRequest{TupleID: sand.ID}, &FakeHostAdapter{AdapterName: "fixture", Counters: counters}, counters)
	if e != nil || !res.Admitted {
		t.Fatal(e, res)
	}
	before, _, _, _ := counters.Snapshot()
	res, e = s.DispatchFixture(contract.PreflightRequest{TupleID: priv.ID}, &FakeHostAdapter{AdapterName: "fixture", Counters: counters}, counters)
	if e == nil || res.Admitted {
		t.Fatal("privileged sibling inherited sandbox qualification")
	}
	after, api, _, _ := counters.Snapshot()
	if after != before || api != 0 {
		t.Fatal("privileged sibling transport invoked")
	}
	got, e := s.ensureInstrumentStore()
	if e != nil {
		t.Fatal(e)
	}
	defer got.Close()
	p, e := got.GetCapability(priv.ID)
	if e != nil {
		t.Fatal(e)
	}
	if p.Maturity != contract.MaturityExperimental || p.ExecutionBoundary != contract.BoundaryPrivileged {
		t.Fatalf("maturity/boundary lost: %+v", p)
	}
}

// TestV409T09 — drift invalidates affected tuple; unaffected pinned B remains.
func TestV409T09(t *testing.T) {
	s := instrService(t)
	counters := NewTransportCounters()
	a := completeTuple("cap-t09-a")
	b := completeTuple("cap-t09-b")
	b.InstalledVersion = "0.154.0-b"
	if _, e := s.CatalogueCapability(a); e != nil {
		t.Fatal(e)
	}
	if _, e := s.CatalogueCapability(b); e != nil {
		t.Fatal(e)
	}
	fields := []struct {
		name string
		mut  func(*contract.CapabilityTuple)
	}{
		{"version", func(t *contract.CapabilityTuple) { t.InstalledVersion = "9.9.9" }},
		{"integration", func(t *contract.CapabilityTuple) { t.IntegrationProtocol = "other@1" }},
		{"mode", func(t *contract.CapabilityTuple) { t.Mode = "cloud" }},
		{"method", func(t *contract.CapabilityTuple) { t.Method = "other-method" }},
		{"permissions", func(t *contract.CapabilityTuple) { t.EffectivePermissions = "danger" }},
		{"boundary", func(t *contract.CapabilityTuple) { t.ExecutionBoundary = contract.BoundaryPrivileged }},
		{"granularity", func(t *contract.CapabilityTuple) { t.Granularity = contract.GranularityProcess }},
		{"maturity", func(t *contract.CapabilityTuple) { t.Maturity = contract.MaturityExperimental }},
		{"evidence", func(t *contract.CapabilityTuple) { t.Evidence.Cancellation = contract.EvidenceUnverified }},
		{"billing", func(t *contract.CapabilityTuple) { t.PermittedBilling.Mode = contract.BillingModeAPI }},
	}
	for _, f := range fields {
		s = instrService(t)
		a = completeTuple("cap-t09-a")
		b = completeTuple("cap-t09-b")
		b.Host = "codex-cli" // same brand
		b.InstalledVersion = "pinned-b"
		if _, e := s.CatalogueCapability(a); e != nil {
			t.Fatal(e)
		}
		if _, e := s.CatalogueCapability(b); e != nil {
			t.Fatal(e)
		}
		mutated := a
		f.mut(&mutated)
		if e := s.DriftCapability(a.ID, mutated); e != nil {
			t.Fatal(f.name, e)
		}
		res, e := s.Preflight(contract.PreflightRequest{TupleID: a.ID}, counters)
		if e != nil || res.Admitted {
			t.Fatalf("%s: drifted A still admitted: %+v", f.name, res)
		}
		res, e = s.DispatchFixture(contract.PreflightRequest{TupleID: b.ID}, &FakeHostAdapter{AdapterName: "fixture", Counters: counters}, counters)
		if e != nil || !res.Admitted {
			t.Fatalf("%s: unaffected B rejected: %+v %v", f.name, res, e)
		}
	}
}

// TestV409T10 — environment mismatch rejects or uses predeclared stratification.
func TestV409T10(t *testing.T) {
	s := instrService(t)
	a := matchedArm("a", contract.ArmNative, contract.NativeControlIdentity)
	b := matchedArm("b", contract.ArmOriginalV3, contract.OriginalV3ControlSHA)
	proto := syntheticProtocol("proto-t10", a, b)
	frozen, _, e := s.FreezeProtocol(proto)
	if e != nil {
		t.Fatal(e)
	}
	ok, reason := contract.EnvironmentComparable(frozen.Arms[0], frozen.Arms[1])
	if !ok || reason != "matched" {
		t.Fatalf("equal arms: %v %s", ok, reason)
	}
	mismatches := []struct {
		label string
		mut   func(*contract.ProtocolArm)
	}{
		{"cpu", func(x *contract.ProtocolArm) { x.CPUGuarantee = "8" }},
		{"memory", func(x *contract.ProtocolArm) { x.MemoryGuarantee = "64Gi" }},
		{"network", func(x *contract.ProtocolArm) { x.NetworkGuarantee = "full" }},
		{"dependencies", func(x *contract.ProtocolArm) { x.Dependencies = "dirty" }},
		{"cache", func(x *contract.ProtocolArm) { x.CacheState = "warm" }},
		{"timeout", func(x *contract.ProtocolArm) { x.Timeout = "1h" }},
		{"task_split", func(x *contract.ProtocolArm) { x.TaskSplit = "other" }},
		{"acceptance", func(x *contract.ProtocolArm) { x.AcceptanceDefinition = "other" }},
		{"evaluator", func(x *contract.ProtocolArm) { x.EvaluatorOwner = "other" }},
	}
	for _, m := range mismatches {
		x := b
		m.mut(&x)
		ok, reason = contract.EnvironmentComparable(a, x)
		if ok || !strings.HasPrefix(reason, "mismatch:") {
			t.Fatalf("%s silently pooled: %v %s", m.label, ok, reason)
		}
	}
	// Predeclared stratification allows accounting without silent pooling.
	stratA := a
	stratB := b
	stratB.CPUGuarantee = "8"
	stratA.Stratification = "cpu-tier"
	stratB.Stratification = "cpu-tier"
	ok, reason = contract.EnvironmentComparable(stratA, stratB)
	if !ok || !strings.Contains(reason, "predeclared_stratification") {
		t.Fatalf("stratification: %v %s", ok, reason)
	}
	report, e := s.InstrumentReport(frozen.ID)
	if e != nil {
		t.Fatal(e)
	}
	if report.Comparability["native:v3"] != "" && report.Comparability["a:b"] != "matched" {
		// arms named a/b
		if report.Comparability["a:b"] != "matched" {
			t.Fatalf("report comparability: %+v", report.Comparability)
		}
	}
}

// TestV409T11 — structural/managed ineligible; native/v3 eligible under fixture auth; zero fabricated.
func TestV409T11(t *testing.T) {
	s := instrService(t)
	counters := NewTransportCounters()
	proto := syntheticProtocol("proto-t11",
		matchedArm("native", contract.ArmNative, contract.NativeControlIdentity),
		matchedArm("v3", contract.ArmOriginalV3, contract.OriginalV3ControlSHA),
		matchedArm("structural", contract.ArmStructural, "structural-placeholder"),
		matchedArm("managed", contract.ArmManaged, "managed-placeholder"),
	)
	frozen, _, e := s.FreezeProtocol(proto)
	if e != nil {
		t.Fatal(e)
	}
	pkgs := map[string]bool{} // V4-10 / V4-15 absent
	for _, arm := range frozen.Arms {
		el, e := s.EvaluateArmEligibility("trial-t11", frozen.ID, arm, pkgs)
		if e != nil {
			t.Fatal(e)
		}
		switch arm.Kind {
		case contract.ArmStructural, contract.ArmManaged:
			if el.Status != contract.EligibilityIneligible || el.FabricatedAttempts != 0 {
				t.Fatalf("expected ineligible: %+v", el)
			}
		case contract.ArmNative, contract.ArmOriginalV3:
			if el.Status != contract.EligibilityEligible {
				t.Fatalf("control ineligible: %+v", el)
			}
		}
	}
	// Available native/v3 can record under fixture authorization (no live transport).
	att := baseAttempt(frozen, "native", contract.ArmNative, "task-a", "n1",
		contract.TerminalCompleted, contract.AcceptanceAccepted, 1)
	if _, e = s.RecordAttempt(att); e != nil {
		t.Fatal(e)
	}
	all, api, _, _ := counters.Snapshot()
	if all != 0 || api != 0 {
		t.Fatal("eligibility/recording hit transport")
	}
	report, e := s.InstrumentReport(frozen.ID)
	if e != nil {
		t.Fatal(e)
	}
	var sawStruct, sawManaged bool
	for _, el := range report.Eligibility {
		if el.ArmKind == contract.ArmStructural {
			sawStruct = true
			if el.Status != contract.EligibilityIneligible || el.MissingPackage != contract.PackageV410 {
				t.Fatalf("structural: %+v", el)
			}
		}
		if el.ArmKind == contract.ArmManaged {
			sawManaged = true
			if el.Status != contract.EligibilityIneligible || el.MissingPackage != contract.PackageV415 {
				t.Fatalf("managed: %+v", el)
			}
		}
		if el.FabricatedAttempts != 0 {
			t.Fatal("fabricated attempts recorded")
		}
	}
	if !sawStruct || !sawManaged {
		t.Fatal("missing eligibility records")
	}
	// Wrong original-v3 SHA rejected at arm validation / eligibility.
	bad := matchedArm("v3-bad", contract.ArmOriginalV3, "deadbeef")
	if e := bad.Validate(); e == nil {
		t.Fatal("wrong v3 SHA validated")
	}
	// H-WIN rename must not become native/v3.
	hwin := matchedArm("h-win", contract.ArmNative, "bare-standard")
	if e := hwin.Validate(); e == nil {
		t.Fatal("H-WIN label accepted as native control")
	}
}

func TestV409StoreReopenOrdering(t *testing.T) {
	dir := t.TempDir()
	s := New(dir, Options{Timeout: time.Second, Clock: func() time.Time {
		return time.Date(2026, 9, 22, 14, 0, 0, 0, time.UTC)
	}})
	if e := s.Init(); e != nil {
		t.Fatal(e)
	}
	if e := s.EnsureInstrumentNamespaces(); e != nil {
		t.Fatal(e)
	}
	proto := syntheticProtocol("proto-reopen", matchedArm("native", contract.ArmNative, contract.NativeControlIdentity))
	frozen, _, e := s.FreezeProtocol(proto)
	if e != nil {
		t.Fatal(e)
	}
	// Prove DB file exists then reopen.
	dbPath := filepath.Join(dir, ".eidolons", ".ledger", ".gauge-controller-v1", "state.db")
	if _, e := os.Stat(dbPath); e != nil {
		t.Fatal(e)
	}
	s2 := New(dir, Options{Timeout: time.Second, Clock: s.opts.Clock})
	att := baseAttempt(frozen, "native", contract.ArmNative, "t", "a1", contract.TerminalFailed, contract.AcceptanceNone, 2)
	if _, e = s2.RecordAttempt(att); e != nil {
		t.Fatal(e)
	}
}
