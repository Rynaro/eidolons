package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"time"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
	"github.com/Rynaro/eidolons/gauge/internal/controller"
)

const usage = `Usage: eidolons gauge COMMAND [options]
  init [--root ID]                 initialize one controller instance / fixture root
  import --root ID                 stage an exact frozen legacy inventory
  promote --root ID                explicitly transfer this root's writer authority
  recover --root ID                complete a recorded interrupted transfer
  status --root ID                 read current typed state (acceptance unavailable)
  fixture --root ID --event-id ID --outcome pass|fail|cancelled
  replace --root ID [--worker ID] [--environment ID] --reconstruction fixture

  migrate                          explicitly migrate supported schema 1 to 2
  preferences                      inspect controller-local user/project layers
  preferences-set --layer user|project --expected-revision N --input JSON
  policy-compile [--input JSON]     inspect unqualified effective policy
  policy-bind|policy-amend --root ID --authorization-id ID [--predecessor ID]
  policy-show --root ID --policy-id ID
  policy-binding --root ID
  amendment-show --root ID --authorization-id ID
  strategy-select --root ID --policy-id ID --input JSON

  observation-enable               add typed observation/lineage namespaces (schema 2)
  task-start --route-digest DIGEST allocate fresh UUID root distinct from route
  task-resume --root ID            resume existing root; unknown fails without create
  lineage-bind --root ID --input JSON
  usage-record --root ID --input JSON
  usage-correct --root ID --input JSON
  usage-summary --root ID --input STREAM-JSON
  usage-export --root ID           allowlisted observation export
  usage-retain --root ID           drop eligible detail; preserve totals/lineage

  instrument-enable                add typed instrument namespaces (schema 2)
  catalogue --input JSON           record host capability tuple (fixture scope)
  preflight --tuple ID [--input JSON]
  freeze --input JSON              freeze comparison protocol before outcomes
  record --input JSON              record native/v3 attempt under frozen protocol
  shadow --input JSON              shadow-observe without mutating execution
  report --protocol ID             instrument report (live remains blocked)
  eligibility --input JSON         record arm eligibility (no fabricated attempts)

  reservation-enable               add typed reservation namespaces (schema 2)
  reservation-admit --root ID --input JSON
  reservation-status --root ID
  reservation-amend --root ID --input JSON
  reservation-reconcile --root ID --input JSON

  dispatch-enable                  add typed dispatch namespaces (schema 2)
  admit-dispatch --root ID --input JSON
  dispatch-status --root ID
  dispatch-cancel --root ID --input JSON
  dispatch-reconcile --root ID --input JSON
  dispatch-events --root ID --intent ID

  compiler-enable                  add typed compiler namespaces (schema 2)
  compile --root ID --input JSON   compile assignments without mandatory chains
  compiler-status --root ID
  consult-validate --root ID --input JSON
  compiler-rebind --root ID --input JSON
  compiler-evidence --root ID --input JSON
  compiler-writers --root ID --input JSON

  acceptance-enable                add typed acceptance namespaces (schema 2)
  acceptance-register --root ID --input JSON
  candidate-freeze --root ID --input JSON
  acceptance-check --root ID --input JSON
  qualify --root ID --input JSON   qualify oracle on valid and defective fixtures
  apply --root ID --input JSON     gate application against target base
  acceptance-report --root ID --candidate ID
  acceptance-status --root ID
  owner-review --root ID --input JSON
  definition-assess --root ID --input JSON

  delivery-enable                  add typed delivery namespaces (schema 2)
  delivery-run --root ID --input JSON
  delivery-inspect --loop ID       observational status (no model work)
  delivery-status [--root ID]
  delivery-resume --root ID --input JSON
  delivery-cancel --root ID --input JSON
  delivery-compact --root ID --input JSON

User preferences are a logical layer local to this controller/project, not an
OS identity, home setting, cross-project default or authority grant. Production
activation is authorizer_boundary_unqualified; authorization IDs are not credentials.
Preset strategy bounds are illustrative registry rules, not calibrated budgets.
Observation recording never grants policy or spending authority.
Instrument catalogue/preflight never grants live host qualification.
Reservation admit is fixture-local atomic bookkeeping; no provider dispatch.
Dispatch admit uses one fixture-qualified fake native adapter; live stays blocked.
Compiler records inspectable selection reasons; semantic planning remains fallible.
Acceptance freezes candidates and qualifies protected oracles; no universal correctness;
no auto push/merge/release; candidate scripts cannot inherit checker credentials.
Delivery loop is the V4-15 observable runnable-slice demonstrator; minimal
inspect/status/resume/cancel only — full V4-20 CLI is deferred. No V4-16+.

Common options: --project PATH (default .), --lock-timeout DURATION (default 5s).
One shared local bbolt DB serves this controller instance. No account-wide or
cross-device authority is implied. Native harnesses own reasoning and editing.
Recover never steals an append lock: first establish that all writers and their
publishing children are quiescent, preserve pending files, and manually recover
ambiguous .append-lock ownership. Original legacy files remain historical.
`

