package controller

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
)

// IsolationBoundary is an actual filesystem/process control for candidate
// execution. Worktree, directory label, process name, and hash alone are
// insufficient (ARCHITECTURE §Acceptance integrity).
type IsolationBoundary struct {
	Mode            string
	Root            string // temporary isolation root
	ProtectedDir    string // authoritative evidence / oracle / keys
	CandidateDir    string // writable candidate workspace
	BuildDir        string // writable build/temp
	CheckerCredPath string // checker credentials — never inherited by candidate
	enforced        bool
	savedModes      map[string]os.FileMode
}

// NewIsolationBoundary prepares dirs under base. Mode IsolationEnforced applies
// real chmod deny on protected paths; label/directory modes do not.
func NewIsolationBoundary(base, mode string) (*IsolationBoundary, error) {
	if base == "" {
		return nil, errors.New("isolation base required")
	}
	b := &IsolationBoundary{
		Mode:       mode,
		Root:       filepath.Join(base, "isolation"),
		savedModes: map[string]os.FileMode{},
	}
	b.ProtectedDir = filepath.Join(b.Root, "protected")
	b.CandidateDir = filepath.Join(b.Root, "candidate")
	b.BuildDir = filepath.Join(b.Root, "build")
	b.CheckerCredPath = filepath.Join(b.ProtectedDir, "checker.key")
	for _, d := range []string{b.ProtectedDir, b.CandidateDir, b.BuildDir} {
		if e := os.MkdirAll(d, 0o700); e != nil {
			return nil, e
		}
	}
	// Seed protected artifacts.
	for _, name := range []string{"journal.jsonl", "receipt.json", "oracle.yaml", "checker.key"} {
		p := filepath.Join(b.ProtectedDir, name)
		if e := os.WriteFile(p, []byte("authoritative:"+name+"\n"), 0o600); e != nil {
			return nil, e
		}
	}
	if mode == contract.IsolationEnforced {
		if e := b.enforce(); e != nil {
			return nil, e
		}
	}
	return b, nil
}

func (b *IsolationBoundary) enforce() error {
	// Make protected directory and contents read-only for the candidate process.
	entries, e := os.ReadDir(b.ProtectedDir)
	if e != nil {
		return e
	}
	for _, ent := range entries {
		p := filepath.Join(b.ProtectedDir, ent.Name())
		info, e := os.Stat(p)
		if e != nil {
			return e
		}
		b.savedModes[p] = info.Mode()
		if e := os.Chmod(p, 0o444); e != nil {
			return e
		}
	}
	info, e := os.Stat(b.ProtectedDir)
	if e != nil {
		return e
	}
	b.savedModes[b.ProtectedDir] = info.Mode()
	if e := os.Chmod(b.ProtectedDir, 0o555); e != nil {
		return e
	}
	b.enforced = true
	return nil
}

// Capability reports whether isolation is a positive control.
func (b *IsolationBoundary) Capability(contextProvenance string) contract.IsolationCapability {
	cap := contract.IsolationCapability{
		Mode:              b.Mode,
		Enforced:          b.enforced && b.Mode == contract.IsolationEnforced,
		ProtectedPaths:    []string{b.ProtectedDir},
		AllowWritePaths:   []string{b.CandidateDir, b.BuildDir},
		ContextProvenance: contextProvenance,
	}
	switch b.Mode {
	case contract.IsolationEnforced:
		if b.enforced {
			cap.Detail = "chmod deny on protected evidence/oracle/keys; candidate write allowlist"
		} else {
			cap.Detail = "enforced mode requested but not active"
			cap.Enforced = false
		}
	case contract.IsolationLabel:
		cap.Detail = "label without access enforcement"
		cap.Enforced = false
	case contract.IsolationDirectory:
		cap.Detail = "separate directory without access enforcement"
		cap.Enforced = false
	default:
		cap.Detail = "isolation absent"
		cap.Enforced = false
	}
	return cap
}

