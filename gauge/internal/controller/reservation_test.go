package controller

import (
	"fmt"
	"sync"
	"testing"
	"time"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
	"github.com/Rynaro/eidolons/gauge/internal/store"
)

func resService(t *testing.T) *Service {
	t.Helper()
	s := New(t.TempDir(), Options{Timeout: time.Second, Clock: func() time.Time {
		return time.Date(2026, 9, 22, 15, 0, 0, 0, time.UTC)
	}})
	if e := s.Init(); e != nil {
		t.Fatal(e)
	}
	if e := s.EnsureReservationNamespaces(); e != nil {
		t.Fatal(e)
	}
	return s
}

func resRoot(t *testing.T, s *Service, id string) {
	t.Helper()
	if e := s.InitRoot(id); e != nil {
		t.Fatal(e)
	}
}

func f64(n float64) *float64 { return &n }

func ceiling(scope string, n float64) contract.Ceiling {
	return contract.Ceiling{
		Resource: "tokens", Unit: "token", Pool: "shared-pool", Interval: "run",
		Scope: scope, Limit: f64(n),
	}
}

func baseAdmit(id, root, project, task string, amount float64, ceilings []contract.Ceiling) contract.AdmitRequest {
	return contract.AdmitRequest{
		ID: id, RootID: root, AssignmentID: "asg-" + id, ProjectID: project,
		AccountPool: "shared-pool", WindowEpoch: "window-1", TaskID: task,
		HeadroomKind: contract.HeadroomImplementation, WorkKind: contract.WorkOptionalImplementation,
		Amount: amount, EstimateProvenance: contract.EstimateProvenance{Kind: contract.ProvenanceEstimate, Source: "fixture"},
		Resource: "tokens", Unit: "token", Pool: "shared-pool", PolicyID: "policy-fixture-1",
		Ceilings: ceilings, ConcurrencyIdentity: "shared-pool", ConcurrencyAmount: 1,
		ObservationUsable: true, RecordedAt: "2026-09-22T15:00:00Z",
	}
}

func allCeilings(task, project, account, window, concurrency float64) []contract.Ceiling {
	return []contract.Ceiling{
		ceiling("task", task), ceiling("project", project), ceiling("account", account),
		ceiling("window", window), ceiling("concurrency", concurrency),
	}
}

// TestV411T01 — concurrent assignments reserve without jointly exceeding known ceilings.
func TestV411T01(t *testing.T) {
	s := resService(t)
	resRoot(t, s, "root-a")
	resRoot(t, s, "root-b")
	ceilings := allCeilings(100, 80, 50, 100, 4) // shared account pool 50; concurrency 4

	db, e := s.ReservationStoreForTest()
	if e != nil {
		t.Fatal(e)
	}
	defer db.Close()

	var reqs []contract.AdmitRequest
	for i := 0; i < 10; i++ {
		root := "root-a"
		project := "project-a"
		task := "task-a"
		if i%2 == 1 {
			root = "root-b"
			project = "project-b"
			task = "task-b"
		}
		reqs = append(reqs, baseAdmit(fmt.Sprintf("adm-%02d", i), root, project, task, 10, ceilings))
	}
	results := db.ConcurrentAdmit(reqs)
	accepted := 0
	var acceptedIDs []string
	for _, r := range results {
		if r.Admitted {
			accepted++
			acceptedIDs = append(acceptedIDs, r.ReservationID)
		}
	}
	// Account ceiling 50 / 10 = 5 admits max; concurrency 4 may bind tighter.
	if accepted > 5 {
		t.Fatalf("jointly exceeded account ceiling: accepted=%d ids=%v", accepted, acceptedIDs)
	}
	if accepted < 4 {
		t.Fatalf("expected at least concurrency-limited admits, got %d (%v)", accepted, results)
	}
	bals, e := db.ListScopeBalances("")
	if e != nil {
		t.Fatal(e)
	}
	var account contract.ScopeBalance
	found := false
	for _, b := range bals {
		if b.Key.Scope == "account" && b.Key.Identity == "shared-pool" {
			account = b
			found = true
		}
	}
	if !found {
		t.Fatal("missing account balance")
	}
	if account.ExposureTotal() > 50+1e-9 {
		t.Fatalf("account exposure %v exceeds ceiling 50", account.ExposureTotal())
	}
	for _, scope := range []string{"task", "project", "window", "concurrency"} {
		ok := false
		for _, b := range bals {
			if b.Key.Scope == scope {
				ok = true
				if b.Ceiling != nil && b.ExposureTotal() > *b.Ceiling+1e-9 {
					t.Fatalf("%s exposure exceeds ceiling", scope)
				}
			}
		}
		if !ok {
			t.Fatalf("missing scoped balance %s", scope)
		}
	}
}

