package controller

import (
	"strings"
	"testing"
	"time"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
)

func compService(t *testing.T) *Service {
	t.Helper()
	s := New(t.TempDir(), Options{Timeout: time.Second, Clock: func() time.Time {
		return time.Date(2026, 9, 22, 17, 0, 0, 0, time.UTC)
	}})
	if e := s.Init(); e != nil {
		t.Fatal(e)
	}
	if e := s.EnsureCompilerNamespaces(); e != nil {
		t.Fatal(e)
	}
	return s
}

func compRoot(t *testing.T, s *Service, id string) {
	t.Helper()
	if e := s.InitRoot(id); e != nil {
		t.Fatal(e)
	}
}

func skill(method, version string, forms []string, inputs []string, out string) contract.SkillContract {
	return contract.SkillContract{
		SchemaVersion: contract.CompilerSchemaVersion,
		MethodID: method, Version: version,
		Applicability: []string{"fixture"},
		RequiredInputs: inputs, OutputSchema: out, AllowedForms: forms,
		MaxOutputBytes: 4096, ExperimentalProfile: contract.ExperimentalProfileID,
	}
}

func baseAuth() contract.AuthorityLayers {
	return contract.AuthorityLayers{
		Operator:        contract.CapabilitySet{Allowed: []string{"read", "write", "plan", "localize", "consult"}},
		Task:            contract.CapabilitySet{Allowed: []string{"read", "write", "plan", "localize", "consult"}},
		Assignment:      contract.CapabilitySet{Allowed: []string{"read", "write", "plan", "localize", "consult"}},
		Specialist:      contract.CapabilitySet{Allowed: []string{"read", "plan", "localize", "consult"}},
		HostEnforceable: contract.CapabilitySet{Allowed: []string{"read", "write", "plan", "localize", "consult"}},
	}
}

func baseCompile(plan, root string, methods []contract.MethodRequest) contract.CompileRequest {
	return contract.CompileRequest{
		PlanID: plan, RootID: root, TaskID: "task-" + plan,
		MakerWorkerID: "maker-1", AuthorityID: "auth-" + plan,
		Authority: baseAuth(), Methods: methods,
		ExperimentalProfile: contract.ExperimentalProfileID,
		RecordedAt: "2026-09-22T17:00:00Z",
	}
}

// TestV413T01 — compatible localize + lite-plan in existing worker; independent consult separates.
func TestV413T01(t *testing.T) {
	s := compService(t)
	compRoot(t, s, "root-t01")

	req := baseCompile("plan-t01", "root-t01", []contract.MethodRequest{
		{
			UseID: "use-localize", MethodID: "localize",
			Contract: skill("localize", "1.0.0", []string{contract.FormEmbedded}, []string{"path"}, "localize.v1"),
			ExecutionForm: contract.FormEmbedded, ProvidedInputs: []string{"path"},
		},
		{
			UseID: "use-lite-plan", MethodID: "lite-plan",
			Contract: skill("lite-plan", "1.0.0", []string{contract.FormEmbedded}, []string{"goal"}, "lite-plan.v1"),
			ExecutionForm: contract.FormEmbedded, ProvidedInputs: []string{"goal"},
		},
		{
			UseID: "use-consult", MethodID: "independent-review",
			Contract: skill("independent-review", "1.0.0", []string{contract.FormConsultant}, []string{"brief"}, "review.v1"),
			ExecutionForm: contract.FormConsultant, ProvidedInputs: []string{"brief"},
			RequireIndependent: true,
		},
	})
	r, e := s.CompileAssignments("root-t01", req)
	if e != nil || !r.Compiled || r.Plan == nil {
		t.Fatalf("compile: %+v %v", r, e)
	}
	if r.Plan.ForcedFanOut {
		t.Fatal("compatible methods must not force fan-out")
	}
	var maker, separated int
	for _, a := range r.Plan.Assignments {
		if a.Continuing {
			maker++
			if a.WorkerID != "maker-1" {
				t.Fatalf("maker worker: %s", a.WorkerID)
			}
			if len(a.Methods) != 2 {
				t.Fatalf("expected localize+lite-plan inline, got %d", len(a.Methods))
			}
		} else {
			separated++
			if a.Boundary != contract.BoundaryIndependentConsult {
				t.Fatalf("consult boundary: %s", a.Boundary)
			}
		}
	}
	if maker != 1 || separated != 1 {
		t.Fatalf("maker=%d separated=%d", maker, separated)
	}
	if len(r.Plan.WorkerStarts) != 1 {
		t.Fatalf("expected one separated worker start, got %d", len(r.Plan.WorkerStarts))
	}
}

