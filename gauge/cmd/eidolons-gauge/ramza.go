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

func isRamzaCommand(c string) bool {
	switch c {
	case "ramza-enable", "ramza-plan-lite", "ramza-mark-ready", "ramza-consume",
		"ramza-rubric", "ramza-profile", "ramza-heuristic", "ramza-assumption", "ramza-show":
		return true
	}
	return false
}

func ramzaCommand(args []string) error {
	command := args[0]
	flags := flag.NewFlagSet(command, flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	project := flags.String("project", ".", "project/controller directory")
	timeout := flags.Duration("lock-timeout", 5*time.Second, "bounded local lock wait")
	input := flags.String("input", "", "strict JSON document path")
	planID := flags.String("plan", "", "ramza lite plan id")
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
	case "ramza-enable":
	case "ramza-mark-ready", "ramza-show":
		allowed["plan"] = true
	case "ramza-rubric", "ramza-assumption":
		allowed["input"], allowed["plan"] = true, true
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
	case "ramza-enable":
		if e := s.EnsureRamzaNamespaces(); e != nil {
			return e
		}
		result = map[string]any{
			"ramza_namespaces":             true,
			"schema_version":               2,
			"typed_version":                contract.RamzaSchemaVersion,
			"contract_version":             contract.RamzaMethodContractID,
			"lite_method":                  contract.RamzaMethodLiteV2,
			"source_owner":                 contract.RamzaCanonicalSourceOwner,
			"canonical_sibling_preserved":  true,
			"scope":                        "fixture-versioned-ramza-methods",
			"live_qualification":           "blocked",
			"v4_17":                        "out_of_scope",
			"v4_10":                        "out_of_scope",
			"fabricated_certainty":         false,
			"default_flip":                 false,
		}
	case "ramza-plan-lite":
		raw, e := readInput(*input)
		if e != nil {
			return e
		}
		var p contract.RamzaLitePlan
		if e := contract.StrictJSON(raw, &p); e != nil {
			return e
		}
		result, e = s.PlanLite(p)
		if e != nil {
			return e
		}
	case "ramza-mark-ready":
		if *planID == "" {
			return errors.New("--plan required")
		}
		out, e := s.MarkPlanReady(*planID)
		if e != nil {
			return e
		}
		result = out
	case "ramza-consume":
		raw, e := readInput(*input)
		if e != nil {
			return e
		}
		req, e := contract.DecodeConsumeDecisionRequest(raw)
		if e != nil {
			return e
		}
		result, e = s.ConsumeSettledDecision(req)
		if e != nil {
			return e
		}
	case "ramza-rubric":
		raw, e := readInput(*input)
		if e != nil {
			return e
		}
		var score contract.RubricScore
		if e := contract.StrictJSON(raw, &score); e != nil {
			return e
		}
		result, e = s.PresentRubricScore(*planID, score)
		if e != nil {
			return e
		}
	case "ramza-profile":
		raw, e := readInput(*input)
		if e != nil {
			return e
		}
		p, e := contract.DecodeProfilePackage(raw)
		if e != nil {
			var loose contract.ProfilePackage
			if e2 := contract.StrictJSON(raw, &loose); e2 != nil {
				return e
			}
			p = loose
		}
		result, e = s.SelectProfilePackage(p)
		if e != nil {
			return e
		}
	case "ramza-heuristic":
		raw, e := readInput(*input)
		if e != nil {
			return e
		}
		h, e := contract.DecodeHeuristicPublication(raw)
		if e != nil {
			var loose contract.HeuristicPublication
			if e2 := contract.StrictJSON(raw, &loose); e2 != nil {
				return e
			}
			h = loose
		}
		result, e = s.PublishHeuristic(h)
		if e != nil {
			return e
		}
	case "ramza-assumption":
		raw, e := readInput(*input)
		if e != nil {
			return e
		}
		a, e := contract.DecodePlanningAssumption(raw)
		if e != nil {
			var loose contract.PlanningAssumption
			if e2 := contract.StrictJSON(raw, &loose); e2 != nil {
				return e
			}
			a = loose
		}
		result, e = s.RecordAssumption(*planID, a)
		if e != nil {
			return e
		}
	case "ramza-show":
		if *planID == "" {
			return errors.New("--plan required")
		}
		out, e := s.ShowRamzaPlan(*planID)
		if e != nil {
			return e
		}
		result = out
	default:
		return errors.New("unsupported ramza command")
	}
	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	return enc.Encode(result)
}
