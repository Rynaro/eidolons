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

func isStatusCommand(c string) bool {
	switch c {
	case "status-enable", "status-project", "status-policy-inspect", "status-policy-preview",
		"status-client-conformance":
		return true
	}
	return false
}

func statusCommand(args []string) error {
	command := args[0]
	flags := flag.NewFlagSet(command, flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	project := flags.String("project", ".", "project/controller directory")
	timeout := flags.Duration("lock-timeout", 5*time.Second, "bounded local lock wait")
	root := flags.String("root", "", "execution root")
	loopID := flags.String("loop", "", "delivery loop id")
	policyID := flags.String("policy-id", "", "immutable typed policy identity")
	input := flags.String("input", "", "strict JSON document path")
	checksPassed := flags.Bool("checks-passed", false, "observed checks-passed verification evidence")
	reviewPending := flags.Bool("review-pending", false, "observed review-pending verification evidence")
	released := flags.Bool("released", false, "observed released verification evidence")
	escalation := flags.String("escalation", "", "escalation attempt to deny without model work")
	quotaKind := flags.String("quota-kind", "", "quota limitation kind for plain-text disclosure")
	quotaText := flags.String("quota-text", "", "plain-text quota/enforcement limitation")
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
	case "status-enable":
	case "status-project":
		allowed["root"], allowed["loop"] = true, true
		allowed["checks-passed"], allowed["review-pending"], allowed["released"] = true, true, true
		allowed["escalation"], allowed["quota-kind"], allowed["quota-text"], allowed["input"] = true, true, true, true
	case "status-policy-inspect":
		allowed["root"], allowed["policy-id"], allowed["escalation"] = true, true, true
	case "status-policy-preview":
		allowed["root"] = true
	case "status-client-conformance":
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
	case "status-enable":
		if e := s.EnsureStatusNamespaces(); e != nil {
			return e
		}
		result = map[string]any{
			"status_namespaces":  true,
			"schema_version":     2,
			"typed_version":      contract.StatusSchemaVersion,
			"contract_version":   contract.StatusContractID,
			"slice":              "core-cli",
			"optional_gambit":    "explicitly_deferred",
			"model_calls":        0,
			"scope":              "observational-status-projection",
			"live_qualification": "blocked",
		}
	case "status-project":
		opts := controller.StatusProjectOptions{
			LoopID:            *loopID,
			RootID:            *root,
			ChecksPassed:      *checksPassed,
			ReviewPending:     *reviewPending,
			Released:          *released,
			AttemptEscalation: *escalation,
			Counters:          &controller.ObservationalCounters{},
		}
		if *quotaKind != "" {
			if *quotaText == "" {
				return errors.New("quota-kind requires --quota-text plain limitation")
			}
			opts.Quota = &contract.QuotaLimitation{
				Kind:              *quotaKind,
				PlainText:         *quotaText,
				PercentageKnown:   false,
				AdvisoryOnly:      *quotaKind == contract.QuotaAdvisoryOnly,
				OutsideController: *quotaKind == contract.QuotaOutsideController,
			}
		}
		if *input != "" {
			raw, e := os.ReadFile(*input)
			if e != nil {
				return e
			}
			var payload struct {
				Assignments []contract.Assignment     `json:"assignments"`
				Cancel      *contract.CancelState     `json:"cancel"`
				Quota       *contract.QuotaLimitation `json:"quota_limitation"`
			}
			if e := contract.StrictJSON(raw, &payload); e != nil {
				return e
			}
			opts.Assignments = payload.Assignments
			opts.CancelState = payload.Cancel
			if payload.Quota != nil {
				opts.Quota = payload.Quota
			}
		}
		proj, e := s.ProjectStatus(opts)
		if e != nil {
			return e
		}
		result = proj
	case "status-policy-inspect":
		counters := &controller.ObservationalCounters{}
		out, e := s.InspectPolicyObservational(*root, *policyID, *escalation, counters)
		if e != nil {
			return e
		}
		result = out
	case "status-policy-preview":
		if *root == "" {
			return errors.New("status-policy-preview requires --root")
		}
		counters := &controller.ObservationalCounters{}
		out, e := s.PreviewPolicyChange(*root, counters)
		if e != nil {
			return e
		}
		result = out
	case "status-client-conformance":
		if *input == "" {
			return errors.New("status-client-conformance requires --input")
		}
		raw, e := os.ReadFile(*input)
		if e != nil {
			return e
		}
		var envelope struct {
			Request    contract.ClientConformanceRequest `json:"request"`
			Projection json.RawMessage                   `json:"projection"`
		}
		if e := contract.StrictJSON(raw, &envelope); e != nil {
			return e
		}
		counters := &controller.ObservationalCounters{}
		out, e := s.ConsumeStatusContract(envelope.Request, envelope.Projection, counters)
		if e != nil {
			return e
		}
		result = out
	}
	return json.NewEncoder(os.Stdout).Encode(result)
}