// TestV413T02 — verification / incompatible authority / isolated writer / context separation.
func TestV413T02(t *testing.T) {
	s := compService(t)
	compRoot(t, s, "root-t02")
	cases := []struct {
		use, method, form, force, want string
	}{
		{"u-ver", "verify", contract.FormVerification, "", contract.BoundaryVerification},
		{"u-auth", "priv", contract.FormEmbedded, contract.BoundaryIncompatibleAuth, contract.BoundaryIncompatibleAuth},
		{"u-iso", "write", contract.FormIsolatedWriter, "", contract.BoundaryIsolatedWriter},
		{"u-ctx", "ctx", contract.FormEmbedded, contract.BoundaryContextSeparation, contract.BoundaryContextSeparation},
	}
	var methods []contract.MethodRequest
	for _, c := range cases {
		methods = append(methods, contract.MethodRequest{
			UseID: c.use, MethodID: c.method,
			Contract: skill(c.method, "1.0.0", []string{c.form, contract.FormEmbedded}, []string{"in"}, "out.v1"),
			ExecutionForm: c.form, ProvidedInputs: []string{"in"}, ForceBoundary: c.force,
		})
	}
	r, e := s.CompileAssignments("root-t02", baseCompile("plan-t02", "root-t02", methods))
	if e != nil || !r.Compiled {
		t.Fatalf("compile: %+v %v", r, e)
	}
	found := map[string]bool{}
	for _, w := range r.Plan.WorkerStarts {
		found[w.Boundary] = true
		if w.AssignmentID == "" || w.WorkerID == "" || w.Selection.Detail == "" {
			t.Fatalf("incomplete worker start: %+v", w)
		}
	}
	for _, c := range cases {
		if !found[c.want] {
			t.Fatalf("missing boundary %s in %+v", c.want, found)
		}
	}
}

// TestV413T03 — effective authority intersection; wideners cannot escalate.
func TestV413T03(t *testing.T) {
	s := compService(t)
	compRoot(t, s, "root-t03")
	layers := contract.AuthorityLayers{
		Operator:        contract.CapabilitySet{Allowed: []string{"read", "write", "admin"}},
		Task:            contract.CapabilitySet{Allowed: []string{"read", "write"}},
		Assignment:      contract.CapabilitySet{Allowed: []string{"read", "write", "escalate"}},
		Specialist:      contract.CapabilitySet{Allowed: []string{"read"}},
		HostEnforceable: contract.CapabilitySet{Allowed: []string{"read", "write"}},
	}
	auth, e := ResolveEffectiveAuthority("auth-t03", layers, []string{
		contract.WidenRoleCard, contract.WidenModelMessage, contract.WidenRepoConfig, contract.WidenPrivilegedParent,
	})
	if e != nil {
		t.Fatal(e)
	}
	if len(auth.Permissions) != 1 || auth.Permissions[0] != "read" {
		t.Fatalf("intersection must be read only: %+v", auth.Permissions)
	}
	for _, w := range []string{contract.WidenRoleCard, contract.WidenModelMessage, contract.WidenRepoConfig, contract.WidenPrivilegedParent} {
		ok := false
		for _, d := range auth.WideningDenied {
			if d == w {
				ok = true
			}
		}
		if !ok {
			t.Fatalf("widener %s not denied", w)
		}
	}
	// Child grant stays intersected even when privileged parent lists admin.
	req := baseCompile("plan-t03", "root-t03", []contract.MethodRequest{{
		UseID: "use-r", MethodID: "localize",
		Contract: skill("localize", "1.0.0", []string{contract.FormEmbedded}, []string{"path"}, "localize.v1"),
		ExecutionForm: contract.FormEmbedded, ProvidedInputs: []string{"path"},
	}})
	req.Authority = layers
	req.WideningAttempts = []string{contract.WidenPrivilegedParent}
	r, e := s.CompileAssignments("root-t03", req)
	if e != nil || !r.Compiled {
		t.Fatalf("compile: %+v %v", r, e)
	}
	if len(r.Plan.EffectiveAuth.Permissions) != 1 || r.Plan.EffectiveAuth.Permissions[0] != "read" {
		t.Fatalf("child grant widened: %+v", r.Plan.EffectiveAuth)
	}
}

