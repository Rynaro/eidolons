// Package legacy validates journal v1 with its original jq byte contract.
// Imported events retain their exact source bytes; Go JSON is never used to
// reproduce a legacy digest or to strengthen legacy evidence provenance.
package legacy

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"time"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
)

type Inventory struct {
	Digest string
	Events []contract.LegacyEvent
}

const validation = `sort_by(.sequence) as $e |
 if ($e|length) != $count then error("one event per file required")
 elif any($e[]; .schema_version != "1.0") then error("unsupported journal version")
 elif any($e[];
  (type != "object") or
  ((keys - ["schema_version","event_id","run_id","sequence","event_type","timestamp","previous_event_digest","requested","observed","evidence_refs","event_digest"])|length > 0) or
  (.run_id != $run) or (.event_id|type != "string") or (.event_id == "") or
  (.event_type|type != "string") or (.timestamp|type != "string") or
  (.requested|type != "object") or (.observed|type != "object") or
  (.evidence_refs|type != "array") or (.event_digest|type != "string") or
  (.event_digest|test("^[a-f0-9]{64}$")|not)) then error("invalid event shape")
 elif ($e|map(.event_id)|unique|length) != $count then error("duplicate event identity")
 elif any(range(0;$count); . as $i |
  ($e[$i].sequence != ($i+1)) or
  ($e[$i].previous_event_digest != (if $i == 0 then null else $e[$i-1].event_digest end)))
  then error("invalid sequence or predecessor")
 else $e[] | .event_digest, del(.event_digest) end`

func Read(project, run string) (Inventory, error) {
	result := Inventory{Events: []contract.LegacyEvent{}}
	if !contract.ValidRoot(run) {
		return result, errors.New("invalid legacy run identity")
	}
	dir := filepath.Join(project, ".eidolons/.ledger", run, "events")
	info, e := os.Lstat(dir)
	if e != nil {
		return result, e
	}
	if !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		return result, errors.New("legacy events must be a real directory")
	}
	entries, e := os.ReadDir(dir)
	if e != nil {
		return result, e
	}
	if len(entries) == 0 {
		return result, errors.New("empty legacy history cannot be imported")
	}
	names := map[string]bool{}
	for _, entry := range entries {
		names[entry.Name()] = true
	}
	var stream bytes.Buffer
	inventoryHash := sha256.New()
	for i := 1; i <= len(entries); i++ {
		name := strconv.Itoa(i) + ".json"
		if !names[name] {
			return result, errors.New("legacy inventory is partial or has unexpected entries")
		}
		path := filepath.Join(dir, name)
		info, e := os.Lstat(path)
		if e != nil {
			return result, e
		}
		if !info.Mode().IsRegular() {
			return result, errors.New("legacy event must be regular, not a symlink")
		}
		raw, e := os.ReadFile(path)
		if e != nil {
			return result, e
		}
		var header struct {
			Sequence int    `json:"sequence"`
			ID       string `json:"event_id"`
		}
		if e = json.Unmarshal(raw, &header); e != nil {
			return result, e
		}
		if header.Sequence != i {
			return result, errors.New("legacy filename/sequence mismatch")
		}
		stream.Write(raw)
		stream.WriteByte('\n')
		_, _ = fmt.Fprintf(inventoryHash, "%d:%s%d:", len(name), name, len(raw))
		_, _ = inventoryHash.Write(raw)
		result.Events = append(result.Events, contract.LegacyEvent{ID: header.ID, Raw: raw, Grade: "self-attested"})
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "jq", "-cesS", "--arg", "run", run, "--argjson", "count", strconv.Itoa(len(entries)), validation)
	cmd.Stdin = &stream
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	canonical, e := cmd.Output()
	if e != nil {
		return result, fmt.Errorf("legacy canonical validation refused: %w: %s", e, stderr.String())
	}
	lines := bytes.Split(bytes.TrimSuffix(canonical, []byte("\n")), []byte("\n"))
	if len(lines) != 2*len(entries) {
		return result, errors.New("invalid jq canonical stream")
	}
	for i := 0; i < len(lines); i += 2 {
		var expected string
		if e = json.Unmarshal(lines[i], &expected); e != nil {
			return result, e
		}
		actual := contract.Digest(append(append([]byte{}, lines[i+1]...), '\n'))
		if actual != expected {
			return result, errors.New("legacy event digest mismatch")
		}
	}
	result.Digest = hex.EncodeToString(inventoryHash.Sum(nil))
	return result, nil
}
