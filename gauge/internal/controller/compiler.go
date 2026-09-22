package controller

import (
	"fmt"
	"time"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
	"github.com/Rynaro/eidolons/gauge/internal/store"
)

func (s *Service) ensureCompilerStore() (*store.Store, error) {
	db, e := s.ensureDispatchStore()
	if e != nil {
		return nil, e
	}
	if e = db.EnsureCompilerNamespaces(); e != nil {
		_ = db.Close()
		return nil, e
	}
	return db, nil
}

// EnsureCompilerNamespaces adds typed compiler buckets under schema 2.
func (s *Service) EnsureCompilerNamespaces() error {
	db, e := s.ensureCompilerStore()
	if e != nil {
		return e
	}
	return db.Close()
}

func rejectCompile(reasons ...string) contract.CompileResult {
	return contract.CompileResult{Compiled: false, RejectReasons: reasons}
}

// ResolveEffectiveAuthority intersects operator/task/assignment/specialist/host
// layers. Role cards, model messages, repo config, and privileged parents cannot
// widen the child grant (R03).
func ResolveEffectiveAuthority(id string, layers contract.AuthorityLayers, widening []string) (contract.EffectiveAuthority, error) {
	out := contract.EffectiveAuthority{
		SchemaVersion: contract.CompilerSchemaVersion,
		ID:            id,
		Layers:        layers,
	}
	if e := layers.Validate(); e != nil {
		return out, e
	}
	set, e := contract.IntersectCapabilitySets(
		layers.Operator, layers.Task, layers.Assignment, layers.Specialist, layers.HostEnforceable,
	)
	if e != nil {
		return out, e
	}
	out.Permissions = set.Allowed
	if out.Permissions == nil {
		out.Permissions = []string{}
	}
	out.Denied = set.Denied
	out.Provenance = []contract.SelectionReason{{
		RuleID: "R03", Kind: "authority_intersection",
		Detail: "operator∩task∩assignment∩specialist∩host_enforceable; denies accumulate",
		Profile: contract.ExperimentalProfileID,
	}}
	for _, w := range widening {
		switch w {
		case contract.WidenRoleCard, contract.WidenModelMessage, contract.WidenRepoConfig, contract.WidenPrivilegedParent:
			out.WideningDenied = append(out.WideningDenied, w)
			out.Provenance = append(out.Provenance, contract.SelectionReason{
				RuleID: "R03", Kind: "widening_rejected", Detail: w + " cannot escalate child grant",
			})
		default:
			out.WideningDenied = append(out.WideningDenied, "unknown:"+w)
		}
	}
	return out, nil
}

func formRequiresBoundary(form, force string, requireIndependent bool) (string, bool) {
	if requireIndependent {
		return contract.BoundaryIndependentConsult, true
	}
	if force != "" {
		return force, true
	}
	switch form {
	case contract.FormEmbedded:
		return contract.BoundaryCompatible, false
	case contract.FormConsultant:
		return contract.BoundaryIndependentConsult, true
	case contract.FormIsolatedWriter:
		return contract.BoundaryIsolatedWriter, true
	case contract.FormVerification:
		return contract.BoundaryVerification, true
	default:
		return contract.BoundaryIncompatibleAuth, true
	}
}

func bindMethod(req contract.MethodRequest, workerID string, continuing bool) contract.MethodUse {
	use := contract.MethodUse{
		ID: req.UseID, MethodID: req.MethodID, MethodVersion: req.Contract.Version,
		ExecutionForm: req.ExecutionForm, WorkerID: workerID,
		Contract: req.Contract, ProvidedInputs: append([]string(nil), req.ProvidedInputs...),
		ReportClass: contract.ReportMethodUse, Status: "bound",
		Selection: contract.SelectionReason{
			RuleID: "R07", Kind: "method_bind",
			Detail: "versioned applicability/input/output/execution-form bound",
			Profile: contract.ExperimentalProfileID,
		},
	}
	// Separate specialist invocation only when form is a true isolated consult
	// that starts a worker — not for embedded ATLAS-derived methods (R06).
	if !continuing && (req.ExecutionForm == contract.FormConsultant || req.RequireIndependent) {
		use.ReportClass = contract.ReportSpecialistInvocation
		use.InvocationID = "inv-" + req.UseID
		use.Selection = contract.SelectionReason{
			RuleID: "R06", Kind: "specialist_invocation",
			Detail: "separately identified specialist invocation",
		}
	} else {
		use.Selection = contract.SelectionReason{
			RuleID: "R06", Kind: "method_use",
			Detail: "embedded method use; not an independent specialist audit",
		}
		if req.Contract.DerivedFrom != "" {
			use.Selection.Detail = "embedded " + req.Contract.DerivedFrom +
				"-derived method; not an independent " + req.Contract.DerivedFrom + " audit"
		}
	}
	return use
}

