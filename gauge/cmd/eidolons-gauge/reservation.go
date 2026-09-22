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

func isReservationCommand(c string) bool {
	switch c {
	case "reservation-enable", "reservation-admit", "reservation-status", "reservation-reconcile", "reservation-amend":
		return true
	}
	return false
}

func reservationCommand(args []string) error {
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
	case "reservation-enable":
	case "reservation-admit", "reservation-reconcile", "reservation-amend":
		allowed["root"] = true
		allowed["input"] = true
	case "reservation-status":
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
	case "reservation-enable":
		if e := s.EnsureReservationNamespaces(); e != nil {
			return e
		}
		result = map[string]any{
			"reservation_namespaces": true,
			"schema_version":         2,
			"typed_version":          contract.ReservationSchemaVersion,
			"scope":                  "fixture-local-atomic-admission",
			"provider_dispatch":      "excluded",
		}
	case "reservation-admit":
		if *root == "" || *input == "" {
			return errors.New("reservation-admit requires --root and --input")
		}
		raw, e := os.ReadFile(*input)
		if e != nil {
			return e
		}
		req, e := contract.DecodeAdmitRequest(raw)
		if e != nil {
			return e
		}
		out, e := s.AdmitReservation(*root, req)
		if e != nil {
			return e
		}
		result = out
	case "reservation-status":
		if *root == "" {
			return errors.New("reservation-status requires --root")
		}
		res, bals, e := s.ReservationStatus(*root)
		if e != nil {
			return e
		}
		result = map[string]any{"reservations": res, "balances": bals}
	case "reservation-reconcile":
		if *root == "" || *input == "" {
			return errors.New("reservation-reconcile requires --root and --input")
		}
		raw, e := os.ReadFile(*input)
		if e != nil {
			return e
		}
		var req contract.ReconcileRequest
		if e := contract.StrictJSON(raw, &req); e != nil {
			return e
		}
		if e := req.Validate(); e != nil {
			return e
		}
		out, e := s.ReconcileReservation(*root, req)
		if e != nil {
			return e
		}
		result = out
	case "reservation-amend":
		if *root == "" || *input == "" {
			return errors.New("reservation-amend requires --root and --input")
		}
		raw, e := os.ReadFile(*input)
		if e != nil {
			return e
		}
		var req contract.AmendRequest
		if e := contract.StrictJSON(raw, &req); e != nil {
			return e
		}
		if e := req.Validate(); e != nil {
			return e
		}
		res, bals, e := s.AmendReservation(*root, req)
		if e != nil {
			return e
		}
		result = map[string]any{"reservation": res, "balances": bals}
	}
	return json.NewEncoder(os.Stdout).Encode(result)
}