// AttemptProtectedWrite tries to write path under protected dir from a
// candidate-controlled context. Returns nil error only if the write succeeded
// (which should not happen under enforced isolation).
func (b *IsolationBoundary) AttemptProtectedWrite(name, content string) error {
	target := filepath.Join(b.ProtectedDir, name)
	return os.WriteFile(target, []byte(content), 0o600)
}

// AttemptProtectedWriteViaShell runs a candidate-controlled shell that tries to
// overwrite journal/receipt/oracle/key. Under enforced isolation the writes fail.
func (b *IsolationBoundary) AttemptProtectedWriteViaShell(name, content string) (denied bool, output string, err error) {
	target := filepath.Join(b.ProtectedDir, name)
	script := fmt.Sprintf(`printf '%%s' %q > %q`, content, target)
	cmd := exec.Command("sh", "-c", script)
	cmd.Dir = b.CandidateDir
	// Candidate scripts cannot inherit checker credentials (HANDOFF / stop rule).
	cmd.Env = filteredCandidateEnv()
	out, e := cmd.CombinedOutput()
	output = string(out)
	if e != nil {
		return true, output, nil
	}
	// Write appeared to succeed — verify content was not actually changed when enforced.
	data, readErr := os.ReadFile(target)
	if readErr != nil {
		return true, output, nil
	}
	if string(data) == content {
		return false, output, errors.New("protected write succeeded unexpectedly")
	}
	return true, output, nil
}

func filteredCandidateEnv() []string {
	var out []string
	for _, kv := range os.Environ() {
		upper := strings.ToUpper(kv)
		if strings.HasPrefix(upper, "CHECKER_") ||
			strings.HasPrefix(upper, "GAUGE_SIGNER_") ||
			strings.HasPrefix(upper, "ACCEPTANCE_KEY=") {
			continue
		}
		out = append(out, kv)
	}
	return out
}

// CandidateEnvHasCheckerCreds reports whether a candidate env would see checker secrets.
func CandidateEnvHasCheckerCreds(env []string) bool {
	for _, kv := range env {
		upper := strings.ToUpper(kv)
		if strings.HasPrefix(upper, "CHECKER_") ||
			strings.HasPrefix(upper, "GAUGE_SIGNER_") ||
			strings.HasPrefix(upper, "ACCEPTANCE_KEY=") {
			return true
		}
	}
	return false
}

// Release restores writable modes for cleanup (test teardown).
func (b *IsolationBoundary) Release() error {
	if !b.enforced {
		return nil
	}
	// Directory first so we can chmod children.
	if mode, ok := b.savedModes[b.ProtectedDir]; ok {
		_ = os.Chmod(b.ProtectedDir, mode|0o200)
	} else {
		_ = os.Chmod(b.ProtectedDir, 0o700)
	}
	for p, mode := range b.savedModes {
		if p == b.ProtectedDir {
			continue
		}
		_ = os.Chmod(p, mode)
	}
	_ = os.Chmod(b.ProtectedDir, 0o700)
	b.enforced = false
	return nil
}

// GradeFromIsolation maps isolation capability to trusted integrity grade (R04).
func GradeFromIsolation(cap contract.IsolationCapability) contract.VerificationGradeReport {
	report := contract.VerificationGradeReport{
		AdequacyGrade: contract.GradeAdequacyWithheld, // adequacy is separate
	}
	if !cap.Enforced {
		report.IntegrityGrade = contract.GradeWithheld
		report.Trusted = false
		report.Reasons = append(report.Reasons, "isolation_not_enforced:"+cap.Mode)
	}
	if cap.ContextProvenance != "present" {
		report.IntegrityGrade = contract.GradeWithheld
		report.Trusted = false
		report.Reasons = append(report.Reasons, "context_provenance_absent")
	}
	if cap.Enforced && cap.ContextProvenance == "present" {
		report.IntegrityGrade = contract.GradeTrustedIntegrity
		report.Trusted = true
		report.Reasons = append(report.Reasons, "supported_isolation_positive_control")
	}
	if report.IntegrityGrade == "" {
		report.IntegrityGrade = contract.GradeUntrustedIntegrity
		report.Trusted = false
	}
	return report
}
