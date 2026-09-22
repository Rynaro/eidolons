package main

import (
	"encoding/json"
	"errors"
	"flag"
	"os"
	"time"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
	"github.com/Rynaro/eidolons/gauge/internal/controller"
)

func isContextCommand(c string) bool {
	switch c {
	case "context-enable", "context-session", "context-reuse", "context-present",
		"context-succeed", "context-memory", "context-batch", "context-debounce",
		"context-overhead", "context-navigate", "context-feature-na":
		return true
	}
	return false
}

func contextCommand(args []string) error {
	command := args[0]
	flags := flag.NewFlagSet(command, flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	project := flags.String("project", ".", "project/controller directory")
	timeout := flags.Duration("lock-timeout", 5*time.Second, "bounded local lock wait")
	root := flags.String("root", "", "execution root")
	session := flags.String("session", "", "context session id")
	input := flags.String("input", "", "strict JSON document path")
	requirement := flags.String("requirement", "", "requirement id for feature N/A")
	testID := flags.String("test", "", "test id for feature N/A")
	feature := flags.String("feature", "", "indexed_information_access|recursive_information_access")
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
	case "context-enable":
	case "context-session":
		allowed["root"], allowed["session"] = true, true
	case "context-reuse", "context-present", "context-succeed", "context-memory",
		"context-batch", "context-debounce", "context-overhead", "context-navigate":
		allowed["input"] = true
	case "context-feature-na":
		allowed["requirement"], allowed["test"], allowed["feature"] = true, true, true
	}
	for name := range seen {
		if !allowed[name] {
			return errors.New("option is not applicable to this command: " + name)
		}
	}
	s := controller.New(*project, controller.Options{Timeout: *timeout})
	var result any
	switch command {
	case "context-enable":
		if e := s.EnsureContextNamespaces(); e != nil {
			return e
		}
		result = map[string]any{
			"context_namespaces": true,
			"schema_version":     2,
			"typed_version":      contract.ContextSchemaVersion,
			"contract_version":   contract.ContextContractID,
			"slice":              contract.ContextSliceCore,
			"optional_adapter":   contract.OptionalAdapterOutOfScope,
			"optional_adapter_name": contract.OptionalAdapterName,
			"model_calls":        0,
			"scope":              "core-context-bounded-information-access",
			"live_qualification": "blocked",
			"crystalium":         "optional_never_operational_truth",
			"atomos":             "compose_verify_only",
			"vector_store":       "not_mandatory",
		}
	case "context-session":
		if *session == "" || *root == "" {
			return errors.New("context-session requires --session and --root")
		}
		sess, e := s.OpenContextSession(*session, *root)
		if e != nil {
			return e
		}
		result = sess
	case "context-reuse":
		raw, e := readInput(*input)
		if e != nil {
			return e
		}
		req, e := contract.DecodeEvidenceReuseRequest(raw)
		if e != nil {
			return e
		}
		result, e = s.ReuseEvidence(req)
		if e != nil {
			return e
		}
	case "context-present":
		raw, e := readInput(*input)
		if e != nil {
			return e
		}
		req, e := contract.DecodePresentationRequest(raw)
		if e != nil {
			return e
		}
		result, e = s.PresentBoundedEvidence(req)
		if e != nil {
			return e
		}
	case "context-succeed":
		raw, e := readInput(*input)
		if e != nil {
			return e
		}
		req, e := contract.DecodeSuccessionRequest(raw)
		if e != nil {
			return e
		}
		result, e = s.SucceedContext(req)
		if e != nil {
			return e
		}
	case "context-memory":
		raw, e := readInput(*input)
		if e != nil {
			return e
		}
		req, e := contract.DecodeMemoryRecallRequest(raw)
		if e != nil {
			return e
		}
		result, e = s.RecallMemory(req)
		if e != nil {
			return e
		}
	case "context-batch":
		raw, e := readInput(*input)
		if e != nil {
			return e
		}
		req, e := contract.DecodeBatchToolRequest(raw)
		if e != nil {
			return e
		}
		result, e = s.EnforceBatchTools(req)
		if e != nil {
			return e
		}
	case "context-debounce":
		raw, e := readInput(*input)
		if e != nil {
			return e
		}
		req, e := contract.DecodeLifecycleTriggerRequest(raw)
		if e != nil {
			return e
		}
		result, e = s.TriggerLifecycle(req)
		if e != nil {
			return e
		}
	case "context-overhead":
		raw, e := readInput(*input)
		if e != nil {
			return e
		}
		req, e := contract.DecodeOverheadRequest(raw)
		if e != nil {
			return e
		}
		result, e = s.MeasureOverhead(req)
		if e != nil {
			return e
		}
	case "context-navigate":
		raw, e := readInput(*input)
		if e != nil {
			return e
		}
		req, e := contract.DecodeNavigationEvent(raw)
		if e != nil {
			return e
		}
		result, e = s.RecordNavigation(req)
		if e != nil {
			return e
		}
	case "context-feature-na":
		if *requirement == "" || *testID == "" || *feature == "" {
			return errors.New("context-feature-na requires --requirement --test --feature")
		}
		f, e := s.RecordFeatureNA(*requirement, *testID, *feature)
		if e != nil {
			return e
		}
		result = f
	}
	return json.NewEncoder(os.Stdout).Encode(result)
}
