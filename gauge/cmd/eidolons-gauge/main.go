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