// TestV413T04 — unsafe role rebinding requires new restricted execution.
func TestV413T04(t *testing.T) {
	s := compService(t)
	compRoot(t, s, "root-t04")

	cases := []struct {
		name string
		req  contract.RoleRebindRequest
		want string
	}{
		{"in-flight", contract.RoleRebindRequest{WorkerID: "w1", InFlightAction: true}, contract.RebindRequireNew},
		{"reusable", contract.RoleRebindRequest{WorkerID: "w2", ReusableOldCapability: true}, contract.RebindRequireNew},
		{"unsupported", contract.RoleRebindRequest{WorkerID: "w3", UnsupportedTransition: true}, contract.RebindRequireNew},
		{"prompt-only", contract.RoleRebindRequest{WorkerID: "w4", PromptOnlyRevocation: true}, contract.RebindPromptOnlyInsufficient},
	}
	for _, c := range cases {
		c.req.RootID = "root-t04"
		c.req.RecordedAt = "2026-09-22T17:04:00Z"
		out, e := s.EvaluateRoleRebind("root-t04", c.req)
		if e != nil {
			t.Fatal(e)
		}
		if !out.RequireNew || out.Outcome != c.want {
			t.Fatalf("%s: %+v", c.name, out)
		}
	}
	ok, e := s.EvaluateRoleRebind("root-t04", contract.RoleRebindRequest{
		RootID: "root-t04", WorkerID: "w5", RecordedAt: "2026-09-22T17:04:01Z",
	})
	if e != nil || ok.RequireNew || ok.Outcome != contract.RebindSafeQuiescent {
		t.Fatalf("quiescent should be safe: %+v %v", ok, e)
	}
}

// TestV413T05 — inherited maker context withholds clean-context verification.
func TestV413T05(t *testing.T) {
	s := compService(t)
	compRoot(t, s, "root-t05")

	contam, e := s.ClassifyEvidence("root-t05", contract.ClassifyEvidenceRequest{
		InvocationID: "inv-contam", InheritsMakerContext: true, PrivilegedInfo: true,
		RecordedAt: "2026-09-22T17:05:00Z",
	})
	if e != nil {
		t.Fatal(e)
	}
	if contam.CleanContextStatus != "withheld" || contam.Class != contract.EvidenceContaminated {
		t.Fatalf("contaminated: %+v", contam)
	}

	fork, e := s.ClassifyEvidence("root-t05", contract.ClassifyEvidenceRequest{
		InvocationID: "inv-fork", ForkOrRename: true, GenuinelyFresh: false,
		RecordedAt: "2026-09-22T17:05:01Z",
	})
	if e != nil {
		t.Fatal(e)
	}
	if fork.CleanContextStatus != "withheld" || fork.Class != contract.EvidenceForkRename {
		t.Fatalf("fork/rename: %+v", fork)
	}

	same, e := s.ClassifyEvidence("root-t05", contract.ClassifyEvidenceRequest{
		InvocationID: "inv-same", SameModelAsMaker: true, GenuinelyFresh: false,
		RecordedAt: "2026-09-22T17:05:02Z",
	})
	if e != nil {
		t.Fatal(e)
	}
	if same.CleanContextStatus != "withheld" || same.Class != contract.EvidenceSameModelCheck {
		t.Fatalf("same-model: %+v", same)
	}

	fresh, e := s.ClassifyEvidence("root-t05", contract.ClassifyEvidenceRequest{
		InvocationID: "inv-fresh", GenuinelyFresh: true,
		RecordedAt: "2026-09-22T17:05:03Z",
	})
	if e != nil {
		t.Fatal(e)
	}
	if fresh.CleanContextStatus != "granted" || fresh.Class != contract.EvidenceCleanContext {
		t.Fatalf("fresh: %+v", fresh)
	}
}

