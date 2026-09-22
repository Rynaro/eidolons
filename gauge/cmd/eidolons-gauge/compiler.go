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

func isCompilerCommand(c string) bool {
	switch c {
	case "compiler-enable", "compile", "compiler-status", "consult-validate",
		"compiler-rebind", "compiler-evidence", "compiler-writers":
		return true
	}
	return false
}

func compilerCommand(args []string) error {
	command := args[0]
	flags := flag.NewFlagSet(command, flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	project := flags.String("project", ".", "project/controller directory")
	timeout := flags.Duration("lock-timeout", 5*time.Second, "bounded local lock wait")
	root := flags.String("root", "", "execution root")
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
	case "compiler-enable":
	case "compile", "consult-validate", "compiler-rebind", "compiler-evidence", "compiler-writers":
		allowed["root"] = true
		allowed["input"] = true
	case "compiler-status":
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
	case "compiler-enable":
		if e := s.EnsureCompilerNamespaces(); e != nil {
			return e
		}
		result = map[string]any{
			"compiler_namespaces": true,
			"schema_version":      2,
			"typed_version":       contract.CompilerSchemaVersion,
			"experimental_profile": contract.ExperimentalProfileID,
			"scope":               "fixture-assignment-compiler",
			"live_qualification":  "blocked",
			"semantic_correctness": "fallible_inspectable_reasons_only",
		}
	case "compile":
		if *root == "" || *input == "" {
			return errors.New("compile requires --root and --input")
		}
		raw, e := os.ReadFile(*input)
		if e != nil {
			return e
		}
		req, e := contract.DecodeCompileRequest(raw)
		if e != nil {
			return e
		}
		out, e := s.CompileAssignments(*root, req)
		if e != nil {
			return e
		}
		result = out
	case "compiler-status":
		if *root == "" {
			return errors.New("compiler-status requires --root")
		}
		plans, e := s.CompilerStatus(*root)
		if e != nil {
			return e
		}
		result = map[string]any{"plans": plans}
	case "consult-validate":
		if *root == "" || *input == "" {
			return errors.New("consult-validate requires --root and --input")
		}
		raw, e := os.ReadFile(*input)
		if e != nil {
			return e
		}
		req, e := contract.DecodeValidateConsultantRequest(raw)
		if e != nil {
			return e
		}
		out, e := s.ValidateConsultantResult(*root, req)
		if e != nil {
			return e
		}
		result = out
	case "compiler-rebind":
		if *root == "" || *input == "" {
			return errors.New("compiler-rebind requires --root and --input")
		}
		raw, e := os.ReadFile(*input)
		if e != nil {
			return e
		}
		req, e := contract.DecodeRoleRebindRequest(raw)
		if e != nil {
			return e
		}
		out, e := s.EvaluateRoleRebind(*root, req)
		if e != nil {
			return e
		}
		result = out
	case "compiler-evidence":
		if *root == "" || *input == "" {
			return errors.New("compiler-evidence requires --root and --input")
		}
		raw, e := os.ReadFile(*input)
		if e != nil {
			return e
		}
		req, e := contract.DecodeClassifyEvidenceRequest(raw)
		if e != nil {
			return e
		}
		out, e := s.ClassifyEvidence(*root, req)
		if e != nil {
			return e
		}
		result = out
	case "compiler-writers":
		if *root == "" || *input == "" {
			return errors.New("compiler-writers requires --root and --input")
		}
		raw, e := os.ReadFile(*input)
		if e != nil {
			return e
		}
		req, e := contract.DecodeConcurrentWritersRequest(raw)
		if e != nil {
			return e
		}
		out, e := s.AdmitConcurrentWriters(*root, req)
		if e != nil {
			return e
		}
		result = out
	default:
		return errors.New("unsupported compiler command")
	}
	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	return enc.Encode(result)
}
