// Package controller is an opt-in durable seam. Native harnesses still own
// reasoning and editing; the only executable adapter here is a local fixture.
package controller

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"time"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
	"github.com/Rynaro/eidolons/gauge/internal/legacy"
	"github.com/Rynaro/eidolons/gauge/internal/store"
)

type Adapter interface {
	Observe(context.Context, contract.FixtureInput) (contract.ObservationResult, error)
}
type FixtureAdapter struct{}

func (FixtureAdapter) Observe(_ context.Context, in contract.FixtureInput) (contract.ObservationResult, error) {
	if e := in.Validate(); e != nil {
		return contract.ObservationResult{}, e
	}
	return contract.ObservationResult{Outcome: in.Outcome, ObservedModel: "unknown", ModelCalls: 0}, nil
}

type Options struct {
	Timeout time.Duration
	Clock   func() time.Time
	IDs     func() string
	Adapter Adapter
	// Cut is an embedding/test fault barrier; it is never exposed as a CLI flag
	// or environment switch and runs outside database transactions.
	Cut func(string) error
}
type Service struct {
	project string
	opts    Options
}

func New(project string, opts Options) *Service {
	absolute, e := filepath.Abs(project)
	if e != nil {
		absolute = project
	}
	if real, e := filepath.EvalSymlinks(absolute); e == nil {
		absolute = real
	}
	if opts.Timeout == 0 {
		opts.Timeout = 5 * time.Second
	}
	if opts.Clock == nil {
		opts.Clock = time.Now
	}
	if opts.IDs == nil {
		opts.IDs = rand.Text
	}
	if opts.Adapter == nil {
		opts.Adapter = FixtureAdapter{}
	}
	return &Service{project: absolute, opts: opts}
}
func (s *Service) validOptions() error {
	if s.opts.Timeout <= 0 || s.opts.Timeout > 300*time.Second {
		return errors.New("lock timeout must be positive and at most 300 seconds")
	}
	return nil
}

func (s *Service) newRoot(id, inventory string, imported bool) contract.Root {
	generation := s.opts.IDs()
	b := contract.Binding{Root: id, Assignment: s.opts.IDs(), Profile: "fixture", Method: "fixture@1", Worker: s.opts.IDs(), Invocation: s.opts.IDs(), Context: s.opts.IDs(), Authority: generation, Candidate: "unavailable", Receipt: "unavailable", Environment: "unknown"}
	m := contract.Manifest{Version: 1, RequestedModel: "none", ObservedModel: "unknown", Harness: "native-unobserved", Adapter: "fixture@1", Methods: []string{"fixture@1"}, Environment: b.Environment, PolicyRefs: []string{}}
	if imported {
		// A frozen journal does not establish its historical harness settings.
		b.Profile, b.Method = "unknown", "unknown"
		m.RequestedModel, m.Methods = "unknown", []string{"unknown"}
		m.Adapter = "unknown"
	}
	return contract.Root{ID: id, Phase: "staged", Generation: generation, Inventory: inventory, Legacy: imported, Binding: b, Manifest: m, PolicyRefs: []string{}, Intents: []string{}, Evidence: []string{}}
}

func (s *Service) InitRoot(id string) error {
	if _, e := s.inspect(); e != nil {
		return e
	}
	release, e := s.lock(id, true)
	if e != nil {
		return e
	}
	defer release()
	snap, e := s.inspect()
	if e != nil {
		return e
	}
	if _, ok := snap.Roots[id]; ok {
		_, _, e = s.active(id)
		return e
	}
	for _, path := range []string{filepath.Join(s.runDir(id), markerName), s.claimPath(id)} {
		if _, e = os.Lstat(path); !os.IsNotExist(e) {
			return errors.New("occupied execution authority path")
		}
	}
	events := filepath.Join(s.runDir(id), "events")
	if info, e := os.Lstat(events); e == nil {
		if !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
			return errors.New("occupied legacy events path")
		}
		entries, e := os.ReadDir(events)
		if e != nil {
			return e
		}
		if len(entries) > 0 {
			return errors.New("existing legacy history requires explicit import")
		}
	} else if !os.IsNotExist(e) {
		return e
	}
	root := s.newRoot(id, contract.Digest([]byte("empty-inventory-v1")), false)
	db, e := store.Open(s.storePath(), s.opts.Timeout)
	if e != nil {
		return e
	}
	e = db.Stage(root, nil)
	_ = db.Close()
	if e != nil {
		return e
	}
	return s.promoteLocked(id, false)
}

