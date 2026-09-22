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

func isCalibrationCommand(c string) bool {
	switch c {
	case "calibration-enable", "calibration-trial", "calibration-baseline", "calibration-arm",
		"calibration-batch", "calibration-cost", "calibration-promote", "calibration-stop",
		"calibration-decide", "calibration-adapt", "calibration-generalize",
		"calibration-strategy", "calibration-revalidate", "calibration-offline":
		return true
	}
	return false
}

func calibrationCommand(args []string) error {
	command := args[0]
	flags := flag.NewFlagSet(command, flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	project := flags.String("project", ".", "project/controller directory")
	timeout := flags.Duration("lock-timeout", 5*time.Second, "bounded local lock wait")
	input := flags.String("input", "", "strict JSON document path")
	strategy := flags.String("strategy", "", "promoted strategy id")
	model := flags.String("model", "", "observed model for revalidation")
	harness := flags.String("harness", "", "observed harness for revalidation")
	taskScope := flags.String("task-scope", "", "observed task scope for revalidation")
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
	case "calibration-enable":
	case "calibration-revalidate":
		allowed["strategy"] = true
		allowed["model"] = true
		allowed["harness"] = true
		allowed["task-scope"] = true
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
	case "calibration-enable":
		if e := s.EnsureCalibrationNamespaces(); e != nil {
			return e
		}
		result = map[string]any{
			"calibration_namespaces": true,
			"schema_version":         2,
			"typed_version":          contract.CalibrationSchemaVersion,
			"scope":                  "fixture-strategy-calibration",
			"live_qualification":     "blocked",
			"extends":                "V4-21-evaluation",
			"slices":                 []string{"workflow-ablations", "routing-calibration", "optional-offline-adaptation"},
			"v4_18":                  "out_of_scope",
			"v4_23":                  "out_of_scope",
		}
	case "calibration-trial":
		raw, e := readInput(*input)
		if e != nil {
			return e
		}
		t, e := contract.DecodeCalibrationTrial(raw)
		if e != nil {
			return e
		}
		result, e = s.StartCalibrationTrial(t)
		if e != nil {
			return e
		}
	case "calibration-baseline":
		raw, e := readInput(*input)
		if e != nil {
			return e
		}
		b, e := contract.DecodeCalibrationBaseline(raw)
		if e != nil {
			return e
		}
		result, e = s.RecordCalibrationBaseline(b)
		if e != nil {
			return e
		}
	case "calibration-arm":
		raw, e := readInput(*input)
		if e != nil {
			return e
		}
		var a contract.CalibrationArm
		if e := contract.StrictJSON(raw, &a); e != nil {
			return e
		}
		pkgs := map[string]bool{
			contract.PackageV416: true, contract.PackageV417: true,
			contract.PackageV419: true,
		}
		result, e = s.RecordCalibrationArm(a, pkgs, nil)
		if e != nil {
			return e
		}
	case "calibration-batch":
		raw, e := readInput(*input)
		if e != nil {
			return e
		}
		var b contract.CalibrationBatch
		if e := contract.StrictJSON(raw, &b); e != nil {
			return e
		}
		result, e = s.RecordCalibrationBatch(b)
		if e != nil {
			return e
		}
	case "calibration-cost":
		raw, e := readInput(*input)
		if e != nil {
			return e
		}
		var r contract.MechanismCostReport
		if e := contract.StrictJSON(raw, &r); e != nil {
			return e
		}
		result, e = s.PublishMechanismCostReport(r)
		if e != nil {
			return e
		}
	case "calibration-promote":
		raw, e := readInput(*input)
		if e != nil {
			return e
		}
		var d contract.PromotionDecision
		if e := contract.StrictJSON(raw, &d); e != nil {
			return e
		}
		result, e = s.DecidePromotion(d)
		if e != nil {
			return e
		}
	case "calibration-stop":
		raw, e := readInput(*input)
		if e != nil {
			return e
		}
		var t contract.TrialBoundaryStop
		if e := contract.StrictJSON(raw, &t); e != nil {
			return e
		}
		result, e = s.StopAtTrialBoundary(t)
		if e != nil {
			return e
		}
	case "calibration-decide":
		raw, e := readInput(*input)
		if e != nil {
			return e
		}
		var d contract.StrategyDecision
		if e := contract.StrictJSON(raw, &d); e != nil {
			return e
		}
		result, e = s.RecordStrategyDecision(d)
		if e != nil {
			return e
		}
	case "calibration-adapt":
		raw, e := readInput(*input)
		if e != nil {
			return e
		}
		var a contract.AdaptationRecord
		if e := contract.StrictJSON(raw, &a); e != nil {
			return e
		}
		result, e = s.RecordAdaptationProposal(a)
		if e != nil {
			return e
		}
	case "calibration-generalize":
		raw, e := readInput(*input)
		if e != nil {
			return e
		}
		var g contract.GeneralizationReport
		if e := contract.StrictJSON(raw, &g); e != nil {
			return e
		}
		result, e = s.ReportGeneralization(g)
		if e != nil {
			return e
		}
	case "calibration-strategy":
		raw, e := readInput(*input)
		if e != nil {
			return e
		}
		p, e := contract.DecodePromotedStrategyRegistry(raw)
		if e != nil {
			return e
		}
		result, e = s.RegisterPromotedStrategy(p)
		if e != nil {
			return e
		}
	case "calibration-revalidate":
		if *strategy == "" {
			return errors.New("calibration-revalidate requires --strategy")
		}
		out, e := s.RevalidatePromotedStrategy(*strategy, *model, *harness, *taskScope)
		if e != nil {
			return e
		}
		result = out
	case "calibration-offline":
		raw, e := readInput(*input)
		if e != nil {
			return e
		}
		var o contract.OfflineAdaptationBoundary
		if e := contract.StrictJSON(raw, &o); e != nil {
			return e
		}
		result, e = s.RecordOfflineAdaptationBoundary(o)
		if e != nil {
			return e
		}
	}
	return json.NewEncoder(os.Stdout).Encode(result)
}
