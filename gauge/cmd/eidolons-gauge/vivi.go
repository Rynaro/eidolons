package main

import (
	"encoding/json"
	"errors"
	"flag"
	"os"
	"strconv"
	"time"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
	"github.com/Rynaro/eidolons/gauge/internal/controller"
)

func isViviCommand(c string) bool {
	switch c {
	case "vivi-enable", "vivi-session", "vivi-mode", "vivi-edit", "vivi-propose",
		"vivi-apply", "vivi-continuity", "vivi-repair", "vivi-reset",
		"vivi-verify", "vivi-boundary", "vivi-context":
		return true
	}
	return false
}

func viviCommand(args []string) error {
	command := args[0]
	flags := flag.NewFlagSet(command, flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	project := flags.String("project", ".", "project/controller directory")
	timeout := flags.Duration("lock-timeout", 5*time.Second, "bounded local lock wait")
	input := flags.String("input", "", "strict JSON document path")
	session := flags.String("session", "", "vivi session id")
	mode := flags.String("mode", "", "vivi mode id")
	proposal := flags.String("proposal", "", "vivi proposal id")
	continuity := flags.String("continuity", "", "vivi continuity id")
	target := flags.String("target", "", "edit target path")
	content := flags.String("content", "", "edit content")
	diff := flags.String("diff", "", "proposal diff text")
	applyPath := flags.String("apply-path", "", "user-tree apply path")
	parentAuth := flags.Bool("parent-authorized", false, "parent-authorized proposal application")
	dirty := flags.Bool("dirty-unrelated", false, "mark unrelated dirty work")
	decision := flags.String("decision", "", "continuity decision")
	failure := flags.String("failure", "", "continuity failure")
	reason := flags.String("reason", "", "context reset reason")
	task := flags.String("task", "", "task description for boundary check")
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
	case "vivi-enable":
	case "vivi-session", "vivi-mode", "vivi-continuity", "vivi-verify", "vivi-context":
		allowed["input"] = true
	case "vivi-edit":
		allowed["session"], allowed["mode"], allowed["target"], allowed["content"], allowed["dirty-unrelated"] = true, true, true, true, true
	case "vivi-propose":
		allowed["session"], allowed["mode"], allowed["diff"] = true, true, true
	case "vivi-apply":
		allowed["session"], allowed["proposal"], allowed["parent-authorized"], allowed["apply-path"] = true, true, true, true
	case "vivi-repair":
		allowed["continuity"], allowed["decision"], allowed["failure"] = true, true, true
	case "vivi-reset":
		allowed["continuity"], allowed["reason"] = true, true
	case "vivi-boundary":
		allowed["session"], allowed["task"], allowed["input"] = true, true, true
	}
	for name := range seen {
		if !allowed[name] {
			return errors.New("option is not applicable to this command: " + name)
		}
	}
	s := controller.New(*project, controller.Options{Timeout: *timeout})
	var result any
	switch command {
	case "vivi-enable":
		if e := s.EnsureViviNamespaces(); e != nil {
			return e
		}
		result = map[string]any{
			"vivi_namespaces":       true,
			"schema_version":        2,
			"typed_version":         contract.ViviSchemaVersion,
			"contract_version":      contract.ViviModesContractID,
			"scope":                 "fixture-vivi-candidate-context-modes",
			"publication_authority": false,
			"live_qualification":    "blocked",
			"v4_16":                 "out_of_scope",
			"v4_18":                 "out_of_scope",
			"v4_10":                 "out_of_scope",
		}
	case "vivi-session":
		raw, e := readInput(*input)
		if e != nil {
			return e
		}
		sess, e := contract.DecodeViviSession(raw)
		if e != nil {
			return e
		}
		result, e = s.StartViviSession(sess)
		if e != nil {
			return e
		}
	case "vivi-mode":
		raw, e := readInput(*input)
		if e != nil {
			return e
		}
		m, e := contract.DecodeViviModeSelection(raw)
		if e != nil {
			return e
		}
		result, e = s.SelectViviMode(m)
		if e != nil {
			return e
		}
	case "vivi-edit":
		if *session == "" || *mode == "" || *target == "" {
			return errors.New("--session --mode --target required")
		}
		out, e := s.AttemptViviEdit(*session, *mode, *target, *content, *dirty)
		result = out
		if e != nil {
			// Still emit the recorded attempt; non-zero exit via wrapping.
			_ = json.NewEncoder(os.Stdout).Encode(result)
			return e
		}
	case "vivi-propose":
		if *session == "" || *mode == "" || *diff == "" {
			return errors.New("--session --mode --diff required")
		}
		var e error
		result, e = s.EmitViviProposal(*session, *mode, *diff)
		if e != nil {
			return e
		}
	case "vivi-apply":
		if *session == "" || *proposal == "" {
			return errors.New("--session --proposal required")
		}
		out, e := s.ApplyViviProposal(*session, *proposal, *parentAuth, *applyPath)
		result = out
		if e != nil {
			_ = json.NewEncoder(os.Stdout).Encode(result)
			return e
		}
	case "vivi-continuity":
		raw, e := readInput(*input)
		if e != nil {
			return e
		}
		var c contract.ViviContinuityState
		if e := contract.StrictJSON(raw, &c); e != nil {
			return e
		}
		result, e = s.InitViviContinuity(c)
		if e != nil {
			return e
		}
	case "vivi-repair":
		if *continuity == "" {
			return errors.New("--continuity required")
		}
		var e error
		result, e = s.RecordViviRepairAttempt(*continuity, *decision, *failure)
		if e != nil {
			return e
		}
	case "vivi-reset":
		if *continuity == "" || *reason == "" {
			return errors.New("--continuity --reason required")
		}
		var e error
		result, e = s.RecordViviContextReset(*continuity, *reason)
		if e != nil {
			return e
		}
	case "vivi-verify":
		raw, e := readInput(*input)
		if e != nil {
			return e
		}
		v, e := contract.DecodeViviVerification(raw)
		if e != nil {
			return e
		}
		result, e = s.SubmitViviVerification(v)
		if e != nil {
			return e
		}
	case "vivi-boundary":
		if *session == "" || *task == "" {
			return errors.New("--session --task required")
		}
		var composition []string
		if *input != "" {
			raw, e := readInput(*input)
			if e != nil {
				return e
			}
			var payload struct {
				Composition []string `json:"method_composition"`
			}
			if e := contract.StrictJSON(raw, &payload); e != nil {
				return e
			}
			composition = payload.Composition
		}
		var e error
		result, e = s.RefuseViviBoundary(*session, *task, composition)
		if e != nil {
			return e
		}
	case "vivi-context":
		raw, e := readInput(*input)
		if e != nil {
			return e
		}
		c, e := contract.DecodeViviContextStrategy(raw)
		if e != nil {
			return e
		}
		result, e = s.SelectViviContextStrategy(c)
		if e != nil {
			return e
		}
	default:
		return errors.New("unsupported vivi command " + strconv.Quote(command))
	}
	return json.NewEncoder(os.Stdout).Encode(result)
}