func (s *Service) Import(id string) error {
	release, e := s.lock(id, false)
	if e != nil {
		return e
	}
	defer release()
	snap, e := s.inspect()
	if e != nil {
		return e
	}
	inventory, e := legacy.Read(s.project, id)
	if e != nil {
		return e
	}
	if previous, ok := snap.Roots[id]; ok {
		if previous.Inventory != inventory.Digest || !previous.Legacy || !reflect.DeepEqual(snap.Legacy[id], inventory.Events) {
			return errors.New("frozen import conflict; original inventory retained")
		}
		if previous.Phase == "active" {
			_, _, e = s.active(id)
			return e
		}
		for _, path := range []string{filepath.Join(s.runDir(id), markerName), s.claimPath(id)} {
			if _, e = os.Lstat(path); !os.IsNotExist(e) {
				return errors.New("pending authority requires explicit recovery")
			}
		}
		return nil
	}
	for _, path := range []string{filepath.Join(s.runDir(id), markerName), s.claimPath(id)} {
		if _, e = os.Lstat(path); !os.IsNotExist(e) {
			return errors.New("unregistered authority proof; import refused")
		}
	}
	root := s.newRoot(id, inventory.Digest, true)
	db, e := store.Open(s.storePath(), s.opts.Timeout)
	if e != nil {
		return e
	}
	defer db.Close()
	return db.Stage(root, inventory.Events)
}

func (s *Service) verifyInventory(r contract.Root) error {
	if r.Legacy {
		inventory, e := legacy.Read(s.project, r.ID)
		if e != nil {
			return e
		}
		if inventory.Digest != r.Inventory {
			return errors.New("legacy inventory changed since import; promotion refused")
		}
		return nil
	}
	entries, e := os.ReadDir(filepath.Join(s.runDir(r.ID), "events"))
	if e != nil && !os.IsNotExist(e) {
		return e
	}
	if len(entries) > 0 {
		return errors.New("unexpected legacy events for controller-created root")
	}
	return nil
}

type Status struct {
	StoreID           string                 `json:"store_id"`
	Scope             string                 `json:"scope"`
	Root              contract.Root          `json:"root"`
	History           []contract.Record      `json:"history"`
	Imported          []contract.LegacyEvent `json:"imported_historical_evidence"`
	CurrentAcceptance string                 `json:"current_acceptance"`
}

func (s *Service) Status(id string) (Status, error) {
	var result Status
	if e := s.validRoot(id); e != nil {
		return result, e
	}
	if e := s.parents(false); e != nil {
		return result, e
	}
	if e := directory(s.runDir(id), false); e != nil {
		return result, e
	}
	lock := filepath.Join(s.runDir(id), ".append-lock")
	if _, e := os.Lstat(lock); !os.IsNotExist(e) {
		return result, errors.New("recovery-required: append ownership unresolved")
	}
	snap, r, e := s.active(id)
	if e != nil {
		return result, e
	}
	if _, e = os.Lstat(lock); !os.IsNotExist(e) {
		return result, errors.New("append ownership changed during inspection")
	}
	return Status{StoreID: snap.StoreID, Scope: "controller-instance", Root: r, History: snap.Records[id], Imported: snap.Legacy[id], CurrentAcceptance: "unavailable"}, nil
}

