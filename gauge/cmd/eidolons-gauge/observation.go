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

func isObservationCommand(c string) bool {
	switch c {
	case "task-start", "task-resume", "lineage-bind", "usage-record", "usage-correct", "usage-summary", "usage-export", "usage-retain", "observation-enable":
		return true
	}
	return false
}

func observationCommand(args []string) error {
	command := args[0]
	flags := flag.NewFlagSet(command, flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	project := flags.String("project", ".", "project/controller directory")
	timeout := flags.Duration("lock-timeout", 5*time.Second, "bounded local lock wait")
	root := flags.String("root", "", "execution root")
	route := flags.String("route-digest", "", "route digest distinct from execution root")
	input := flags.String("input", "", "strict JSON document path")
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
	case "task-start":
		allowed["route-digest"] = true
	case "task-resume", "usage-export", "usage-retain":
		allowed["root"] = true
	case "lineage-bind", "usage-record", "usage-correct", "usage-summary":
		allowed["root"], allowed["input"] = true, true
	case "observation-enable":
	}
	for name := range seen {
		if !allowed[name] {
			return errors.New("option is not applicable to this command: " + name)
		}
	}
	s := controller.New(*project, controller.Options{Timeout: *timeout})
	var result any
	switch command {
	case "observation-enable":
		db, e := s.ReadPreferences()
		if e != nil {
			return e
		}
		_ = db
		// Ensure via a throwaway open path: StartTask-less ensure through Export on missing root is wrong.
		// Use Init check then preferences store ensure by calling a no-op Ensure through resume of nothing.
		svc := s
		if e := ensureObservation(svc); e != nil {
			return e
		}
		result = map[string]any{"observation_namespaces": true, "schema_version": 2, "typed_version": contract.ObservationSchemaVersion}
	case "task-start":
		if *route == "" {
			return errors.New("--route-digest is required")
		}
		v, e := s.StartTask(*route)
		if e != nil {
			return e
		}
		result = v
	case "task-resume":
		if *root == "" {
			return errors.New("--root is required")
		}
		if e := s.ResumeRoot(*root); e != nil {
			return e
		}
		result = map[string]any{"root": *root, "resumed": true}
	case "lineage-bind":
		if *root == "" || *input == "" {
			return errors.New("lineage-bind requires --root and --input")
		}
		raw, e := os.ReadFile(*input)
		if e != nil {
			return e
		}
		edge, e := contract.DecodeLineageEdge(raw)
		if e != nil {
			return errors.New("lineage validation failed")
		}
		if e = s.BindLineage(*root, edge); e != nil {
			return e
		}
		result = edge
	case "usage-record":
		if *root == "" || *input == "" {
			return errors.New("usage-record requires --root and --input")
		}
		raw, e := os.ReadFile(*input)
		if e != nil {
			return e
		}
		o, e := contract.DecodeUsageObservation(raw)
		if e != nil {
			return errors.New("observation validation failed")
		}
		if e = s.RecordUsage(*root, o); e != nil {
			return e
		}
		result = map[string]any{"root": *root, "observation_id": o.ID, "recorded": true}
	case "usage-correct":
		if *root == "" || *input == "" {
			return errors.New("usage-correct requires --root and --input")
		}
		raw, e := os.ReadFile(*input)
		if e != nil {
			return e
		}
		c, e := contract.DecodeUsageCorrection(raw)
		if e != nil {
			return errors.New("correction validation failed")
		}
		if e = s.CorrectUsage(*root, c); e != nil {
			return e
		}
		result = map[string]any{"root": *root, "correction_id": c.ID, "recorded": true}
	case "usage-summary":
		if *root == "" || *input == "" {
			return errors.New("usage-summary requires --root and --input stream JSON")
		}
		raw, e := os.ReadFile(*input)
		if e != nil {
			return e
		}
		var stream contract.StreamIdentity
		if e = contract.StrictJSON(raw, &stream); e != nil {
			return e
		}
		v, e := s.SummarizeUsage(*root, stream)
		if e != nil {
			return e
		}
		result = v
	case "usage-export":
		if *root == "" {
			return errors.New("--root is required")
		}
		v, e := s.ExportUsage(*root)
		if e != nil {
			return e
		}
		result = v
	case "usage-retain":
		if *root == "" {
			return errors.New("--root is required")
		}
		if e := s.RetainUsage(*root); e != nil {
			return e
		}
		result = map[string]any{"root": *root, "retained": true, "detail_removed": true}
	}
	return json.NewEncoder(os.Stdout).Encode(result)
}

func ensureObservation(s *controller.Service) error {
	// Touch preferences to prove store exists, then ensure namespaces via export path helpers.
	if _, e := s.ReadPreferences(); e != nil {
		return e
	}
	return s.EnsureObservationNamespaces()
}
