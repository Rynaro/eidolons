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

func isDispatchCommand(c string) bool {
	switch c {
	case "dispatch-enable", "admit-dispatch", "dispatch-status", "dispatch-cancel",
		"dispatch-reconcile", "dispatch-events":
		return true
	}
	return false
}

func dispatchCommand(args []string) error {
	command := args[0]
	flags := flag.NewFlagSet(command, flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	project := flags.String("project", ".", "project/controller directory")
	timeout := flags.Duration("lock-timeout", 5*time.Second, "bounded local lock wait")
	root := flags.String("root", "", "execution root")
	input := flags.String("input", "", "strict JSON document path")
	intent := flags.String("intent", "", "dispatch intent identity")
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
	case "dispatch-enable":
	case "admit-dispatch", "dispatch-cancel", "dispatch-reconcile":
		allowed["root"] = true
		allowed["input"] = true
	case "dispatch-status":
		allowed["root"] = true
	case "dispatch-events":
		allowed["root"] = true
		allowed["intent"] = true
	}
	for name := range seen {
		if !allowed[name] {
			return errors.New("option is not applicable to this command: " + name)
		}
	}
	s := controller.New(*project, controller.Options{Timeout: *timeout})
	var result any
	switch command {
	case "dispatch-enable":
		if e := s.EnsureDispatchNamespaces(); e != nil {
			return e
		}
		result = map[string]any{
			"dispatch_namespaces": true,
			"schema_version":      2,
			"typed_version":       contract.DispatchSchemaVersion,
			"scope":               "fixture-qualified-native-adapter",
			"live_qualification":  "blocked",
			"provider_network":    "excluded",
		}
	case "admit-dispatch":
		if *root == "" || *input == "" {
			return errors.New("admit-dispatch requires --root and --input")
		}
		raw, e := os.ReadFile(*input)
		if e != nil {
			return e
		}
		req, e := contract.DecodeAdmitDispatchRequest(raw)
		if e != nil {
			return e
		}
		adapter := controller.NewFakeNativeAdapter(controller.NewNativeMethodCounters())
		out, e := s.AdmitAndDispatch(*root, req, adapter, controller.DispatchFaultNone)
		if e != nil {
			return e
		}
		result = out
	case "dispatch-status":
		if *root == "" {
			return errors.New("dispatch-status requires --root")
		}
		intents, e := s.DispatchStatus(*root)
		if e != nil {
			return e
		}
		result = map[string]any{"intents": intents}
	case "dispatch-cancel":
		if *root == "" || *input == "" {
			return errors.New("dispatch-cancel requires --root and --input")
		}
		raw, e := os.ReadFile(*input)
		if e != nil {
			return e
		}
		req, e := contract.DecodeCancelDispatchRequest(raw)
		if e != nil {
			return e
		}
		adapter := controller.NewFakeNativeAdapter(controller.NewNativeMethodCounters())
		out, e := s.CancelDispatch(*root, req, adapter)
		if e != nil {
			return e
		}
		result = out
	case "dispatch-reconcile":
		if *root == "" || *input == "" {
			return errors.New("dispatch-reconcile requires --root and --input")
		}
		raw, e := os.ReadFile(*input)
		if e != nil {
			return e
		}
		req, e := contract.DecodeReconcileDispatchRequest(raw)
		if e != nil {
			return e
		}
		adapter := controller.NewFakeNativeAdapter(controller.NewNativeMethodCounters())
		out, e := s.ReconcileDispatch(*root, req, adapter)
		if e != nil {
			return e
		}
		result = out
	case "dispatch-events":
		if *root == "" || *intent == "" {
			return errors.New("dispatch-events requires --root and --intent")
		}
		events, e := s.DispatchEvents(*root, *intent)
		if e != nil {
			return e
		}
		result = map[string]any{"events": events}
	}
	return json.NewEncoder(os.Stdout).Encode(result)
}
