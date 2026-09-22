package controller

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
	"github.com/Rynaro/eidolons/gauge/internal/store"
)

const storeDirectory = ".gauge-controller-v1"
const markerName = ".writer-authority.json"

type layout struct {
	Version int    `json:"schema_version"`
	Kind    string `json:"kind"`
	StoreID string `json:"store_id"`
}
type marker struct {
	Version    int    `json:"schema_version"`
	Backend    string `json:"backend"`
	Phase      string `json:"phase"`
	StoreID    string `json:"store_id"`
	StorePath  string `json:"store_path"`
	RootID     string `json:"root_id"`
	Generation string `json:"generation"`
	Inventory  string `json:"inventory"`
}

func (s *Service) ledgerDir() string       { return filepath.Join(s.project, ".eidolons/.ledger") }
func (s *Service) storeDir() string        { return filepath.Join(s.ledgerDir(), storeDirectory) }
func (s *Service) storePath() string       { return filepath.Join(s.storeDir(), "state.db") }
func (s *Service) runDir(id string) string { return filepath.Join(s.ledgerDir(), id) }

func directory(path string, create bool) error {
	info, e := os.Lstat(path)
	if os.IsNotExist(e) && create {
		if e = os.Mkdir(path, 0700); e != nil && !os.IsExist(e) {
			return e
		}
		info, e = os.Lstat(path)
	}
	if e != nil {
		return e
	}
	if !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		return fmt.Errorf("expected real directory, refusing occupied/symlink path: %s", path)
	}
	return nil
}

func (s *Service) parents(create bool) error {
	if e := directory(s.project, false); e != nil {
		return e
	}
	for _, p := range []string{filepath.Join(s.project, ".eidolons"), s.ledgerDir()} {
		if e := directory(p, create); e != nil {
			return e
		}
	}
	return nil
}

func decodeFile(path string, v any) error {
	info, e := os.Lstat(path)
	if e != nil {
		return e
	}
	if !info.Mode().IsRegular() {
		return errors.New("metadata must be a regular file, not a symlink")
	}
	data, e := os.ReadFile(path)
	if e != nil {
		return e
	}
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.DisallowUnknownFields()
	if e = dec.Decode(v); e != nil {
		return e
	}
	var extra any
	if e = dec.Decode(&extra); e != io.EOF {
		return errors.New("metadata must contain exactly one object")
	}
	return nil
}

func atomicJSON(path string, v any) error {
	data, e := json.Marshal(v)
	if e != nil {
		return e
	}
	data = append(data, '\n')
	f, e := os.CreateTemp(filepath.Dir(path), ".gauge-write-")
	if e != nil {
		return e
	}
	temporary := f.Name()
	defer os.Remove(temporary)
	if _, e = f.Write(data); e != nil {
		_ = f.Close()
		return e
	}
	if e = f.Sync(); e != nil {
		_ = f.Close()
		return e
	}
	if e = f.Close(); e != nil {
		return e
	}
	if e = os.Rename(temporary, path); e != nil {
		return e
	}
	dir, e := os.Open(filepath.Dir(path))
	if e != nil {
		return e
	}
	defer dir.Close()
	return dir.Sync()
}

func (s *Service) inspect() (store.Snapshot, error) {
	var empty store.Snapshot
	if e := s.parents(false); e != nil {
		return empty, e
	}
	if e := directory(s.storeDir(), false); e != nil {
		return empty, e
	}
	var l layout
	if e := decodeFile(filepath.Join(s.storeDir(), "layout.json"), &l); e != nil {
		return empty, fmt.Errorf("controller layout unavailable; explicit recovery required: %w", e)
	}
	if l.Version != 1 || l.Kind != "gauge-controller-instance" || l.StoreID == "" {
		return empty, errors.New("unsupported or occupied controller layout")
	}
	snap, e := store.Inspect(s.storePath(), s.opts.Timeout)
	if e != nil {
		return snap, e
	}
	if snap.StoreID != l.StoreID {
		return empty, errors.New("controller layout/database identity mismatch")
	}
	return snap, nil
}

func (s *Service) Init() error {
	if e := s.validOptions(); e != nil {
		return e
	}
	if e := s.parents(true); e != nil {
		return e
	}
	if e := os.Mkdir(s.storeDir(), 0700); e != nil {
		if !os.IsExist(e) {
			return e
		}
		_, e = s.inspect()
		return e
	}
	// A crash during creation leaves an explicit incomplete layout. Init never
	// recreates it; an operator must preserve and diagnose that state.
	id := s.opts.IDs()
	if id == "" {
		return errors.New("empty controller identity")
	}
	if e := store.Create(s.storePath(), id); e != nil {
		return e
	}
	return atomicJSON(filepath.Join(s.storeDir(), "layout.json"), layout{Version: 1, Kind: "gauge-controller-instance", StoreID: id})
}

func (s *Service) validRoot(id string) error {
	if !contract.ValidRoot(id) || id == storeDirectory {
		return errors.New("invalid/reserved execution root")
	}
	return nil
}