func validateMethodBeforeDispatch(req contract.MethodRequest) []string {
	var reasons []string
	c := req.Contract
	if e := c.Validate(); e != nil {
		reasons = append(reasons, e.Error())
		return reasons
	}
	formOK := false
	for _, f := range c.AllowedForms {
		if f == req.ExecutionForm {
			formOK = true
			break
		}
	}
	if !formOK {
		reasons = append(reasons, "forbidden_execution_form:"+req.ExecutionForm)
	}
	have := map[string]bool{}
	for _, in := range req.ProvidedInputs {
		have[in] = true
	}
	for _, need := range c.RequiredInputs {
		if !have[need] {
			reasons = append(reasons, "missing_input:"+need)
		}
	}
	if c.OutputSchema == "" {
		reasons = append(reasons, "incompatible_output_schema:missing")
	}
	if req.ExpectedOutputSchema != "" && req.ExpectedOutputSchema != c.OutputSchema {
		reasons = append(reasons, "incompatible_output_schema:"+c.OutputSchema)
	}
	return reasons
}

// CompileAssignments compiles methods into continuing-maker or separated assignments.
// Compatible methods stay in the existing worker (R01); boundaries create identified
// assignments with recorded reasons (R02). Semantic planning remains fallible —
// selection reasons are inspectable, not correctness claims.
func (s *Service) CompileAssignments(rootID string, req contract.CompileRequest) (contract.CompileResult, error) {
	req.RootID = rootID
	if req.RecordedAt == "" {
		req.RecordedAt = s.opts.Clock().UTC().Format(time.RFC3339)
	}
	if req.ExperimentalProfile == "" {
		req.ExperimentalProfile = contract.ExperimentalProfileID
	}
	if e := req.Validate(); e != nil {
		return rejectCompile(e.Error()), nil
	}

	auth, e := ResolveEffectiveAuthority(req.AuthorityID, req.Authority, req.WideningAttempts)
	if e != nil {
		return rejectCompile("authority_resolution:" + e.Error()), nil
	}

	release, e := s.lock(rootID, false)
	if e != nil {
		return rejectCompile("append_lock_unavailable"), nil
	}
	defer release()
	if _, _, e = s.active(rootID); e != nil {
		return rejectCompile("active_claim_or_inventory_failed"), nil
	}

	db, e := store.Open(s.storePath(), s.opts.Timeout)
	if e != nil {
		return rejectCompile("store_unavailable:" + e.Error()), nil
	}
	defer db.Close()
	if e = db.EnsureCompilerNamespaces(); e != nil {
		return rejectCompile(e.Error()), nil
	}

	plan := contract.CompiledPlan{
		SchemaVersion: contract.CompilerSchemaVersion,
		ID: req.PlanID, RootID: rootID, TaskID: req.TaskID,
		MakerWorkerID: req.MakerWorkerID, EffectiveAuth: auth,
		ExperimentalProfile: req.ExperimentalProfile,
		CompiledAt: req.RecordedAt, Status: "compiled",
		SelectionReasons: []contract.SelectionReason{{
			RuleID: "V4-13", Kind: "compile",
			Detail: "inspectable selection; semantic planning remains fallible",
			Profile: req.ExperimentalProfile,
		}},
	}

	var inlineMethods []contract.MethodUse
	var rejectAll []string

	for _, mreq := range req.Methods {
		pre := validateMethodBeforeDispatch(mreq)
		if len(pre) > 0 {
			rejectAll = append(rejectAll, pre...)
			use := bindMethod(mreq, req.MakerWorkerID, true)
			use.Status = "rejected"
			use.RejectReasons = pre
			inlineMethods = append(inlineMethods, use)
			continue
		}
		boundary, separate := formRequiresBoundary(mreq.ExecutionForm, mreq.ForceBoundary, mreq.RequireIndependent)
		if !separate {
			use := bindMethod(mreq, req.MakerWorkerID, true)
			inlineMethods = append(inlineMethods, use)
			plan.SelectionReasons = append(plan.SelectionReasons, contract.SelectionReason{
				RuleID: "R01", Kind: "continuing_maker",
				Detail: mreq.MethodID + " runs in existing worker without forced fan-out",
			})
			continue
		}
		// Separated assignment with recorded reason (R02).
		assignID := "asgn-" + mreq.UseID
		workerID := "worker-" + mreq.UseID
		use := bindMethod(mreq, workerID, false)
		asgn := contract.Assignment{
			SchemaVersion: contract.CompilerSchemaVersion,
			ID: assignID, RootID: rootID, TaskID: req.TaskID,
			WorkerID: workerID, MakerWorkerID: req.MakerWorkerID,
			Continuing: false, Boundary: boundary, AuthorityID: auth.ID,
			Methods: []contract.MethodUse{use}, Status: "compiled",
			Selection: contract.SelectionReason{
				RuleID: "R02", Kind: "execution_boundary",
				Detail: "separately identified assignment: " + boundary,
			},
		}
		plan.Assignments = append(plan.Assignments, asgn)
		plan.WorkerStarts = append(plan.WorkerStarts, contract.WorkerStart{
			AssignmentID: assignID, WorkerID: workerID, Boundary: boundary,
			AuthorityID: auth.ID,
			Selection: asgn.Selection,
		})
		plan.SelectionReasons = append(plan.SelectionReasons, asgn.Selection)
	}

	if len(rejectAll) > 0 {
		plan.Status = "rejected"
		plan.RejectReasons = rejectAll
		// Still persist rejected bindings for inspectability before dispatch.
		if len(inlineMethods) > 0 {
			plan.Assignments = append([]contract.Assignment{{
				SchemaVersion: contract.CompilerSchemaVersion,
				ID: "asgn-maker-" + req.PlanID, RootID: rootID, TaskID: req.TaskID,
				WorkerID: req.MakerWorkerID, MakerWorkerID: req.MakerWorkerID,
				Continuing: true, Boundary: contract.BoundaryCompatible, AuthorityID: auth.ID,
				Methods: inlineMethods, Status: "rejected", RejectReasons: rejectAll,
				Selection: contract.SelectionReason{RuleID: "R07", Kind: "pre_dispatch_reject", Detail: "method contract failed before dispatch"},
			}}, plan.Assignments...)
		}
		persisted, e := db.PersistCompiledPlan(plan)
		if e != nil {
			return rejectCompile("persist:" + e.Error()), e
		}
		return contract.CompileResult{Compiled: false, Plan: &persisted, RejectReasons: rejectAll}, nil
	}

	if len(inlineMethods) > 0 {
		plan.Assignments = append([]contract.Assignment{{
			SchemaVersion: contract.CompilerSchemaVersion,
			ID: "asgn-maker-" + req.PlanID, RootID: rootID, TaskID: req.TaskID,
			WorkerID: req.MakerWorkerID, MakerWorkerID: req.MakerWorkerID,
			Continuing: true, Boundary: contract.BoundaryCompatible, AuthorityID: auth.ID,
			Methods: inlineMethods, Status: "compiled",
			Selection: contract.SelectionReason{
				RuleID: "R01", Kind: "continuing_maker",
				Detail: "compatible methods in existing worker; no forced fan-out",
			},
		}}, plan.Assignments...)
	}

	// forced_fan_out is true only when every method was forcibly separated with no
	// continuing maker methods — compatible localize+lite-plan must keep this false.
	plan.ForcedFanOut = len(inlineMethods) == 0 && len(plan.WorkerStarts) > 0

	persisted, e := db.PersistCompiledPlan(plan)
	if e != nil {
		return rejectCompile("persist:" + e.Error()), e
	}
	return contract.CompileResult{Compiled: true, Plan: &persisted}, nil
}

