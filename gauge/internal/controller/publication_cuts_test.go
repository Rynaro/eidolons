package controller_test

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
)

// These windows are inside Promote, unlike the existing "before" and
// "published" whole-call boundaries in repair_test.go.
func TestV406T04_PublicationWindows(t *testing.T) {
	for _, phase := range []string{"claim-published", "marker-published"} {
		t.Run(phase, func(t *testing.T) {
			p := t.TempDir()
			run := legacyFixture(t, p, "legacy-complex")
			s := service(t, p)
			if err := s.Init(); err != nil {
				t.Fatal(err)
			}
			if err := s.Import(run); err != nil {
				t.Fatal(err)
			}
			before := readStore(t, p)
			if before.Roots[run].Phase != "staged" {
				t.Fatal("import must remain staged")
			}
			runDir := filepath.Join(p, ".eidolons/.ledger", run)
			events := filepath.Join(runDir, "events")
			originals := map[string][]byte{}
			entries, err := os.ReadDir(events)
			if err != nil {
				t.Fatal(err)
			}
			for _, entry := range entries {
				raw, err := os.ReadFile(filepath.Join(events, entry.Name()))
				if err != nil {
					t.Fatal(err)
				}
				originals[entry.Name()] = raw
			}
			assertHistory := func() {
				t.Helper()
				if !reflect.DeepEqual(before.Legacy[run], readStore(t, p).Legacy[run]) {
					t.Fatal("imported bytes, IDs or grades changed")
				}
				entries, err := os.ReadDir(events)
				if err != nil {
					t.Fatal(err)
				}
				if len(entries) != len(originals) {
					t.Fatal("legacy inventory changed")
				}
				for _, entry := range entries {
					raw, err := os.ReadFile(filepath.Join(events, entry.Name()))
					if err != nil || !bytes.Equal(raw, originals[entry.Name()]) {
						t.Fatalf("legacy bytes changed: %s: %v", entry.Name(), err)
					}
				}
			}
			exe, err := os.Executable()
			if err != nil {
				t.Fatal(err)
			}
			child := func(mode string) *exec.Cmd {
				c := exec.Command(exe, "-test.run=^TestV406RepairPromotionChild$")
				c.Env = append(os.Environ(), "V406_PROCESS_PROJECT="+p, "V406_PROCESS_ROOT="+run, "V406_PROCESS_MODE="+mode)
				return c
			}
			c := child(phase)
			out, err := c.StdoutPipe()
			if err != nil {
				t.Fatal(err)
			}
			if err = c.Start(); err != nil {
				t.Fatal(err)
			}
			reaped := false
			defer func() {
				if !reaped {
					_ = c.Process.Kill()
					_ = c.Wait()
				}
			}()
			ready := make(chan string, 1)
			go func() { line, _ := bufio.NewReader(out).ReadString('\n'); ready <- line }()
			select {
			case line := <-ready:
				if line != "READY\n" {
					t.Fatalf("exact %s callback not reached: %q (missing publication fault-injection coverage)", phase, line)
				}
			case <-time.After(15 * time.Second):
				t.Fatalf("exact %s callback timed out", phase)
			}
			lock := filepath.Join(runDir, ".append-lock")
			owner, err := os.ReadFile(filepath.Join(lock, "owner"))
			if err != nil || len(owner) == 0 {
				t.Fatalf("callback did not retain append ownership: %v", err)
			}
			claimPath := filepath.Join(p, ".eidolons/.ledger/.gauge-controller-v1", "authority-"+run+".json")
			claim, err := os.ReadFile(claimPath)
			if err != nil {
				t.Fatal("claim not durably published", err)
			}
			var proof struct {
				Phase  string `json:"phase"`
				RootID string `json:"root_id"`
			}
			if err = json.Unmarshal(claim, &proof); err != nil || proof.Phase != "pending" || proof.RootID != run {
				t.Fatalf("wrong claim: %s: %v", claim, err)
			}
			markerPath := filepath.Join(runDir, ".writer-authority.json")
			marker, markerErr := os.ReadFile(markerPath)
			paused := readStore(t, p)
			wantRoot := before.Roots[run]
			if phase == "claim-published" {
				if !os.IsNotExist(markerErr) {
					t.Fatal("claim callback must precede pending marker", markerErr)
				}
			} else {
				if markerErr != nil {
					t.Fatal(markerErr)
				}
				if err = json.Unmarshal(marker, &proof); err != nil || proof.Phase != "active" || proof.RootID != run {
					t.Fatalf("final marker not published: %s: %v", marker, err)
				}
				wantRoot.Phase = "active"
			}
			if !reflect.DeepEqual(wantRoot, paused.Roots[run]) {
				t.Fatal("publication window has wrong staged/active root or changed identity")
			}
			contender := child("contender")
			if output, err := contender.CombinedOutput(); err == nil || !strings.Contains(string(output), "append ownership unavailable") {
				t.Fatalf("competing promoter did not refuse ownership: %v %s", err, output)
			}
			_, stderr, rc := cli(t, p, "ledger", "record", "--run-id", run, "--type", "publication-race")
			if rc == 0 {
				t.Fatalf("Bash writer entered publication window: %s", stderr)
			}
			assertHistory()
			if !reflect.DeepEqual(paused, readStore(t, p)) {
				t.Fatal("refused competing writer changed state")
			}
			if err = c.Process.Kill(); err != nil {
				t.Fatal(err)
			}
			if err = c.Wait(); err == nil {
				t.Fatal("child did not terminate from kill")
			}
			reaped = true
			t.Logf("reached exact %s with append ownership held; killed and reaped pid=%d; competing promoter and Bash refused", phase, c.Process.Pid)
			if _, err = s.Status(run); err == nil {
				t.Fatal("status accepted unresolved lock")
			}
			if err = s.Promote(run); err == nil {
				t.Fatal("promotion stole unresolved lock")
			}
			if err = s.Recover(run); err == nil {
				t.Fatal("recovery stole unresolved lock")
			}
			gotOwner, err := os.ReadFile(filepath.Join(lock, "owner"))
			if err != nil || !bytes.Equal(owner, gotOwner) {
				t.Fatal("unresolved ownership changed", err)
			}
			if !reflect.DeepEqual(paused, readStore(t, p)) {
				t.Fatal("unresolved-lock refusals changed state")
			}
			assertHistory()
			// Wait above and synchronous contender/Bash completion establish quiescence.
			// Only this explicit operator action removes the unresolved lock.
			if err = os.Remove(filepath.Join(lock, "owner")); err != nil {
				t.Fatal(err)
			}
			if err = os.Remove(lock); err != nil {
				t.Fatal(err)
			}
			if phase == "claim-published" {
				if err = s.Promote(run); err == nil {
					t.Fatal("claim-only transfer bypassed explicit recovery")
				}
			}
			if err = s.Recover(run); err != nil {
				t.Fatal("explicit quiescent recovery", err)
			}
			status, err := s.Status(run)
			if err != nil || status.Root.Phase != "active" || !reflect.DeepEqual(before.Legacy[run], status.Imported) {
				t.Fatal("recovery did not preserve active imported history", err)
			}
			recovered := readStore(t, p)
			if err = s.Recover(run); err != nil {
				t.Fatal("idempotent recovery", err)
			}
			if err = s.Promote(run); err != nil {
				t.Fatal("idempotent promotion", err)
			}
			if !reflect.DeepEqual(recovered, readStore(t, p)) {
				t.Fatal("retry changed logical state")
			}
			assertHistory()
			if _, err = s.ExecuteFixture(context.Background(), run, "publication-recovery", contract.FixtureInput{Outcome: "pass"}); err != nil {
				t.Fatal("recovered positive mutation", err)
			}
			_, _, rc = cli(t, p, "ledger", "record", "--run-id", run, "--type", "after-publication-recovery")
			if rc == 0 {
				t.Fatal("recovery reopened legacy writes")
			}
			assertHistory()
		})
	}
}