// TestV411T02 — verification/recovery headroom excluded from optional implementation.
func TestV411T02(t *testing.T) {
	s := resService(t)
	resRoot(t, s, "root-t02")
	ceilings := allCeilings(100, 100, 100, 100, 10)
	req := baseAdmit("near-limit", "root-t02", "proj", "task-t02", 80, ceilings)
	req.ProtectedVerification = 15
	req.ProtectedRecovery = 5
	r, e := s.AdmitReservation("root-t02", req)
	if e != nil || !r.Admitted {
		t.Fatalf("seed admit: %+v %v", r, e)
	}
	// Optional exploration near limit should reject (remaining 100-80-15-5=0).
	explore := baseAdmit("explore", "root-t02", "proj", "task-t02", 1, ceilings)
	explore.ProtectedVerification = 15
	explore.ProtectedRecovery = 5
	out, e := s.AdmitReservation("root-t02", explore)
	if e != nil {
		t.Fatal(e)
	}
	if out.Admitted {
		t.Fatal("optional exploration must not borrow verification/recovery headroom")
	}
	// Authorized verification can use designated reserve.
	verify := baseAdmit("verify", "root-t02", "proj", "task-t02", 10, ceilings)
	verify.WorkKind = contract.WorkVerification
	verify.HeadroomKind = contract.HeadroomVerification
	verify.ProtectedVerification = 15
	verify.ProtectedRecovery = 5
	vout, e := s.AdmitReservation("root-t02", verify)
	if e != nil || !vout.Admitted {
		t.Fatalf("verification admit: %+v %v", vout, e)
	}
}

// TestV411T03 — overrun/late usage/corrections retain actual exposure; stop new work past ceiling.
func TestV411T03(t *testing.T) {
	s := resService(t)
	resRoot(t, s, "root-t03")
	ceilings := allCeilings(50, 50, 50, 50, 10)
	r, e := s.AdmitReservation("root-t03", baseAdmit("est", "root-t03", "proj", "task-t03", 30, ceilings))
	if e != nil || !r.Admitted {
		t.Fatalf("admit: %+v %v", r, e)
	}
	_, bals, e := s.AmendReservation("root-t03", contract.AmendRequest{
		ReservationID: "est", Observed: 45, Kind: contract.AmendOverrun, RecordedAt: "2026-09-22T15:01:00Z",
	})
	if e != nil {
		t.Fatal(e)
	}
	var taskBal contract.ScopeBalance
	for _, b := range bals {
		if b.Key.Scope == "task" {
			taskBal = b
		}
	}
	if taskBal.Consumed < 45-1e-9 {
		t.Fatalf("overrun clamped away: %+v", taskBal)
	}
	// New work that would exceed ceiling rejects.
	more := baseAdmit("more", "root-t03", "proj", "task-t03", 10, ceilings)
	out, e := s.AdmitReservation("root-t03", more)
	if e != nil {
		t.Fatal(e)
	}
	if out.Admitted {
		t.Fatal("new work past ceiling after overrun must reject")
	}
	// Late usage / correction still retain exposure.
	_, bals2, e := s.AmendReservation("root-t03", contract.AmendRequest{
		ReservationID: "est", Observed: 48, Kind: contract.AmendLateUsage, RecordedAt: "2026-09-22T15:02:00Z",
	})
	if e != nil {
		t.Fatal(e)
	}
	for _, b := range bals2 {
		if b.Key.Scope == "task" && b.Consumed < 48-1e-9 {
			t.Fatalf("late usage clamped: %+v", b)
		}
	}
}