// CompilerStatus lists compiled plans for a root.
func (s *Service) CompilerStatus(rootID string) ([]contract.CompiledPlan, error) {
	release, e := s.lock(rootID, true)
	if e != nil {
		return nil, e
	}
	defer release()
	db, e := store.Open(s.storePath(), s.opts.Timeout)
	if e != nil {
		return nil, e
	}
	defer db.Close()
	if e = db.EnsureCompilerNamespaces(); e != nil {
		return nil, e
	}
	return db.ListCompiledPlans(rootID)
}

// EvaluateRoleRebind requires a new restricted execution when prior capabilities
// cannot be safely revoked at a supported boundary (R04). Prompt-only is insufficient.
func (s *Service) EvaluateRoleRebind(rootID string, req contract.RoleRebindRequest) (contract.RoleRebindResult, error) {
	req.RootID = rootID
	if req.RecordedAt == "" {
		req.RecordedAt = s.opts.Clock().UTC().Format(time.RFC3339)
	}
	var out contract.RoleRebindResult
	if e := req.Validate(); e != nil {
		out.Outcome = contract.RebindRequireNew
		out.RequireNew = true
		out.Detail = e.Error()
		return out, nil
	}
	var triggers []string
	if req.InFlightAction {
		triggers = append(triggers, contract.RebindTriggerInFlight)
	}
	if req.ReusableOldCapability {
		triggers = append(triggers, contract.RebindTriggerReusableOldCap)
	}
	if req.UnsupportedTransition {
		triggers = append(triggers, contract.RebindTriggerUnsupported)
	}
	if req.PromptOnlyRevocation {
		triggers = append(triggers, contract.RebindTriggerPromptOnly)
	}
	if len(triggers) > 0 {
		out.Outcome = contract.RebindRequireNew
		if req.PromptOnlyRevocation && len(triggers) == 1 {
			out.Outcome = contract.RebindPromptOnlyInsufficient
		}
		out.RequireNew = true
		out.Triggers = triggers
		out.Detail = "unsafe role rebinding; new appropriately restricted execution required"
		return out, nil
	}
	out.Outcome = contract.RebindSafeQuiescent
	out.RequireNew = false
	out.Detail = "quiescent rebinding at supported boundary"
	return out, nil
}

