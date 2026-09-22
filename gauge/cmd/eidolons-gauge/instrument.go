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

func isInstrumentCommand(c string) bool {
	switch c {
	case "instrument-enable", "catalogue", "preflight", "freeze", "record", "shadow", "report", "eligibility":
		return true
	}
	return false
}

func instrumentCommand(args []string) error {
	command := args[0]
	flags := flag.NewFlagSet(command, flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	project := flags.String("project", ".", "project/controller directory")
	timeout := flags.Duration("lock-timeout", 5*time.Second, "bounded local lock wait")
	input := flags.String("input", "", "strict JSON document path")
	protocol := flags.String("protocol", "", "frozen protocol identity")
	tuple := flags.String("tuple", "", "capability tuple identity")
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
	case "instrument-enable":
	case "catalogue", "freeze", "record", "shadow", "eligibility":
		allowed["input"] = true
	case "preflight":
		allowed["tuple"] = true
		allowed["input"] = true
	case "report":
		allowed["protocol"] = true
	}
	for name := range seen {
		if !allowed[name] {
			return errors.New("option is not applicable to this command: " + name)
		}
	}
	s := controller.New(*project, controller.Options{Timeout: *timeout})
	var result any
	switch command {
	case "instrument-enable":
		if e := s.EnsureInstrumentNamespaces(); e != nil {
			return e
		}
		result = map[string]any{
			"instrument_namespaces": true,
			"schema_version":        2,
			"typed_version":         contract.InstrumentSchemaVersion,
			"live_qualification":    "blocked",
		}
	case "catalogue":
		if *input == "" {
			return errors.New("catalogue requires --input")
		}
		raw, e := os.ReadFile(*input)
		if e != nil {
			return e
		}
		t, e := contract.DecodeCapabilityTuple(raw)
		if e != nil {
			return errors.New("capability validation failed")
		}
		out, e := s.CatalogueCapability(t)
		if e != nil {
			return e
		}
		result = out
	case "preflight":
		req := contract.PreflightRequest{TupleID: *tuple}
		if *input != "" {
			raw, e := os.ReadFile(*input)
			if e != nil {
				return e
			}
			if e = contract.StrictJSON(raw, &req); e != nil {
				return e
			}
		}
		if req.TupleID == "" {
			return errors.New("preflight requires --tuple or input.tuple_id")
		}
		out, e := s.Preflight(req, controller.NewTransportCounters())
		if e != nil {
			return e
		}
		result = out
	case "freeze":
		if *input == "" {
			return errors.New("freeze requires --input")
		}
		raw, e := os.ReadFile(*input)
		if e != nil {
			return e
		}
		p, e := contract.DecodeFrozenProtocol(raw)
		if e != nil {
			return errors.New("protocol validation failed")
		}
		out, ev, e := s.FreezeProtocol(p)
		if e != nil {
			return e
		}
		result = map[string]any{"protocol": out, "ordering": ev}
	case "record":
		if *input == "" {
			return errors.New("record requires --input")
		}
		raw, e := os.ReadFile(*input)
		if e != nil {
			return e
		}
		r, e := contract.DecodeAttemptRecord(raw)
		if e != nil {
			return errors.New("attempt validation failed")
		}
		ev, e := s.RecordAttempt(r)
		if e != nil {
			return e
		}
		result = map[string]any{"attempt_id": r.ID, "ordering": ev}
	case "shadow":
		if *input == "" {
			return errors.New("shadow requires --input")
		}
		raw, e := os.ReadFile(*input)
		if e != nil {
			return e
		}
		var body struct {
			Enabled bool                     `json:"enabled"`
			Request contract.ExecutionRequest `json:"request"`
		}
		if e = contract.StrictJSON(raw, &body); e != nil {
			return e
		}
		req, obs, e := s.ShadowObserve(body.Enabled, body.Request, nil)
		if e != nil {
			return e
		}
		result = map[string]any{"request": req, "observation": obs}
	case "report":
		if *protocol == "" {
			return errors.New("report requires --protocol")
		}
		out, e := s.InstrumentReport(*protocol)
		if e != nil {
			return e
		}
		result = out
	case "eligibility":
		if *input == "" {
			return errors.New("eligibility requires --input")
		}
		raw, e := os.ReadFile(*input)
		if e != nil {
			return e
		}
		var body struct {
			TrialID            string               `json:"trial_id"`
			ProtocolID         string               `json:"protocol_id"`
			Arm                contract.ProtocolArm `json:"arm"`
			AvailablePackages  map[string]bool      `json:"available_packages"`
		}
		if e = contract.StrictJSON(raw, &body); e != nil {
			return e
		}
		out, e := s.EvaluateArmEligibility(body.TrialID, body.ProtocolID, body.Arm, body.AvailablePackages)
		if e != nil {
			return e
		}
		result = out
	}
	return json.NewEncoder(os.Stdout).Encode(result)
}
