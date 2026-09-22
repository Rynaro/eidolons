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

func isEvaluationCommand(c string) bool {
	switch c {
	case "evaluation-enable", "evaluation-trial", "evaluation-arm", "evaluation-cost",
		"evaluation-holdout", "evaluation-plumbing", "evaluation-report", "evaluation-admit",
		"evaluation-drift", "evaluation-outcome", "evaluation-promotion", "evaluation-show":
		return true
	}
	return false
}

func evaluationCommand(args []string) error {
	command := args[0]
	flags := flag.NewFlagSet(command, flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	project := flags.String("project", ".", "project/controller directory")
	timeout := flags.Duration("lock-timeout", 5*time.Second, "bounded local lock wait")
	input := flags.String("input", "", "strict JSON document path")
	protocol := flags.String("protocol", "", "frozen protocol id")
	trial := flags.String("trial", "", "evaluation trial id")
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
	case "evaluation-enable":
	case "evaluation-cost":
		allowed["protocol"] = true
	case "evaluation-show":
		allowed["trial"] = true
	default:
		allowed["input"] = true
	}
	for name := range seen {
		if !allowed[name] {
			return errors.New("option is not applicable to this command: " + name)
		}
	}
	s := controller.New(*project, controller.Options{Timeout: *timeout})
	var result any
	switch command {
	case "evaluation-enable":
		if e := s.EnsureEvaluationNamespaces(); e != nil {
			return e
		}
		result = map[string]any{
			"evaluation_namespaces": true,
			"schema_version":        2,
			"typed_version":         contract.EvaluationSchemaVersion,
			"scope":                 "fixture-auditable-evaluation",
			"live_qualification":    "blocked",
			"extends":               "V4-09-instrument",
			"v4_22":                 "out_of_scope",
			"v4_10":                 "out_of_scope",
		}
	case "evaluation-trial":
		raw, e := readInput(*input)
		if e != nil {
			return e
		}
		t, e := contract.DecodeEvaluationTrial(raw)
		if e != nil {
			return e
		}
		result, e = s.StartEvaluationTrial(t)
		if e != nil {
			return e
		}
	case "evaluation-arm":
		raw, e := readInput(*input)
		if e != nil {
			return e
		}
		a, e := contract.DecodeEvalArmIdentity(raw)
		if e != nil {
			return e
		}
		pkgs := map[string]bool{contract.PackageV415: true}
		result, e = s.RecordEvalArmIdentity(a, pkgs, nil)
		if e != nil {
			return e
		}
	case "evaluation-cost":
		if *protocol == "" {
			return errors.New("evaluation-cost requires --protocol")
		}
		sum, e := s.ComputeEvalCost(*protocol)
		if e != nil {
			return e
		}
		result = sum
	case "evaluation-holdout":
		raw, e := readInput(*input)
		if e != nil {
			return e
		}
		h, e := contract.DecodeHoldoutBoundary(raw)
		if e != nil {
			return e
		}
		result, e = s.RecordHoldoutBoundary(h)
		if e != nil {
			return e
		}
	case "evaluation-plumbing":
		raw, e := readInput(*input)
		if e != nil {
			return e
		}
		p, e := contract.DecodePlumbingEvidence(raw)
		if e != nil {
			return e
		}
		result, e = s.ClassifyPlumbingEvidence(p)
		if e != nil {
			return e
		}
	case "evaluation-report":
		raw, e := readInput(*input)
		if e != nil {
			return e
		}
		m, e := contract.DecodeEvalReportMetrics(raw)
		if e != nil {
			return e
		}
		result, e = s.PublishEvalReport(m)
		if e != nil {
			return e
		}
	case "evaluation-admit":
		raw, e := readInput(*input)
		if e != nil {
			return e
		}
		t, e := contract.DecodeTaskAdmission(raw)
		if e != nil {
			return e
		}
		result, e = s.AdmitEvaluationTask(t)
		if e != nil {
			return e
		}
	case "evaluation-drift":
		raw, e := readInput(*input)
		if e != nil {
			return e
		}
		var d contract.EnvironmentDrift
		if e := contract.StrictJSON(raw, &d); e != nil {
			return e
		}
		result, e = s.FlagEnvironmentDrift(d)
		if e != nil {
			return e
		}
	case "evaluation-outcome":
		raw, e := readInput(*input)
		if e != nil {
			return e
		}
		o, e := contract.DecodeOutcomeDistinction(raw)
		if e != nil {
			return e
		}
		result, e = s.DistinguishOutcomes(o)
		if e != nil {
			return e
		}
	case "evaluation-promotion":
		raw, e := readInput(*input)
		if e != nil {
			return e
		}
		p, e := contract.DecodePromotionSet(raw)
		if e != nil {
			return e
		}
		result, e = s.UpdatePromotionSet(p)
		if e != nil {
			return e
		}
	case "evaluation-show":
		if *trial == "" {
			return errors.New("evaluation-show requires --trial")
		}
		report, e := s.EvaluationReport(*trial)
		if e != nil {
			return e
		}
		result = report
	}
	return json.NewEncoder(os.Stdout).Encode(result)
}

func readInput(path string) ([]byte, error) {
	if path == "" {
		return nil, errors.New("--input is required")
	}
	return os.ReadFile(path)
}