// ClassifyEvidence withholds clean-context verification when maker context or
// privileged info is inherited; rename/fork and same-model are not independence (R05).
func (s *Service) ClassifyEvidence(rootID string, req contract.ClassifyEvidenceRequest) (contract.EvidenceClass, error) {
	req.RecordedAt = coalesce(req.RecordedAt, s.opts.Clock().UTC().Format(time.RFC3339))
	ev := contract.EvidenceClass{
		SchemaVersion: contract.CompilerSchemaVersion,
		InvocationID: req.InvocationID,
		InheritsMakerContext: req.InheritsMakerContext,
		PrivilegedInfo: req.PrivilegedInfo,
		SameModelAsMaker: req.SameModelAsMaker,
		ForkOrRename: req.ForkOrRename,
	}
	if e := req.Validate(); e != nil {
		ev.Class = contract.EvidenceWithheldClean
		ev.CleanContextStatus = "withheld"
		ev.Selection = contract.SelectionReason{RuleID: "R05", Kind: "invalid", Detail: e.Error()}
		return ev, nil
	}
	switch {
	case req.InheritsMakerContext || req.PrivilegedInfo:
		ev.Class = contract.EvidenceContaminated
		ev.CleanContextStatus = "withheld"
		ev.Selection = contract.SelectionReason{
			RuleID: "R05", Kind: "contaminated_context",
			Detail: "inherits maker conversation or privileged information",
		}
	case req.ForkOrRename && !req.GenuinelyFresh:
		ev.Class = contract.EvidenceForkRename
		ev.CleanContextStatus = "withheld"
		ev.Selection = contract.SelectionReason{
			RuleID: "R05", Kind: "fork_or_rename",
			Detail: "rename/fork is not a genuinely fresh invocation",
		}
	case req.SameModelAsMaker && !req.GenuinelyFresh:
		ev.Class = contract.EvidenceSameModelCheck
		ev.CleanContextStatus = "withheld"
		ev.Selection = contract.SelectionReason{
			RuleID: "R05", Kind: "same_model",
			Detail: "same-model checking is not statistical independence",
		}
	case req.GenuinelyFresh && !req.InheritsMakerContext && !req.PrivilegedInfo:
		ev.Class = contract.EvidenceCleanContext
		ev.CleanContextStatus = "granted"
		ev.Selection = contract.SelectionReason{
			RuleID: "R05", Kind: "clean_context",
			Detail: "genuinely fresh invocation without inherited privileged context",
		}
	default:
		ev.Class = contract.EvidenceWithheldClean
		ev.CleanContextStatus = "withheld"
		ev.Selection = contract.SelectionReason{
			RuleID: "R05", Kind: "withheld", Detail: "clean-context verification status withheld",
		}
	}

	release, e := s.lock(rootID, false)
	if e != nil {
		return ev, e
	}
	defer release()
	db, e := store.Open(s.storePath(), s.opts.Timeout)
	if e != nil {
		return ev, e
	}
	defer db.Close()
	if e = db.EnsureCompilerNamespaces(); e != nil {
		return ev, e
	}
	if e = db.PersistEvidenceClass(ev, req.RecordedAt); e != nil {
		return ev, e
	}
	return ev, nil
}

func coalesce(v, fallback string) string {
	if v == "" {
		return fallback
	}
	return v
}