// TestV411T04 — unknown outcome retains uncertain exposure; no automatic release.
func TestV411T04(t *testing.T) {
	s := resService(t)
	resRoot(t, s, "root-t04")
	ceilings := allCeilings(100, 100, 100, 100, 10)
	reasons := []string{
		contract.UncertainCrash, contract.UncertainTimeout,
		contract.UncertainMissingCallback, contract.UncertainCancellationAfterSend,
	}
	for i, reason := range reasons {
		id := fmt.Sprintf("u-%d", i)
		r, e := s.AdmitReservation("root-t04", baseAdmit(id, "root-t04", "proj", "task-t04", 5, ceilings))
		if e != nil || !r.Admitted {
			t.Fatalf("admit %s: %+v %v", id, r, e)
		}
		res, e := s.MarkReservationUncertain("root-t04", contract.MarkUncertainRequest{
			ReservationID: id, Reason: reason, RecordedAt: "2026-09-22T15:03:00Z",
		})
		if e != nil {
			t.Fatal(reason, e)
		}
		if res.Status != contract.ReservationUncertain || res.Exposure != contract.ExposureUncertain {
			t.Fatalf("expected uncertain retention for %s: %+v", reason, res)
		}
		if res.Status == contract.ReservationReleased {
			t.Fatal("automatic release forbidden")
		}
	}
	_, bals, e := s.ReservationStatus("root-t04")
	if e != nil {
		t.Fatal(e)
	}
	var taskBal contract.ScopeBalance
	for _, b := range bals {
		if b.Key.Scope == "task" && b.Key.Identity == "task-t04" {
			taskBal = b
		}
	}
	if taskBal.Uncertain < 20-1e-9 {
		t.Fatalf("uncertain exposure auto-released: %+v", taskBal)
	}
	// Explicit reconcile with proof may release; without proof stays reconciled/uncertain path.
	_, e = s.ReconcileReservation("root-t04", contract.ReconcileRequest{
		ReservationID: "u-0", Actual: 5, Release: true, ReleaseProof: "operator-proof-1",
		RecordedAt: "2026-09-22T15:04:00Z",
	})
	if e != nil {
		t.Fatal(e)
	}
}

// TestV411T05 — provider window reset preserves root task consumption.
func TestV411T05(t *testing.T) {
	s := resService(t)
	resRoot(t, s, "root-t05")
	ceilings := allCeilings(100, 100, 100, 40, 10)
	r, e := s.AdmitReservation("root-t05", baseAdmit("w1", "root-t05", "proj", "task-t05", 20, ceilings))
	if e != nil || !r.Admitted {
		t.Fatalf("admit: %+v %v", r, e)
	}
	_, bals, e := s.AmendReservation("root-t05", contract.AmendRequest{
		ReservationID: "w1", Observed: 20, Kind: contract.AmendLateUsage, RecordedAt: "2026-09-22T15:05:00Z",
	})
	if e != nil {
		t.Fatal(e)
	}
	var taskBefore float64
	for _, b := range bals {
		if b.Key.Scope == "task" {
			taskBefore = b.Consumed
		}
	}
	out, e := s.ResetProviderWindow("root-t05", contract.WindowResetRequest{
		RootID: "root-t05", Resource: "tokens", Unit: "token", Pool: "shared-pool",
		OldEpoch: "window-1", NewEpoch: "window-2", NewWindowCeiling: f64(40),
		RecordedAt: "2026-09-22T15:06:00Z",
	})
	if e != nil {
		t.Fatal(e)
	}
	var taskAfter, newWindow *contract.ScopeBalance
	for i := range out {
		b := &out[i]
		if b.Key.Scope == "task" {
			taskAfter = b
		}
		if b.Key.Scope == "window" && b.Key.Identity == "window-2" {
			newWindow = b
		}
	}
	if taskAfter == nil || taskAfter.Consumed != taskBefore {
		t.Fatalf("task budget refilled on window reset: before=%v after=%+v", taskBefore, taskAfter)
	}
	if newWindow == nil || newWindow.Consumed != 0 {
		t.Fatalf("new window should start without old-window consumption: %+v", newWindow)
	}
}

