package main

import (
	"encoding/json"
	"errors"
	"flag"
	"os"
	"time"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
	"github.com/Rynaro/eidolons/gauge/internal/controller"
	"github.com/Rynaro/eidolons/gauge/internal/store"
)

func isPolicyCommand(c string) bool {
	switch c {
	case "migrate", "preferences", "preferences-set", "policy-compile", "policy-bind", "policy-amend", "policy-show", "policy-binding", "amendment-show", "strategy-select":
		return true
	}
	return false
}
func policyCommand(args []string) error {
	command := args[0]
	flags := flag.NewFlagSet(command, flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	project := flags.String("project", ".", "project/controller directory")
	timeout := flags.Duration("lock-timeout", 5*time.Second, "bounded local lock wait")
	root := flags.String("root", "", "execution root")
	layer := flags.String("layer", "", "controller-local logical layer: user or project; not an authenticated identity")
	revision := flags.Uint64("expected-revision", 0, "required current layer revision for CAS")
	input := flags.String("input", "", "strict JSON document path; no trust labels")
	authorizationID := flags.String("authorization-id", "", "pre-authorized request identifier; never a credential")
	predecessor := flags.String("predecessor", "", "expected immutable policy identity")
	policyID := flags.String("policy-id", "", "immutable typed policy identity")
	if e := flags.Parse(args[1:]); e != nil {
		return e
	}
	if flags.NArg() != 0 {
		return errors.New("unexpected positional arguments")
	}
	if *timeout <= 0 || *timeout > 300*time.Second {
		return errors.New("lock timeout must be positive and at most 300s")
	}
	seen := map[string]bool{}
	flags.Visit(func(f *flag.Flag) { seen[f.Name] = true })
	allowed := map[string]bool{"project": true, "lock-timeout": true}
	switch command {
	case "preferences-set":
		allowed["layer"], allowed["expected-revision"], allowed["input"] = true, true, true
	case "policy-compile":
		allowed["input"] = true
	case "policy-bind", "policy-amend":
		allowed["root"], allowed["authorization-id"], allowed["predecessor"], allowed["input"] = true, true, true, true
	case "policy-show", "strategy-select":
		allowed["root"], allowed["policy-id"] = true, true
		if command == "strategy-select" {
			allowed["input"] = true
		}
	case "policy-binding":
		allowed["root"] = true
	case "amendment-show":
		allowed["root"], allowed["authorization-id"] = true, true
	}
	for name := range seen {
		if !allowed[name] {
			return errors.New("option is not applicable to this command: " + name)
		}
	}
	switch command {
	case "policy-bind", "policy-amend", "policy-show", "policy-binding", "amendment-show", "strategy-select":
		if *root == "" {
			return errors.New("--root is required")
		}
	}
	if command == "preferences-set" && (!seen["expected-revision"] || *input == "" || *layer == "") {
		return errors.New("preferences-set requires --layer, --expected-revision and --input")
	}
	s := controller.New(*project, controller.Options{Timeout: *timeout})
	var result any
	switch command {
	case "migrate":
		if e := s.Migrate(); e != nil {
			return e
		}
		result = map[string]any{"schema_version": 2, "migrated": true, "scope": "controller-instance"}
	case "preferences":
		v, e := s.ReadPreferences()
		if e != nil {
			return e
		}
		result = map[string]any{"scope": "controller-local user/project layers; not OS identity or account-wide settings", "layers": v}
	case "preferences-set":
		raw, e := os.ReadFile(*input)
		if e != nil {
			return e
		}
		p, e := contract.DecodePreferences(raw)
		if e != nil {
			return e
		}
		v, e := s.UpdatePreferences(*layer, *revision, p)
		if e != nil {
			return e
		}
		result = v
	case "policy-compile", "policy-bind", "policy-amend":
		// Unbound inspection defaults cannot authorize execution. A real trusted
		// composition must provide the actual acceptance contract before binding.
		patch := contract.PolicyPatch{Run: contract.Preferences{Version: 1}, Required: contract.Requirements{Checks: []string{"acceptance", "regression"}, Criteria: "unavailable", Grade: "unqualified"}}
		if *input != "" {
			raw, e := os.ReadFile(*input)
			if e != nil {
				return e
			}
			patch, e = store.DecodePolicyPatch(raw)
			if e != nil {
				return e
			}
		}
		if command == "policy-compile" {
			v, e := s.CompilePolicy(patch)
			if e != nil {
				return e
			}
			result = v
		} else {
			if *authorizationID == "" {
				return errors.New("--authorization-id is required (not a credential)")
			}
			if command == "policy-bind" && *predecessor != "" {
				return errors.New("initial binding requires empty predecessor")
			}
			v, e := s.ApplyPolicy(*root, contract.PolicyRequest{Version: 1, Root: *root, Predecessor: *predecessor, AuthorizationID: *authorizationID, Patch: patch})
			if e != nil {
				return e
			}
			result = v
		}
	case "policy-show":
		v, e := s.ReadPolicy(*root, *policyID)
		if e != nil {
			return e
		}
		result = v
	case "policy-binding":
		v, e := s.ReadPolicyBinding(*root)
		if e != nil {
			return e
		}
		result = v
	case "amendment-show":
		v, e := s.ReadAmendment(*root, *authorizationID)
		if e != nil {
			return e
		}
		result = v
	case "strategy-select":
		raw, e := os.ReadFile(*input)
		if e != nil {
			return e
		}
		proposal, e := contract.DecodeStrategy(raw)
		if e != nil {
			return e
		}
		p, e := s.ReadPolicy(*root, *policyID)
		if e != nil {
			return e
		}
		v, e := contract.SelectStrategy(p, proposal)
		if e != nil {
			return e
		}
		result = v
	}
	return json.NewEncoder(os.Stdout).Encode(result)
}
