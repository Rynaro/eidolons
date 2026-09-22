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

func isRosterCommand(c string) bool {
	switch c {
	case "roster-enable", "roster-seed", "roster-route", "roster-control",
		"roster-compat", "roster-isolation", "roster-benefit", "roster-show":
		return true
	}
	return false
}

func rosterCommand(args []string) error {
	command := args[0]
	flags := flag.NewFlagSet(command, flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	project := flags.String("project", ".", "project/controller directory")
	timeout := flags.Duration("lock-timeout", 5*time.Second, "bounded local lock wait")
	input := flags.String("input", "", "strict JSON document path")
	profileID := flags.String("profile", "", "roster profile id")
	registryID := flags.String("registry", "registry-v4-18", "roster registry id")
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
	case "roster-enable", "roster-seed":
	case "roster-show":
		allowed["profile"] = true
		allowed["registry"] = true
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
	case "roster-enable":
		if e := s.EnsureRosterNamespaces(); e != nil {
			return e
		}
		result = map[string]any{
			"roster_namespaces":  true,
			"schema_version":     2,
			"typed_version":      contract.RosterSchemaVersion,
			"contract_version":   contract.RosterAdoptionContractID,
			"required_slices":    contract.RequiredAdoptionSlices,
			"scope":              "fixture-need-based-roster-adoption",
			"live_qualification": "blocked",
			"v4_22":              "out_of_scope",
			"v4_23":              "out_of_scope",
			"global_rename":      false,
			"refusal_weakened":   false,
		}
	case "roster-seed":
		reg, e := s.SeedAdoptionProfiles()
		if e != nil {
			return e
		}
		result = reg
	case "roster-route":
		raw, e := readInput(*input)
		if e != nil {
			return e
		}
		req, e := contract.DecodeRosterRouteRequest(raw)
		if e != nil {
			var loose contract.RosterRouteRequest
			if e2 := contract.StrictJSON(raw, &loose); e2 != nil {
				return e
			}
			req = loose
		}
		result, e = s.RouteAdoption(req)
		if e != nil {
			return e
		}
	case "roster-control":
		raw, e := readInput(*input)
		if e != nil {
			return e
		}
		c, e := contract.DecodeMethodologyControlRevision(raw)
		if e != nil {
			var loose contract.MethodologyControlRevision
			if e2 := contract.StrictJSON(raw, &loose); e2 != nil {
				return e
			}
			c = loose
		}
		result, e = s.ReviseMethodologyControl(c)
		if e != nil {
			return e
		}
	case "roster-compat":
		raw, e := readInput(*input)
		if e != nil {
			return e
		}
		c, e := contract.DecodeProfileCompatibilityCheck(raw)
		if e != nil {
			var loose contract.ProfileCompatibilityCheck
			if e2 := contract.StrictJSON(raw, &loose); e2 != nil {
				return e
			}
			c = loose
		}
		result, e = s.CheckProfileCompatibility(c)
		if e != nil {
			return e
		}
	case "roster-isolation":
		raw, e := readInput(*input)
		if e != nil {
			return e
		}
		c, e := contract.DecodeIsolationContractCheck(raw)
		if e != nil {
			var loose contract.IsolationContractCheck
			if e2 := contract.StrictJSON(raw, &loose); e2 != nil {
				return e
			}
			c = loose
		}
		result, e = s.CheckIsolationContract(c)
		if e != nil {
			return e
		}
	case "roster-benefit":
		raw, e := readInput(*input)
		if e != nil {
			return e
		}
		b, e := contract.DecodeBenefitEvidenceLabel(raw)
		if e != nil {
			var loose contract.BenefitEvidenceLabel
			if e2 := contract.StrictJSON(raw, &loose); e2 != nil {
				return e
			}
			b = loose
		}
		result, e = s.LabelBenefitEvidence(b)
		if e != nil {
			return e
		}
	case "roster-show":
		if *profileID != "" {
			out, e := s.GetRosterProfile(*profileID)
			if e != nil {
				return e
			}
			result = out
			break
		}
		out, e := s.GetRosterRegistry(*registryID)
		if e != nil {
			return e
		}
		result = out
	default:
		return errors.New("unsupported roster command")
	}
	return json.NewEncoder(os.Stdout).Encode(result)
}