// TestV411T06 — authoritative accounting unavailable rejects managed dispatch; advisory separate.
func TestV411T06(t *testing.T) {
	s := resService(t)
	resRoot(t, s, "root-t06")
	ceilings := allCeilings(100, 100, 100, 100, 10)
	db, e := s.ReservationStoreForTest()
	if e != nil {
		t.Fatal(e)
	}
	defer db.Close()

	for _, fault := range []store.AccountingFault{
		store.FaultCorruption, store.FaultLockTimeout, store.FaultFullStorage, store.FaultReadOnly,
	} {
		db.SetAccountingFault(fault)
		out, e := db.AdmitReservation(baseAdmit("f-"+string(fault), "root-t06", "proj", "task-t06", 1, ceilings))
		if e != nil {
			t.Fatal(fault, e)
		}
		if out.Admitted || out.AccountingOK {
			t.Fatalf("managed admit must reject under %s: %+v", fault, out)
		}
		if len(out.RejectReasons) == 0 {
			t.Fatalf("expected reject reason for %s", fault)
		}
		db.ClearAccountingFault()
	}
	// Advisory hooks keep a separate error policy.
	if e := db.AdvisoryHookFailure(); e != store.AdvisoryHookError {
		t.Fatalf("advisory policy mismatch: %v", e)
	}
	ok, e := db.AdmitReservation(baseAdmit("ok", "root-t06", "proj", "task-t06", 1, ceilings))
	if e != nil || !ok.Admitted {
		t.Fatalf("admit after clear: %+v %v", ok, e)
	}
}

// TestV411T07 — hard-limited unknown without bound rejects; explicit bounded mode is positive control.
func TestV411T07(t *testing.T) {
	s := resService(t)
	resRoot(t, s, "root-t07")
	ceilings := allCeilings(100, 100, 100, 100, 10)

	unknown := baseAdmit("unk", "root-t07", "proj", "task-t07", 5, ceilings)
	unknown.HardLimited = true
	unknown.ObservationUsable = false
	unknown.ExplicitBoundedMode = false
	unknown.AuthorizedBound = nil
	out, e := s.AdmitReservation("root-t07", unknown)
	if e != nil {
		t.Fatal(e)
	}
	if out.Admitted {
		t.Fatal("unsupported hard-limited data must not become unlimited")
	}

	db, e := s.ReservationStoreForTest()
	if e != nil {
		t.Fatal(e)
	}
	defer db.Close()
	for _, scope := range []struct {
		scope, id string
	}{
		{"task", "task-t07b"}, {"project", "proj-b"}, {"account", "shared-pool-b"},
		{"window", "window-1"}, {"concurrency", "shared-pool-b"},
	} {
		if e := db.SeedScopeBalance(contract.ScopeBalance{
			Key: contract.ScopeBalanceKey{
				Scope: scope.scope, Identity: scope.id, Resource: "tokens", Unit: "token", Pool: "shared-pool",
			},
			HardLimited: true, ObservationUsable: false, ExplicitBoundedMode: true, AuthorizedBound: f64(20),
		}); e != nil {
			t.Fatal(scope, e)
		}
	}
	bounded := baseAdmit("bound-ok", "root-t07", "proj-b", "task-t07b", 5, nil)
	bounded.AccountPool = "shared-pool-b"
	bounded.Pool = "shared-pool"
	bounded.HardLimited = true
	bounded.ObservationUsable = false
	bounded.ExplicitBoundedMode = true
	bounded.AuthorizedBound = f64(20)
	bounded.ConcurrencyIdentity = "shared-pool-b"
	bout, e := db.AdmitReservation(bounded)
	if e != nil {
		t.Fatal(e)
	}
	if !bout.Admitted {
		t.Fatalf("explicit bounded mode is positive control: %+v", bout)
	}
}