func run(args []string) error {
	if len(args) == 0 || args[0] == "help" || args[0] == "--help" {
		fmt.Print(usage)
		return nil
	}
	command := args[0]
	if isPolicyCommand(command) {
		return policyCommand(args)
	}
	if isObservationCommand(command) {
		return observationCommand(args)
	}
	if isInstrumentCommand(command) {
		return instrumentCommand(args)
	}
	if isReservationCommand(command) {
		return reservationCommand(args)
	}
	if isDispatchCommand(command) {
		return dispatchCommand(args)
	}
	if isCompilerCommand(command) {
		return compilerCommand(args)
	}
	if isAcceptanceCommand(command) {
		return acceptanceCommand(args)
	}
	if isDeliveryCommand(command) {
		return deliveryCommand(args)
	}
	switch command {
	case "init", "import", "promote", "recover", "status", "fixture", "replace":
	default:
		return fmt.Errorf("unsupported Gauge command %q", command)
	}
	flags := flag.NewFlagSet(command, flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	project := flags.String("project", ".", "project directory")
	root := flags.String("root", "", "execution root")
	timeout := flags.Duration("lock-timeout", 5*time.Second, "bounded local lock wait")
	event := flags.String("event-id", "", "idempotent fixture request identity")
	outcome := flags.String("outcome", "", "observed fixture outcome")
	worker := flags.String("worker", "", "replacement worker identity")
	environment := flags.String("environment", "", "replacement environment identity")
	reconstruction := flags.String("reconstruction", "", "supported fixture reconstruction")
	if e := flags.Parse(args[1:]); e != nil {
		return e
	}
	if flags.NArg() != 0 {
		return errors.New("unexpected positional arguments")
	}
	if *timeout <= 0 || *timeout > 300*time.Second {
		return errors.New("lock timeout must be positive and at most 300s")
	}
	if command != "init" && *root == "" {
		return errors.New("--root is required")
	}
	if command != "fixture" && (*event != "" || *outcome != "") {
		return errors.New("--event-id and --outcome are exclusive to fixture")
	}
	if command != "replace" && (*worker != "" || *environment != "" || *reconstruction != "") {
		return errors.New("replacement options are exclusive to replace")
	}
	s := controller.New(*project, controller.Options{Timeout: *timeout})
	var result any
	switch command {
	case "init":
		if e := s.Init(); e != nil {
			return e
		}
		if *root != "" {
			if e := s.InitRoot(*root); e != nil {
				return e
			}
		}
		result = map[string]any{"initialized": true, "scope": "controller-instance", "root": *root}
	case "import":
		if e := s.Import(*root); e != nil {
			return e
		}
		result = map[string]string{"root": *root, "import": "frozen", "authority": "unchanged"}
	case "promote":
		if e := s.Promote(*root); e != nil {
			return e
		}
		result = map[string]string{"root": *root, "authority": "gauge"}
	case "recover":
		if e := s.Recover(*root); e != nil {
			return e
		}
		result = map[string]string{"root": *root, "authority": "gauge"}
	case "status":
		r, e := s.Status(*root)
		if e != nil {
			return e
		}
		result = r
	case "fixture":
		r, e := s.ExecuteFixture(context.Background(), *root, *event, contract.FixtureInput{Outcome: *outcome})
		if e != nil {
			return e
		}
		result = r
	case "replace":
		if e := s.Replace(*root, *worker, *environment, *reconstruction == "fixture"); e != nil {
			return e
		}
		result = map[string]string{"root": *root, "reconstruction": "fixture"}
	}
	return json.NewEncoder(os.Stdout).Encode(result)
}
func main() {
	if e := run(os.Args[1:]); e != nil {
		fmt.Fprintln(os.Stderr, "gauge:", e)
		os.Exit(1)
	}
}