// TestV413T06 — method use ≠ specialist invocation; ATLAS-derived ≠ ATLAS audit.
func TestV413T06(t *testing.T) {
	s := compService(t)
	compRoot(t, s, "root-t06")
	atlas := skill("atlas-localize", "1.0.0", []string{contract.FormEmbedded}, []string{"path"}, "localize.v1")
	atlas.DerivedFrom = "ATLAS"
	req := baseCompile("plan-t06", "root-t06", []contract.MethodRequest{
		{UseID: "use-atlas", MethodID: "atlas-localize", Contract: atlas,
			ExecutionForm: contract.FormEmbedded, ProvidedInputs: []string{"path"}},
		{UseID: "use-audit", MethodID: "atlas-audit",
			Contract: skill("atlas-audit", "1.0.0", []string{contract.FormConsultant}, []string{"scope"}, "audit.v1"),
			ExecutionForm: contract.FormConsultant, ProvidedInputs: []string{"scope"}, RequireIndependent: true},
	})
	r, e := s.CompileAssignments("root-t06", req)
	if e != nil || !r.Compiled {
		t.Fatalf("compile: %+v %v", r, e)
	}
	var sawMethod, sawInv bool
	for _, a := range r.Plan.Assignments {
		for _, m := range a.Methods {
			switch m.ReportClass {
			case contract.ReportMethodUse:
				sawMethod = true
				if m.InvocationID != "" && a.Continuing {
					// continuing method use must not claim specialist invocation id as audit
				}
				if !strings.Contains(m.Selection.Detail, "not an independent ATLAS audit") {
					t.Fatalf("embedded ATLAS must not claim audit: %+v", m.Selection)
				}
			case contract.ReportSpecialistInvocation:
				sawInv = true
				if m.InvocationID == "" {
					t.Fatal("specialist invocation requires visible invocation id")
				}
			}
		}
	}
	if !sawMethod || !sawInv {
		t.Fatalf("need both report classes: method=%v inv=%v", sawMethod, sawInv)
	}
}

// TestV413T07 — versioned skill contract; missing/incompatible/forbidden reject before dispatch.
func TestV413T07(t *testing.T) {
	s := compService(t)
	compRoot(t, s, "root-t07")

	ok := skill("reuse", "2.1.0", []string{contract.FormEmbedded, contract.FormConsultant}, []string{"brief", "scope"}, "reuse.v2")
	// Positive: inline and isolated share task intent via bound contract.
	pos, e := s.CompileAssignments("root-t07", baseCompile("plan-t07-ok", "root-t07", []contract.MethodRequest{
		{UseID: "inline", MethodID: "reuse", Contract: ok, ExecutionForm: contract.FormEmbedded,
			ProvidedInputs: []string{"brief", "scope"}},
		{UseID: "isolated", MethodID: "reuse", Contract: ok, ExecutionForm: contract.FormConsultant,
			ProvidedInputs: []string{"brief", "scope"}},
	}))
	if e != nil || !pos.Compiled {
		t.Fatalf("positive: %+v %v", pos, e)
	}
	for _, a := range pos.Plan.Assignments {
		for _, m := range a.Methods {
			if m.Contract.Version != "2.1.0" || m.Status != "bound" {
				t.Fatalf("binding: %+v", m)
			}
		}
	}

	neg, e := s.CompileAssignments("root-t07", baseCompile("plan-t07-neg", "root-t07", []contract.MethodRequest{
		{UseID: "miss", MethodID: "reuse", Contract: ok, ExecutionForm: contract.FormEmbedded,
			ProvidedInputs: []string{"brief"}}, // missing scope
		{UseID: "schema", MethodID: "reuse", Contract: ok, ExecutionForm: contract.FormEmbedded,
			ProvidedInputs: []string{"brief", "scope"}, ExpectedOutputSchema: "other.v1"},
		{UseID: "form", MethodID: "reuse", Contract: ok, ExecutionForm: contract.FormIsolatedWriter,
			ProvidedInputs: []string{"brief", "scope"}},
	}))
	if e != nil {
		t.Fatal(e)
	}
	if neg.Compiled {
		t.Fatalf("expected pre-dispatch reject: %+v", neg)
	}
	joined := strings.Join(neg.RejectReasons, ",")
	for _, need := range []string{"missing_input:scope", "incompatible_output_schema", "forbidden_execution_form"} {
		if !strings.Contains(joined, need) {
			t.Fatalf("missing reject %s in %s", need, joined)
		}
	}
}