// TestV411T08 — child/retry reserves implementation+integration+verification; cannot borrow protected headroom.
func TestV411T08(t *testing.T) {
	s := resService(t)
	resRoot(t, s, "root-t08")
	ceilings := allCeilings(100, 100, 100, 100, 10)

	parent := baseAdmit("parent", "root-t08", "proj", "task-t08", 40, ceilings)
	parent.ProtectedVerification = 20
	parent.ProtectedRecovery = 10
	pout, e := s.AdmitReservation("root-t08", parent)
	if e != nil || !pout.Admitted {
		t.Fatalf("parent: %+v %v", pout, e)
	}

	// Parallel child under parent: joint = impl+integration+verification.
	child := baseAdmit("child-1", "root-t08", "proj", "task-t08", 0, ceilings)
	child.ParentReservationID = "parent"
	child.WorkKind = contract.WorkChild
	child.HeadroomKind = contract.HeadroomImplementation
	child.ImplementationAmount = 10
	child.IntegrationAmount = 5
	child.VerificationAmount = 5
	child.ProtectedVerification = 20
	child.ProtectedRecovery = 10
	cout, e := s.AdmitReservation("root-t08", child)
	if e != nil || !cout.Admitted {
		t.Fatalf("child: %+v %v", cout, e)
	}
	if cout.Reservation == nil || cout.Reservation.Amount != 20 {
		t.Fatalf("joint child amount: %+v", cout.Reservation)
	}

	// Failed candidate + repeated retry also joint-reserve; cannot borrow protected headroom.
	// Remaining optional: 100 - 40 - 20 - 20(protV) - 10(protR) = 10.
	retry := baseAdmit("retry-1", "root-t08", "proj", "task-t08", 0, ceilings)
	retry.ParentReservationID = "parent"
	retry.WorkKind = contract.WorkRetry
	retry.ImplementationAmount = 5
	retry.IntegrationAmount = 3
	retry.VerificationAmount = 2
	retry.ProtectedVerification = 20
	retry.ProtectedRecovery = 10
	rout, e := s.AdmitReservation("root-t08", retry)
	if e != nil || !rout.Admitted {
		t.Fatalf("retry within remaining: %+v %v", rout, e)
	}

	// Another child that would borrow protected headroom rejects.
	borrow := baseAdmit("child-borrow", "root-t08", "proj", "task-t08", 0, ceilings)
	borrow.ParentReservationID = "parent"
	borrow.WorkKind = contract.WorkChild
	borrow.ImplementationAmount = 5
	borrow.IntegrationAmount = 5
	borrow.VerificationAmount = 5 // joint 15 > remaining ~0
	borrow.ProtectedVerification = 20
	borrow.ProtectedRecovery = 10
	bout, e := s.AdmitReservation("root-t08", borrow)
	if e != nil {
		t.Fatal(e)
	}
	if bout.Admitted {
		t.Fatal("child must not borrow protected verification/recovery headroom")
	}
}

// TestV411ConcurrencyStress — extra contention stress beyond T01.
func TestV411ConcurrencyStress(t *testing.T) {
	s := resService(t)
	resRoot(t, s, "root-stress")
	ceilings := allCeilings(200, 200, 100, 200, 8)
	db, e := s.ReservationStoreForTest()
	if e != nil {
		t.Fatal(e)
	}
	defer db.Close()

	const n = 40
	reqs := make([]contract.AdmitRequest, n)
	for i := 0; i < n; i++ {
		reqs[i] = baseAdmit(fmt.Sprintf("s-%02d", i), "root-stress", "proj", "task-stress", 10, ceilings)
	}
	var wg sync.WaitGroup
	results := make([]contract.AdmitResult, n)
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			results[i], _ = db.AdmitReservation(reqs[i])
		}(i)
	}
	wg.Wait()
	accepted := 0
	for _, r := range results {
		if r.Admitted {
			accepted++
		}
	}
	if accepted > 10 { // account ceiling 100 / 10
		t.Fatalf("stress exceeded account ceiling: %d", accepted)
	}
	bals, e := db.ListScopeBalances("account")
	if e != nil {
		t.Fatal(e)
	}
	for _, b := range bals {
		if b.ExposureTotal() > 100+1e-9 {
			t.Fatalf("account over: %+v", b)
		}
	}
}
