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

func isReleaseCommand(c string) bool {
	switch c {
	case "release-enable", "release-candidate", "release-authorize", "release-retire",
		"release-hostcap", "release-hostcap-invalidate", "release-readiness", "release-rollback":
		return true
	}
	return false
}

func releaseCommand(args []string) error {
	command := args[0]
	flags := flag.NewFlagSet(command, flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	project := flags.String("project", ".", "project/controller directory")
	timeout := flags.Duration("lock-timeout", 5*time.Second, "bounded local lock wait")
	input := flags.String("input", "", "strict JSON document path")
	id := flags.String("id", "", "host capability qualification id")
	version := flags.String("version", "", "observed host version")
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
	case "release-enable":
	case "release-hostcap-invalidate":
		allowed["id"] = true
		allowed["version"] = true
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
	case "release-enable":
		if e := s.EnsureReleaseNamespaces(); e != nil {
			return e
		}
		result = map[string]any{
			"release_namespaces": true,
			"schema_version":     2,
			"typed_version":      contract.ReleaseSchemaVersion,
			"scope":              "fixture-migration-release-gates",
			"live_qualification": "blocked",
			"publication":        "blocked",
			"tag_merge_release":  "not_authorized_by_this_package",
			"extends":            []string{"V4-07-migration", "V4-20-status", "V4-21-evidence", "V4-22-calibration"},
		}
	case "release-candidate":
		raw, e := os.ReadFile(*input)
		if e != nil {
			return e
		}
		c, e := contract.DecodeReleaseCandidate(raw)
		if e != nil {
			return e
		}
		result, e = s.EvaluateReleaseCandidate(c)
		if e != nil {
			return e
		}
	case "release-authorize":
		raw, e := os.ReadFile(*input)
		if e != nil {
			return e
		}
		p, e := contract.DecodePromotionAuthorization(raw)
		if e != nil {
			return e
		}
		result, e = s.AuthorizePromotion(p)
		if e != nil {
			return e
		}
	case "release-retire":
		raw, e := os.ReadFile(*input)
		if e != nil {
			return e
		}
		r, e := contract.DecodeRetirementRequest(raw)
		if e != nil {
			return e
		}
		result, e = s.EvaluateRetirement(r)
		if e != nil {
			return e
		}
	case "release-hostcap":
		raw, e := os.ReadFile(*input)
		if e != nil {
			return e
		}
		h, e := contract.DecodeHostCapabilityQualification(raw)
		if e != nil {
			return e
		}
		result, e = s.RegisterHostCapabilityQualification(h)
		if e != nil {
			return e
		}
	case "release-hostcap-invalidate":
		if *id == "" || *version == "" {
			return errors.New("--id and --version required")
		}
		var e error
		result, e = s.InvalidateHostCapabilityOnVersionChange(*id, *version)
		if e != nil {
			return e
		}
	case "release-readiness":
		raw, e := os.ReadFile(*input)
		if e != nil {
			return e
		}
		r, e := contract.DecodeReleaseReadinessReport(raw)
		if e != nil {
			return e
		}
		result, e = s.ReportReleaseReadiness(r)
		if e != nil {
			return e
		}
	case "release-rollback":
		raw, e := os.ReadFile(*input)
		if e != nil {
			return e
		}
		r, e := contract.DecodeStrategyMethodRollback(raw)
		if e != nil {
			return e
		}
		result, e = s.RollbackStrategyMethod(r)
		if e != nil {
			return e
		}
	default:
		return errors.New("unsupported release command")
	}
	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	return enc.Encode(result)
}
