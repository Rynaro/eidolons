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

func isDeliveryCommand(c string) bool {
	switch c {
	case "delivery-enable", "delivery-run", "delivery-inspect", "delivery-status",
		"delivery-resume", "delivery-cancel", "delivery-compact":
		return true
	}
	return false
}

func deliveryCommand(args []string) error {
	command := args[0]
	flags := flag.NewFlagSet(command, flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	project := flags.String("project", ".", "project/controller directory")
	timeout := flags.Duration("lock-timeout", 5*time.Second, "bounded local lock wait")
	root := flags.String("root", "", "execution root")
	input := flags.String("input", "", "strict JSON document path")
	loopID := flags.String("loop", "", "delivery loop id")
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
	case "delivery-enable":
	case "delivery-run", "delivery-resume", "delivery-cancel", "delivery-compact":
		allowed["root"] = true
		allowed["input"] = true
	case "delivery-inspect":
		allowed["loop"] = true
	case "delivery-status":
		allowed["root"] = true
	}
	for name := range seen {
		if !allowed[name] {
			return errors.New("option is not applicable to this command: " + name)
		}
	}
	s := controller.New(*project, controller.Options{Timeout: *timeout})
	var result any
	switch command {
	case "delivery-enable":
		if e := s.EnsureDeliveryNamespaces(); e != nil {
			return e
		}
		result = map[string]any{
			"delivery_namespaces": true,
			"schema_version":      2,
			"typed_version":       contract.DeliverySchemaVersion,
			"scope":               "fixture-managed-delivery-demonstrator",
			"live_qualification":  "blocked",
			"model_calls":         0,
			"v4_20_full_cli":      "deferred",
			"v4_16_plus":          "out_of_scope",
		}
	case "delivery-run":
		if *root == "" || *input == "" {
			return errors.New("delivery-run requires --root and --input")
		}
		raw, e := os.ReadFile(*input)
		if e != nil {
			return e
		}
		req, e := contract.DecodeDeliveryRunRequest(raw)
		if e != nil {
			return e
		}
		req.RootID = *root
		loop, e := s.RunDeliveryLoop(req, nil, req.Fault)
		if e != nil {
			// Still emit partial loop state when fault-injected.
			result = map[string]any{"loop": loop, "error": e.Error()}
			_ = json.NewEncoder(os.Stdout).Encode(result)
			return e
		}
		result = loop
	case "delivery-inspect":
		if *loopID == "" {
			return errors.New("delivery-inspect requires --loop")
		}
		counters := &controller.ObservationalCounters{}
		snap, e := s.InspectDelivery(*loopID, counters)
		if e != nil {
			return e
		}
		result = snap
	case "delivery-status":
		loops, e := s.DeliveryStatus(*root)
		if e != nil {
			return e
		}
		result = map[string]any{"root": *root, "loops": loops, "model_calls": 0}
	case "delivery-resume":
		if *root == "" || *input == "" {
			return errors.New("delivery-resume requires --root and --input")
		}
		raw, e := os.ReadFile(*input)
		if e != nil {
			return e
		}
		req, e := contract.DecodeDeliveryResumeRequest(raw)
		if e != nil {
			return e
		}
		req.RootID = *root
		loop, e := s.ResumeDelivery(req)
		if e != nil {
			return e
		}
		result = loop
	case "delivery-cancel":
		if *root == "" || *input == "" {
			return errors.New("delivery-cancel requires --root and --input")
		}
		raw, e := os.ReadFile(*input)
		if e != nil {
			return e
		}
		req, e := contract.DecodeDeliveryCancelRequest(raw)
		if e != nil {
			return e
		}
		req.RootID = *root
		loop, e := s.CancelDelivery(req)
		if e != nil {
			return e
		}
		result = loop
	case "delivery-compact":
		if *root == "" || *input == "" {
			return errors.New("delivery-compact requires --root and --input")
		}
		raw, e := os.ReadFile(*input)
		if e != nil {
			return e
		}
		req, e := contract.DecodeContextCompactRequest(raw)
		if e != nil {
			return e
		}
		req.RootID = *root
		loop, obs, e := s.CompactDeliveryContext(req)
		if e != nil {
			return e
		}
		result = map[string]any{"loop": loop, "obligations": obs}
	}
	return json.NewEncoder(os.Stdout).Encode(result)
}
