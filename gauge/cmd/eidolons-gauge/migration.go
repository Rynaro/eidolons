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

func isMigrationCommand(c string) bool {
	switch c {
	case "migration-attempt", "migration-recover":
		return true
	}
	return false
}

func migrationCommand(args []string) error {
	command := args[0]
	flags := flag.NewFlagSet(command, flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	project := flags.String("project", ".", "project/controller directory")
	timeout := flags.Duration("lock-timeout", 5*time.Second, "bounded local lock wait")
	input := flags.String("input", "", "strict JSON document path")
	migration := flags.String("migration", "", "failed migration attempt id")
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
	case "migration-attempt":
		allowed["input"] = true
	case "migration-recover":
		allowed["migration"] = true
	}
	for name := range seen {
		if !allowed[name] {
			return errors.New("option is not applicable to this command: " + name)
		}
	}
	s := controller.New(*project, controller.Options{Timeout: *timeout})
	var result any
	switch command {
	case "migration-attempt":
		raw, e := os.ReadFile(*input)
		if e != nil {
			return e
		}
		m, e := contract.DecodeMigrationAttempt(raw)
		if e != nil {
			return e
		}
		result, e = s.AttemptMigration(m)
		if e != nil {
			return e
		}
	case "migration-recover":
		if *migration == "" {
			return errors.New("--migration required")
		}
		var e error
		result, e = s.RecoverMigration(*migration)
		if e != nil {
			return e
		}
	default:
		return errors.New("unsupported migration command")
	}
	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	return enc.Encode(result)
}
