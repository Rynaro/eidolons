package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestV407CLI(t *testing.T) {
	project := filepath.Join(t.TempDir(), "project espaço 日本")
	if e := os.MkdirAll(project, 0700); e != nil {
		t.Fatal(e)
	}
	if e := run([]string{"init", "--project", project, "--root", "root"}); e != nil {
		t.Fatal(e)
	}
	input := filepath.Join(t.TempDir(), "preferences input.json")
	if e := os.WriteFile(input, []byte(`{"schema_version":1,"preset":"Conserve"}`), 0600); e != nil {
		t.Fatal(e)
	}
	if e := run([]string{"preferences-set", "--project", project, "--layer", "user", "--expected-revision", "0", "--input", input}); e != nil {
		t.Fatal(e)
	}
	for _, args := range [][]string{{"preferences", "--project", project}, {"policy-compile", "--project", project}} {
		if e := run(args); e != nil {
			t.Fatal(e)
		}
	}
	for _, args := range [][]string{
		{"preferences-set", "--project", project, "--layer", "user", "--expected-revision", "0", "--input", input},
		{"preferences-set", "--project", project, "--layer", "account", "--expected-revision", "0", "--input", input},
		{"policy-bind", "--project", project, "--root", "root", "--authorization-id", "forged"},
		{"policy-amend", "--project", project, "--root", "root", "--authorization-id", "forged", "--predecessor", "copied"},
		{"policy-bind", "--project", project, "--root", "root", "--source", "operator"},
		{"policy-bind", "--project", project, "--root", "root", "--authorized"},
		{"policy-bind", "--project", project, "--root", "root", "--grant-file", input},
		{"migrate", "--project", project},
		{"preferences-set", "--project", project, "--layer", "user", "--input", input},
	} {
		if e := run(args); e == nil {
			t.Fatal("negative command accepted", args)
		}
	}
	if e := os.WriteFile(input, []byte(`{"schema_version":1,"preset":"Balanced","preset":"Accelerate"}`), 0600); e != nil {
		t.Fatal(e)
	}
	if e := run([]string{"preferences-set", "--project", project, "--layer", "user", "--expected-revision", "1", "--input", input}); e == nil {
		t.Fatal("CLI collapsed duplicate")
	}
}