func (s *Service) lock(id string, create bool) (func(), error) {
	if e := s.validOptions(); e != nil {
		return nil, e
	}
	if e := s.validRoot(id); e != nil {
		return nil, e
	}
	if e := s.parents(false); e != nil {
		return nil, e
	}
	if e := directory(s.runDir(id), create); e != nil {
		return nil, e
	}
	path := filepath.Join(s.runDir(id), ".append-lock")
	deadline := time.Now().Add(s.opts.Timeout)
	for {
		e := os.Mkdir(path, 0700)
		if e == nil {
			break
		}
		if !os.IsExist(e) {
			return nil, e
		}
		if !time.Now().Before(deadline) {
			return nil, errors.New("recovery-required: append ownership unavailable; establish all writers and publishing children quiescent before manual lock recovery")
		}
		time.Sleep(10 * time.Millisecond)
	}
	token := fmt.Sprintf("pid=%d\ntoken=gauge-%s\n", os.Getpid(), s.opts.IDs())
	owner := filepath.Join(path, "owner")
	if e := os.WriteFile(owner, []byte(token), 0600); e != nil {
		return nil, e
	}
	return func() {
		info, e := os.Lstat(owner)
		if e != nil || !info.Mode().IsRegular() {
			return
		}
		data, e := os.ReadFile(owner)
		if e != nil || string(data) != token {
			return
		}
		_ = os.Remove(owner)
		_ = os.Remove(path)
	}, nil
}

func (s *Service) readMarker(id string) (marker, error) {
	var m marker
	e := decodeFile(filepath.Join(s.runDir(id), markerName), &m)
	if e != nil {
		return m, e
	}
	if m.Version != 1 || m.Backend != "gauge" || (m.Phase != "pending" && m.Phase != "active") || m.RootID != id || m.StoreID == "" || m.Generation == "" || m.Inventory == "" || m.StorePath != s.storePath() {
		return m, errors.New("unsupported or conflicting writer authority; explicit recovery required")
	}
	return m, nil
}
func (s *Service) bound(m marker, snap store.Snapshot, r contract.Root) error {
	if m.StoreID != snap.StoreID || m.RootID != r.ID || m.Generation != r.Generation || m.Inventory != r.Inventory {
		return errors.New("marker/database authority disagreement; explicit recovery required")
	}
	return nil
}

func (s *Service) active(id string) (store.Snapshot, contract.Root, error) {
	snap, e := s.inspect()
	if e != nil {
		return snap, contract.Root{}, e
	}
	r, ok := snap.Roots[id]
	if !ok {
		return snap, r, errors.New("unknown execution root")
	}
	m, e := s.readMarker(id)
	if e != nil {
		return snap, r, e
	}
	if e = s.bound(m, snap, r); e != nil {
		return snap, r, e
	}
	if m.Phase != "active" || r.Phase != "active" {
		return snap, r, errors.New("incomplete transfer; explicit gauge recover required")
	}
	return snap, r, nil
}

func (s *Service) promoteLocked(id string, recovery bool) error {
	snap, e := s.inspect()
	if e != nil {
		return e
	}
	r, ok := snap.Roots[id]
	if !ok {
		return errors.New("root has no frozen import")
	}
	existing, e := s.readMarker(id)
	if e == nil {
		if e = s.bound(existing, snap, r); e != nil {
			return e
		}
		if existing.Phase == "active" && r.Phase == "active" {
			return nil
		}
		if !recovery {
			return errors.New("pending transfer requires explicit gauge recover")
		}
	} else if !os.IsNotExist(e) {
		return e
	} else if recovery || r.Phase != "staged" {
		return errors.New("missing authority marker; explicit inspection required")
	}
	if e = s.verifyInventory(r); e != nil {
		return e
	}
	m := marker{Version: 1, Backend: "gauge", Phase: "pending", StoreID: snap.StoreID, StorePath: s.storePath(), RootID: id, Generation: r.Generation, Inventory: r.Inventory}
	if e = atomicJSON(filepath.Join(s.runDir(id), markerName), m); e != nil {
		return e
	}
	if s.opts.Cut != nil {
		if e = s.opts.Cut("pending"); e != nil {
			return e
		}
	}
	db, e := store.Open(s.storePath(), s.opts.Timeout)
	if e != nil {
		return e
	}
	e = db.Activate(id, r.Generation, r.Inventory)
	closeErr := db.Close()
	if e != nil {
		return e
	}
	if closeErr != nil {
		return closeErr
	}
	if s.opts.Cut != nil {
		if e = s.opts.Cut("committed"); e != nil {
			return e
		}
	}
	m.Phase = "active"
	return atomicJSON(filepath.Join(s.runDir(id), markerName), m)
}

func (s *Service) Promote(id string) error {
	release, e := s.lock(id, false)
	if e != nil {
		return e
	}
	defer release()
	return s.promoteLocked(id, false)
}

// Recover does not remove an ambiguous append lock, infer quiescence from a
// PID, or fall back to legacy authority. It completes a recorded transfer only.
func (s *Service) Recover(id string) error {
	release, e := s.lock(id, false)
	if e != nil {
		return e
	}
	defer release()
	return s.promoteLocked(id, true)
}
