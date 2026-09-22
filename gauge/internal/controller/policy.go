package controller

import (
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"sort"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
	"github.com/Rynaro/eidolons/gauge/internal/legacy"
	"github.com/Rynaro/eidolons/gauge/internal/store"
)

func (s *Service) preferencesStore() (*store.Store, error) {
	if _, e := s.inspect(); e != nil {
		return nil, e
	}
	return store.Open(s.storePath(), s.opts.Timeout)
}
func (s *Service) ReadPreferences() (map[string]contract.PreferenceDocument, error) {
	db, e := s.preferencesStore()
	if e != nil {
		return nil, e
	}
	defer db.Close()
	return db.ReadPreferences()
}
func (s *Service) UpdatePreferences(layer string, expected uint64, p contract.Preferences) (contract.PreferenceDocument, error) {
	db, e := s.preferencesStore()
	if e != nil {
		return contract.PreferenceDocument{}, e
	}
	defer db.Close()
	return db.UpdatePreferences(layer, expected, p)
}
func (s *Service) CompilePolicy(p contract.PolicyPatch) (contract.Policy, error) {
	db, e := s.preferencesStore()
	if e != nil {
		return contract.Policy{}, e
	}
	defer db.Close()
	return db.Compile(p)
}
func (s *Service) ApplyPolicy(id string, request contract.PolicyRequest) (contract.AmendmentResult, error) {
	var result contract.AmendmentResult
	release, e := s.lock(id, false)
	if e != nil {
		return result, e
	}
	defer release()
	_, r, e := s.active(id)
	if e != nil {
		return result, e
	}
	db, e := store.Open(s.storePath(), s.opts.Timeout)
	if e != nil {
		return result, e
	}
	defer db.Close()
	return db.ApplyPolicy(id, r.Generation, request)
}
func (s *Service) ReadPolicy(id, policyID string) (contract.Policy, error) {
	if _, e := s.Status(id); e != nil {
		return contract.Policy{}, e
	}
	db, e := s.preferencesStore()
	if e != nil {
		return contract.Policy{}, e
	}
	defer db.Close()
	p, e := db.ReadPolicy(policyID)
	if e == nil && p.Root != id {
		e = errors.New("policy root mismatch")
	}
	return p, e
}
func (s *Service) ReadPolicyBinding(id string) (contract.PolicyBinding, error) {
	if _, e := s.Status(id); e != nil {
		return contract.PolicyBinding{}, e
	}
	db, e := s.preferencesStore()
	if e != nil {
		return contract.PolicyBinding{}, e
	}
	defer db.Close()
	return db.ReadBinding(id)
}
func (s *Service) ReadAmendment(id, authorizationID string) (contract.AmendmentResult, error) {
	if _, e := s.Status(id); e != nil {
		return contract.AmendmentResult{}, e
	}
	db, e := s.preferencesStore()
	if e != nil {
		return contract.AmendmentResult{}, e
	}
	defer db.Close()
	r, e := db.ReadAmendment("policy-amendment@1", authorizationID)
	if e == nil && r.Root != id {
		e = errors.New("amendment root mismatch")
	}
	return r, e
}

func (s *Service) Migrate() error {
	if e := s.parents(false); e != nil {
		return e
	}
	if e := directory(s.storeDir(), false); e != nil {
		return e
	}
	var l layout
	if e := decodeFile(filepath.Join(s.storeDir(), "layout.json"), &l); e != nil {
		return e
	}
	if l.Version != 1 || l.Kind != "gauge-controller-instance" || l.StoreID == "" {
		return errors.New("unsupported layout")
	}
	before, e := store.InspectPredecessor(s.storePath(), s.opts.Timeout)
	if e != nil {
		return e
	}
	if l.StoreID != before.StoreID {
		return errors.New("layout/controller identity disagreement")
	}
	ids := make([]string, 0, len(before.Roots))
	for id := range before.Roots {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	releases := []func(){}
	defer func() {
		for i := len(releases) - 1; i >= 0; i-- {
			releases[i]()
		}
	}()
	for _, id := range ids {
		release, e := s.lock(id, false)
		if e != nil {
			return e
		}
		releases = append(releases, release)
	}
	return store.Migrate(s.storePath(), s.opts.Timeout, func(current store.Snapshot) error {
		if !reflect.DeepEqual(current.Roots, before.Roots) || current.StoreID != l.StoreID {
			return errors.New("predecessor changed during migration lock acquisition")
		}
		for _, id := range ids {
			r := current.Roots[id]
			if e := s.verifyInventory(r); e != nil {
				return e
			}
			if r.Legacy {
				inventory, e := legacy.Read(s.project, id)
				if e != nil {
					return e
				}
				if !reflect.DeepEqual(inventory.Events, current.Legacy[id]) {
					return errors.New("predecessor DB/filesystem inventory mismatch")
				}
			}
			if r.Phase == "active" {
				claim, e := s.readClaim(id)
				if e != nil {
					return e
				}
				if e = s.bound(claim, current, r); e != nil {
					return e
				}
				m, e := s.readMarker(id)
				if e != nil {
					return e
				}
				if e = s.bound(m, current, r); e != nil {
					return e
				}
				if m.Phase != "active" {
					return errors.New("incomplete transfer requires predecessor recovery before migration")
				}
			} else {
				for _, path := range []string{s.claimPath(id), filepath.Join(s.runDir(id), markerName)} {
					if _, e := os.Lstat(path); !os.IsNotExist(e) {
						return errors.New("pending transfer requires predecessor recovery before migration")
					}
				}
			}
		}
		return nil
	})
}