func (s *Service) ExecuteFixture(ctx context.Context, id, eventID string, in contract.FixtureInput) (contract.Receipt, error) {
	var result contract.Receipt
	if eventID == "" {
		return result, errors.New("fixture event identity required")
	}
	if e := in.Validate(); e != nil {
		return result, e
	}
	release, e := s.lock(id, false)
	if e != nil {
		return result, e
	}
	defer release()
	snap, r, e := s.active(id)
	if e != nil {
		return result, e
	}
	manifestID, e := r.Manifest.Identity()
	if e != nil {
		return result, e
	}
	payload, e := json.Marshal(struct {
		Input    contract.FixtureInput `json:"input"`
		Manifest string                `json:"manifest"`
	}{in, manifestID})
	if e != nil {
		return result, e
	}
	inputDigest := contract.Digest(payload)
	for _, record := range snap.Records[id] {
		if record.Family == "history" && record.ID == eventID {
			if record.Kind != "receipt" {
				return result, errors.New("event identity conflict")
			}
			if e = json.Unmarshal(record.Body, &result); e != nil {
				return result, e
			}
			if result.InputDigest != inputDigest {
				return contract.Receipt{}, errors.New("fixture event identity conflict")
			}
			return result, nil
		}
	}
	// External execution happens before the short dependent-state transaction.
	observation, e := s.opts.Adapter.Observe(ctx, in)
	if e != nil {
		return result, e
	}
	if observation.ModelCalls != 0 {
		return result, errors.New("fixture adapter attempted model execution")
	}
	if observation.ObservedModel == "" {
		observation.ObservedModel = "unknown"
	}
	if e = (contract.FixtureInput{Outcome: observation.Outcome}).Validate(); e != nil {
		return result, e
	}
	result = contract.Receipt{ID: eventID, RootID: id, Outcome: observation.Outcome, ObservedModel: observation.ObservedModel, ModelCalls: 0, Timestamp: s.opts.Clock().UTC().Format(time.RFC3339), Grade: "fixture-only", Accepted: false, InputDigest: inputDigest}
	body, e := json.Marshal(result)
	if e != nil {
		return result, e
	}
	db, e := store.Open(s.storePath(), s.opts.Timeout)
	if e != nil {
		return result, e
	}
	defer db.Close()
	e = db.Update(id, r.Generation, func(tx *store.Tx) error {
		fresh, e := tx.Once(eventID, payload)
		if e != nil {
			return e
		}
		if !fresh {
			return errors.New("receipt missing for existing operation; recovery required")
		}
		if e = tx.Put(contract.Record{ID: eventID, Family: "history", Kind: "receipt", Body: body}); e != nil {
			return e
		}
		root := tx.Root()
		root.Binding.Receipt = eventID
		root.Evidence = append(root.Evidence, eventID)
		return tx.SetRoot(root)
	})
	return result, e
}

// Replace supports fixture reconstruction only. Real harness reconstruction
// must be supplied and qualified by its native adapter in a later package.
func (s *Service) Replace(id, worker, environment string, reconstruct bool) error {
	if !reconstruct {
		return errors.New("unsupported reconstruction; durable state retained")
	}
	if worker == "" && environment == "" {
		return errors.New("replacement identity required")
	}
	release, e := s.lock(id, false)
	if e != nil {
		return e
	}
	defer release()
	_, r, e := s.active(id)
	if e != nil {
		return e
	}
	// Imported labels do not establish reconstruction capability, including
	// historical roots created by earlier versions that defaulted to fixture.
	if r.Legacy || r.Manifest.Adapter != "fixture@1" {
		return errors.New("unsupported adapter reconstruction")
	}
	if worker != "" {
		r.Binding.Worker = worker
		r.Binding.Invocation = s.opts.IDs()
		r.Binding.Context = s.opts.IDs()
	}
	if environment != "" {
		r.Binding.Environment = environment
		r.Manifest.Environment = environment
	}
	if _, e = r.Manifest.Identity(); e != nil {
		return e
	}
	db, e := store.Open(s.storePath(), s.opts.Timeout)
	if e != nil {
		return e
	}
	defer db.Close()
	return db.Update(id, r.Generation, func(tx *store.Tx) error { return tx.SetRoot(r) })
}

func (s *Service) String() string { return fmt.Sprintf("controller-instance %s", s.storePath()) }
