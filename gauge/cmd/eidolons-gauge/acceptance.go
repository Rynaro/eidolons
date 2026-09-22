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

func isAcceptanceCommand(c string) bool {
	switch c {
	case "acceptance-enable", "acceptance-register", "candidate-freeze", "acceptance-check",
		"qualify", "apply", "acceptance-report", "acceptance-status",
		"owner-review", "definition-assess":
		return true
	}
	return false
}

func acceptanceCommand(args []string) error {
	command := args[0]
	flags := flag.NewFlagSet(command, flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	project := flags.String("project", ".", "project/controller directory")
	timeout := flags.Duration("lock-timeout", 5*time.Second, "bounded local lock wait")
	root := flags.String("root", "", "execution root")
	input := flags.String("input", "", "strict JSON document path")
	candidate := flags.String("candidate", "", "frozen candidate id")
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
	case "acceptance-enable":
	case "acceptance-register", "candidate-freeze", "acceptance-check", "qualify", "apply",
		"owner-review", "definition-assess":
		allowed["root"] = true
		allowed["input"] = true
	case "acceptance-report":
		allowed["root"] = true
		allowed["candidate"] = true
	case "acceptance-status":
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
	case "acceptance-enable":
		if e := s.EnsureAcceptanceNamespaces(); e != nil {
			return e
		}
		result = map[string]any{
			"acceptance_namespaces": true,
			"schema_version":        2,
			"typed_version":         contract.AcceptanceSchemaVersion,
			"scope":                 "fixture-protected-acceptance",
			"live_qualification":    "blocked",
			"universal_correctness": "not_claimed",
			"auto_push_merge_release": false,
		}
	case "acceptance-register":
		if *root == "" || *input == "" {
			return errors.New("acceptance-register requires --root and --input")
		}
		raw, e := os.ReadFile(*input)
		if e != nil {
			return e
		}
		pkg, e := contract.DecodeAcceptancePackage(raw)
		if e != nil {
			return e
		}
		if e := s.RegisterAcceptancePackage(pkg); e != nil {
			return e
		}
		result = map[string]any{"registered": true, "acceptance_id": pkg.ID, "root": *root}
	case "candidate-freeze":
		if *root == "" || *input == "" {
			return errors.New("candidate-freeze requires --root and --input")
		}
		raw, e := os.ReadFile(*input)
		if e != nil {
			return e
		}
		req, e := contract.DecodeFreezeRequest(raw)
		if e != nil {
			return e
		}
		out, e := s.FreezeCandidate(*root, req)
		if e != nil {
			return e
		}
		result = out
	case "acceptance-check":
		if *root == "" || *input == "" {
			return errors.New("acceptance-check requires --root and --input")
		}
		raw, e := os.ReadFile(*input)
		if e != nil {
			return e
		}
		req, e := contract.DecodeRunCheckRequest(raw)
		if e != nil {
			return e
		}
		cap := contract.IsolationCapability{
			Mode: req.IsolationMode,
			Enforced: req.IsolationMode == contract.IsolationEnforced,
			ContextProvenance: "present",
		}
		receipt, grade, e := s.FinishCheck(*root, req, cap)
		if e != nil {
			return e
		}
		result = map[string]any{"receipt": receipt, "grade": grade}
	case "qualify":
		if *root == "" || *input == "" {
			return errors.New("qualify requires --root and --input")
		}
		raw, e := os.ReadFile(*input)
		if e != nil {
			return e
		}
		req, e := contract.DecodeQualifyRequest(raw)
		if e != nil {
			return e
		}
		out, e := s.QualifyOracle(*root, req)
		if e != nil {
			return e
		}
		result = out
	case "apply":
		if *root == "" || *input == "" {
			return errors.New("apply requires --root and --input")
		}
		raw, e := os.ReadFile(*input)
		if e != nil {
			return e
		}
		req, e := contract.DecodeApplyRequest(raw)
		if e != nil {
			return e
		}
		out, e := s.ApplyCandidate(*root, req)
		if e != nil {
			return e
		}
		result = out
	case "acceptance-report":
		if *root == "" || *candidate == "" {
			return errors.New("acceptance-report requires --root and --candidate")
		}
		frozen, e := s.GetFrozen(*candidate)
		if e != nil {
			return e
		}
		proj := contract.Project(contract.ProjectionInput{
			Candidate: contract.Candidate{
				Identity: map[string]string{"id": frozen.ID, "digest": frozen.ContentDigest},
			},
			CurrentIdentity: map[string]string{"id": frozen.ID, "digest": frozen.ContentDigest},
		})
		result = controller.ProjectHumanReport(frozen, nil, proj)
	case "acceptance-status":
		if *root == "" {
			return errors.New("acceptance-status requires --root")
		}
		cands, e := s.AcceptanceStatus(*root)
		if e != nil {
			return e
		}
		result = map[string]any{"frozen_candidates": cands}
	case "owner-review":
		if *root == "" || *input == "" {
			return errors.New("owner-review requires --root and --input")
		}
		raw, e := os.ReadFile(*input)
		if e != nil {
			return e
		}
		rev, e := contract.DecodeOwnerReview(raw)
		if e != nil {
			return e
		}
		out, e := s.ReviewOwnerChange(*root, rev)
		if e != nil {
			return e
		}
		result = out
	case "definition-assess":
		if *root == "" || *input == "" {
			return errors.New("definition-assess requires --root and --input")
		}
		raw, e := os.ReadFile(*input)
		if e != nil {
			return e
		}
		pkg, e := contract.DecodeAcceptancePackage(raw)
		if e != nil {
			return e
		}
		blocker, e := s.AssessDefinition(*root, pkg, "blocker-"+pkg.ID)
		if e != nil {
			return e
		}
		if blocker == nil {
			result = map[string]any{"blocker": nil, "clear": true}
		} else {
			result = map[string]any{"blocker": blocker, "clear": false}
		}
	}
	return json.NewEncoder(os.Stdout).Encode(result)
}