// ValidateConsultantResult checks bounded output contract before maker use (R08).
func (s *Service) ValidateConsultantResult(rootID string, req contract.ValidateConsultantRequest) (contract.ConsultantValidation, error) {
	req.RecordedAt = coalesce(req.RecordedAt, s.opts.Clock().UTC().Format(time.RFC3339))
	out := contract.ConsultantValidation{ResultID: req.Result.ID}
	if e := req.Validate(); e != nil {
		out.RejectReasons = []string{e.Error()}
		return out, nil
	}
	r := req.Result
	var reasons []string
	if r.TranscriptDump {
		reasons = append(reasons, "uncontrolled_transcript_dump")
	}
	if r.Malformed {
		reasons = append(reasons, "malformed_result")
	}
	if r.PayloadBytes > req.MaxOutputBytes {
		reasons = append(reasons, fmt.Sprintf("oversized_output:%d>%d", r.PayloadBytes, req.MaxOutputBytes))
	}
	if r.ArtifactRef == "" {
		reasons = append(reasons, "missing_artifact_ref")
	}
	if r.TaskID != req.ExpectedTaskID {
		reasons = append(reasons, "wrong_task:"+r.TaskID)
	}
	if r.CandidateID != req.ExpectedCandidate {
		reasons = append(reasons, "wrong_candidate:"+r.CandidateID)
	}
	if r.OutputSchema != req.ExpectedSchema {
		reasons = append(reasons, "incompatible_output_schema")
	}
	if len(reasons) > 0 {
		out.Accepted = false
		out.RejectReasons = reasons
	} else {
		out.Accepted = true
		out.ArtifactRef = r.ArtifactRef
	}

	release, e := s.lock(rootID, false)
	if e != nil {
		return out, e
	}
	defer release()
	if _, _, e = s.active(rootID); e != nil {
		out.Accepted = false
		out.RejectReasons = append(out.RejectReasons, "active_claim_or_inventory_failed")
		return out, nil
	}
	db, e := store.Open(s.storePath(), s.opts.Timeout)
	if e != nil {
		return out, e
	}
	defer db.Close()
	if e = db.EnsureCompilerNamespaces(); e != nil {
		return out, e
	}
	if e = db.PersistConsultantReceipt(out, req.RecordedAt); e != nil {
		return out, e
	}
	return out, nil
}

// AdmitConcurrentWriters requires isolated workspaces and an explicit integration
// owner; overlapping/shared mutable reject; merge still revalidates (R09).
func (s *Service) AdmitConcurrentWriters(rootID string, req contract.ConcurrentWritersRequest) (contract.ConcurrentWritersResult, error) {
	req.RootID = rootID
	req.RecordedAt = coalesce(req.RecordedAt, s.opts.Clock().UTC().Format(time.RFC3339))
	out := contract.ConcurrentWritersResult{MergeRevalidates: true}
	if e := req.Validate(); e != nil {
		out.RejectReasons = []string{e.Error()}
		return out, nil
	}
	if req.IntegrationOwnerID == "" {
		out.RejectReasons = append(out.RejectReasons, "missing_integration_owner")
	}
	if !req.IntegrationReserved {
		out.RejectReasons = append(out.RejectReasons, "integration_reservation_required")
	}
	if !req.CheckReserved {
		out.RejectReasons = append(out.RejectReasons, "check_reservation_required")
	}
	if !req.MergeRequiresRevalidate {
		out.RejectReasons = append(out.RejectReasons, "merge_must_revalidate_candidate")
	}

	seenPaths := map[string]string{}
	seenWS := map[string]bool{}
	for _, w := range req.Writers {
		if !w.IsolatedWorkspace {
			out.RejectReasons = append(out.RejectReasons, "non_isolated_workspace:"+w.WorkerID)
		}
		if w.SharedMutable {
			out.RejectReasons = append(out.RejectReasons, "shared_mutable:"+w.WorkerID)
		}
		if seenWS[w.WorkspaceID] {
			out.RejectReasons = append(out.RejectReasons, "duplicate_workspace:"+w.WorkspaceID)
		}
		seenWS[w.WorkspaceID] = true
		for _, p := range w.MutablePaths {
			if other, ok := seenPaths[p]; ok {
				out.RejectReasons = append(out.RejectReasons, "overlapping_path:"+p+"/"+other+"+"+w.WorkerID)
			} else {
				seenPaths[p] = w.WorkerID
			}
		}
		out.WorkspaceIDs = append(out.WorkspaceIDs, w.WorkspaceID)
	}

	if len(out.RejectReasons) > 0 {
		out.Admitted = false
		return out, nil
	}
	out.Admitted = true
	out.IntegrationOwnerID = req.IntegrationOwnerID
	out.MergeRevalidates = true
	return out, nil
}