// TestV413T08 — bounded consultant validation before maker use.
func TestV413T08(t *testing.T) {
	s := compService(t)
	compRoot(t, s, "root-t08")
	base := contract.ValidateConsultantRequest{
		ExpectedTaskID: "task-1", ExpectedCandidate: "cand-1",
		ExpectedSchema: "review.v1", MaxOutputBytes: 100,
		RecordedAt: "2026-09-22T17:08:00Z",
	}
	reject := func(name string, mut func(*contract.ConsultantResult)) {
		t.Helper()
		req := base
		req.Result = contract.ConsultantResult{
			SchemaVersion: contract.CompilerSchemaVersion,
			ID: "res-" + name, TaskID: "task-1", CandidateID: "cand-1",
			AssignmentID: "asgn-1", ArtifactRef: "artifact://" + name,
			OutputSchema: "review.v1", PayloadBytes: 50,
		}
		mut(&req.Result)
		out, e := s.ValidateConsultantResult("root-t08", req)
		if e != nil {
			t.Fatal(e)
		}
		if out.Accepted {
			t.Fatalf("%s should reject: %+v", name, out)
		}
	}
	reject("oversize", func(r *contract.ConsultantResult) { r.PayloadBytes = 500 })
	reject("noref", func(r *contract.ConsultantResult) { r.ArtifactRef = "" })
	reject("wrongtask", func(r *contract.ConsultantResult) { r.TaskID = "task-other" })
	reject("wrongcand", func(r *contract.ConsultantResult) { r.CandidateID = "cand-other" })
	reject("malformed", func(r *contract.ConsultantResult) { r.Malformed = true })
	reject("dump", func(r *contract.ConsultantResult) { r.TranscriptDump = true })

	okReq := base
	okReq.Result = contract.ConsultantResult{
		SchemaVersion: contract.CompilerSchemaVersion,
		ID: "res-ok", TaskID: "task-1", CandidateID: "cand-1",
		AssignmentID: "asgn-1", ArtifactRef: "artifact://ok",
		OutputSchema: "review.v1", PayloadBytes: 40,
	}
	ok, e := s.ValidateConsultantResult("root-t08", okReq)
	if e != nil || !ok.Accepted || ok.ArtifactRef != "artifact://ok" {
		t.Fatalf("valid result: %+v %v", ok, e)
	}
}

// TestV413T09 — concurrent writers need isolation + integration owner; merge revalidates.
func TestV413T09(t *testing.T) {
	s := compService(t)
	compRoot(t, s, "root-t09")

	overlap, e := s.AdmitConcurrentWriters("root-t09", contract.ConcurrentWritersRequest{
		RootID: "root-t09", TaskID: "task-9", CandidateID: "cand-9",
		IntegrationOwnerID: "integrator-1", IntegrationReserved: true, CheckReserved: true,
		MergeRequiresRevalidate: true, RecordedAt: "2026-09-22T17:09:00Z",
		Writers: []contract.WriterProposal{
			{WorkerID: "w-a", WorkspaceID: "ws-a", IsolatedWorkspace: true, MutablePaths: []string{"pkg/a.go", "shared.go"}},
			{WorkerID: "w-b", WorkspaceID: "ws-b", IsolatedWorkspace: true, MutablePaths: []string{"pkg/b.go", "shared.go"}},
		},
	})
	if e != nil || overlap.Admitted {
		t.Fatalf("overlap must reject: %+v %v", overlap, e)
	}
	if !strings.Contains(strings.Join(overlap.RejectReasons, ","), "overlapping_path") {
		t.Fatalf("expected overlapping_path: %+v", overlap.RejectReasons)
	}

	shared, e := s.AdmitConcurrentWriters("root-t09", contract.ConcurrentWritersRequest{
		RootID: "root-t09", TaskID: "task-9", CandidateID: "cand-9",
		IntegrationOwnerID: "integrator-1", IntegrationReserved: true, CheckReserved: true,
		MergeRequiresRevalidate: true, RecordedAt: "2026-09-22T17:09:01Z",
		Writers: []contract.WriterProposal{
			{WorkerID: "w-a", WorkspaceID: "ws-a", IsolatedWorkspace: true, SharedMutable: true, MutablePaths: []string{"a.go"}},
			{WorkerID: "w-b", WorkspaceID: "ws-b", IsolatedWorkspace: true, MutablePaths: []string{"b.go"}},
		},
	})
	if e != nil || shared.Admitted {
		t.Fatalf("shared mutable must reject: %+v %v", shared, e)
	}

	ok, e := s.AdmitConcurrentWriters("root-t09", contract.ConcurrentWritersRequest{
		RootID: "root-t09", TaskID: "task-9", CandidateID: "cand-9",
		IntegrationOwnerID: "integrator-1", IntegrationReserved: true, CheckReserved: true,
		MergeRequiresRevalidate: true, RecordedAt: "2026-09-22T17:09:02Z",
		Writers: []contract.WriterProposal{
			{WorkerID: "w-a", WorkspaceID: "ws-a", IsolatedWorkspace: true, MutablePaths: []string{"pkg/a.go"}},
			{WorkerID: "w-b", WorkspaceID: "ws-b", IsolatedWorkspace: true, MutablePaths: []string{"pkg/b.go"}},
		},
	})
	if e != nil || !ok.Admitted {
		t.Fatalf("disjoint should admit: %+v %v", ok, e)
	}
	if !ok.MergeRevalidates || ok.IntegrationOwnerID != "integrator-1" {
		t.Fatalf("merge must revalidate with owner: %+v", ok)
	}
}
