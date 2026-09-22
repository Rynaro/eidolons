package store

import (
	"encoding/json"
	"errors"
	"fmt"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
	bolt "go.etcd.io/bbolt"
)

var dispatchBuckets = []string{"dispatch_intents", "dispatch_events", "dispatch_acks", "dispatch_ops"}

type dispatchReceipt struct {
	Version    int    `json:"schema_version"`
	Controller string `json:"controller"`
	Kind       string `json:"kind"`
	Typed      int    `json:"typed_version"`
}

func initializeDispatch(tx *bolt.Tx, id, kind string) error {
	for _, name := range dispatchBuckets {
		if _, e := tx.CreateBucketIfNotExists([]byte(name)); e != nil {
			return e
		}
	}
	return putJSON(tx.Bucket([]byte("meta")), "dispatch_receipt", dispatchReceipt{
		Version: 1, Controller: id, Kind: kind, Typed: contract.DispatchSchemaVersion,
	})
}

func guardDispatch(tx *bolt.Tx) error {
	meta := tx.Bucket([]byte("meta"))
	raw := meta.Get([]byte("dispatch_receipt"))
	missing := 0
	for _, name := range dispatchBuckets {
		if tx.Bucket([]byte(name)) == nil {
			missing++
		}
	}
	if raw == nil && missing == len(dispatchBuckets) {
		// Pre-V4-12 schema 2 stores remain openable; dispatch APIs ensure namespaces.
		return nil
	}
	if raw == nil || missing != 0 {
		return errors.New("incomplete dispatch namespaces; call dispatch-enable")
	}
	var receipt dispatchReceipt
	if e := contract.StrictJSON(raw, &receipt); e != nil {
		return errors.New("invalid dispatch receipt")
	}
	id := string(meta.Get([]byte("store_id")))
	if receipt.Version != 1 || receipt.Controller != id || receipt.Typed != contract.DispatchSchemaVersion {
		return errors.New("unsupported dispatch receipt")
	}
	return nil
}

func (s *Store) dispatchReady(tx *bolt.Tx) error {
	for _, name := range dispatchBuckets {
		if tx.Bucket([]byte(name)) == nil {
			return errors.New("dispatch namespaces required")
		}
	}
	if tx.Bucket([]byte("meta")).Get([]byte("dispatch_receipt")) == nil {
		return errors.New("dispatch namespaces required")
	}
	return nil
}

// EnsureDispatchNamespaces adds typed dispatch buckets under schema 2 without a schema bump.
func (s *Store) EnsureDispatchNamespaces() error {
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := guardBase(tx, "2"); e != nil {
			return e
		}
		if e := guardPolicy(tx); e != nil {
			return e
		}
		if e := guardObservation(tx); e != nil {
			return e
		}
		if e := guardInstrument(tx); e != nil {
			return e
		}
		if e := guardReservation(tx); e != nil {
			return e
		}
		id := string(tx.Bucket([]byte("meta")).Get([]byte("store_id")))
		if raw := tx.Bucket([]byte("meta")).Get([]byte("dispatch_receipt")); raw != nil {
			return guardDispatch(tx)
		}
		if e := initializeDispatch(tx, id, "ensure"); e != nil {
			return e
		}
		return guardDispatch(tx)
	})
}

func (s *Store) appendDispatchEvent(tx *bolt.Tx, kind, intentID, at string, detail any) error {
	payload := map[string]any{
		"kind": kind, "intent_id": intentID, "recorded_at": at, "detail": detail,
	}
	raw, e := json.Marshal(payload)
	if e != nil {
		return e
	}
	key := fmt.Sprintf("%s/%s/%s", at, kind, intentID)
	b := tx.Bucket([]byte("dispatch_events"))
	if b.Get([]byte(key)) != nil {
		key = key + "/" + contract.Digest(raw)[:12]
	}
	return b.Put([]byte(key), raw)
}

func (s *Store) putIntent(tx *bolt.Tx, intent contract.DispatchIntent) error {
	if e := intent.Validate(); e != nil {
		return e
	}
	return putJSON(tx.Bucket([]byte("dispatch_intents")), intent.ID, intent)
}

func (s *Store) loadIntent(tx *bolt.Tx, id string) (contract.DispatchIntent, error) {
	var intent contract.DispatchIntent
	raw := tx.Bucket([]byte("dispatch_intents")).Get([]byte(id))
	if raw == nil {
		return intent, errors.New("unknown dispatch intent")
	}
	if e := contract.StrictJSON(raw, &intent); e != nil {
		return intent, e
	}
	return intent, nil
}

// CommitIntent durably records reservation + dispatch intent BEFORE any native send.
func (s *Store) CommitIntent(intent contract.DispatchIntent) (contract.DispatchIntent, error) {
	if intent.Status == "" {
		intent.Status = contract.IntentCommitted
	}
	if intent.Outcome == "" {
		intent.Outcome = contract.OutcomeUnknown
	}
	if intent.Cancel.State == "" {
		intent.Cancel.State = contract.CancelNone
	}
	err := s.db.Update(func(tx *bolt.Tx) error {
		if e := s.dispatchReady(tx); e != nil {
			return e
		}
		if tx.Bucket([]byte("roots")).Get([]byte(intent.RootID)) == nil {
			return errors.New("unknown root for dispatch intent")
		}
		b := tx.Bucket([]byte("dispatch_intents"))
		if prev := b.Get([]byte(intent.ID)); prev != nil {
			var existing contract.DispatchIntent
			if e := contract.StrictJSON(prev, &existing); e != nil {
				return e
			}
			intent = existing
			return nil
		}
		ops := tx.Bucket([]byte("dispatch_ops"))
		if intent.OperationID != "" {
			if prev := ops.Get([]byte(intent.OperationID)); prev != nil {
				var existingID string
				if e := contract.StrictJSON(prev, &existingID); e != nil {
					return e
				}
				if existingID != intent.ID {
					return errors.New("operation identity already bound to different intent")
				}
			}
			if e := putJSON(ops, intent.OperationID, intent.ID); e != nil {
				return e
			}
		}
		if intent.IdempotencyKey != "" {
			key := "idem:" + intent.IdempotencyKey
			if prev := ops.Get([]byte(key)); prev != nil {
				var existingID string
				if e := contract.StrictJSON(prev, &existingID); e != nil {
					return e
				}
				if existingID != intent.ID {
					// Same key maps to existing intent — return it (no duplicate effect).
					existing, e := s.loadIntent(tx, existingID)
					if e != nil {
						return e
					}
					intent = existing
					return nil
				}
			} else if e := putJSON(ops, key, intent.ID); e != nil {
				return e
			}
		}
		if e := s.putIntent(tx, intent); e != nil {
			return e
		}
		return s.appendDispatchEvent(tx, "intent_committed", intent.ID, intent.CommittedAt, map[string]string{
			"operation_id": intent.OperationID, "reservation_id": intent.ReservationID,
		})
	})
	return intent, err
}

// MarkIntentSent records that a native send was attempted after durable commit.
func (s *Store) MarkIntentSent(intentID, sentAt string) (contract.DispatchIntent, error) {
	var out contract.DispatchIntent
	err := s.db.Update(func(tx *bolt.Tx) error {
		if e := s.dispatchReady(tx); e != nil {
			return e
		}
		intent, e := s.loadIntent(tx, intentID)
		if e != nil {
			return e
		}
		switch intent.Status {
		case contract.IntentCommitted, contract.IntentSent, contract.IntentUncertain:
		default:
			return fmt.Errorf("cannot mark sent from status %s", intent.Status)
		}
		intent.Status = contract.IntentSent
		intent.SentAt = sentAt
		intent.Outcome = contract.OutcomeRunning
		if e = s.putIntent(tx, intent); e != nil {
			return e
		}
		if e = s.appendDispatchEvent(tx, "intent_sent", intentID, sentAt, nil); e != nil {
			return e
		}
		out = intent
		return nil
	})
	return out, err
}

// MarkIntentUncertain retains uncertain exposure after ambiguous send (coordinates with reservation).
func (s *Store) MarkIntentUncertain(intentID, at, detail string) (contract.DispatchIntent, error) {
	var out contract.DispatchIntent
	err := s.db.Update(func(tx *bolt.Tx) error {
		if e := s.dispatchReady(tx); e != nil {
			return e
		}
		intent, e := s.loadIntent(tx, intentID)
		if e != nil {
			return e
		}
		intent.Status = contract.IntentUncertain
		intent.Outcome = contract.OutcomeUnknown
		if e = s.putIntent(tx, intent); e != nil {
			return e
		}
		if e = s.appendDispatchEvent(tx, "intent_uncertain", intentID, at, detail); e != nil {
			return e
		}
		out = intent
		return nil
	})
	return out, err
}

// RecordAck persists observed acknowledgement AFTER native send.
func (s *Store) RecordAck(intentID string, ack contract.DispatchAck) (contract.DispatchIntent, error) {
	if e := ack.Validate(); e != nil {
		return contract.DispatchIntent{}, e
	}
	var out contract.DispatchIntent
	err := s.db.Update(func(tx *bolt.Tx) error {
		if e := s.dispatchReady(tx); e != nil {
			return e
		}
		intent, e := s.loadIntent(tx, intentID)
		if e != nil {
			return e
		}
		if intent.Status != contract.IntentSent && intent.Status != contract.IntentUncertain && intent.Status != contract.IntentAcked {
			return fmt.Errorf("cannot ack from status %s", intent.Status)
		}
		// Transport terminal alone never sets acceptance.
		if ack.TransportState == contract.OutcomeTransportTerminal {
			ack.Accepted = false
		}
		intent.Ack = &ack
		intent.AckedAt = ack.ObservedAt
		intent.Status = contract.IntentAcked
		intent.Outcome = ack.TransportState
		if e = putJSON(tx.Bucket([]byte("dispatch_acks")), intentID, ack); e != nil {
			return e
		}
		if e = s.putIntent(tx, intent); e != nil {
			return e
		}
		if e = s.appendDispatchEvent(tx, "intent_acked", intentID, ack.ObservedAt, ack); e != nil {
			return e
		}
		out = intent
		return nil
	})
	return out, err
}

// RecordEvent appends a native event with requested vs observed separation.
func (s *Store) RecordEvent(ev contract.NativeEvent) (contract.NativeEvent, error) {
	if e := ev.Validate(); e != nil {
		return ev, e
	}
	err := s.db.Update(func(tx *bolt.Tx) error {
		if e := s.dispatchReady(tx); e != nil {
			return e
		}
		intent, e := s.loadIntent(tx, ev.IntentID)
		if e != nil {
			return e
		}
		b := tx.Bucket([]byte("dispatch_events"))
		if prev := b.Get([]byte("native/" + ev.ID)); prev != nil {
			var existing contract.NativeEvent
			if e := contract.StrictJSON(prev, &existing); e != nil {
				return e
			}
			ev = existing
			return nil
		}
		if e = putJSON(b, "native/"+ev.ID, ev); e != nil {
			return e
		}
		// Update observed settings on intent without overwriting requested.
		if ev.Observed.Model != "" || ev.Observed.Effort != "" || ev.Observed.Method != "" {
			intent.Observed = ev.Observed
		}
		if ev.TransportTerminal {
			intent.Outcome = contract.OutcomeTransportTerminal
		}
		if e = s.putIntent(tx, intent); e != nil {
			return e
		}
		return s.appendDispatchEvent(tx, "native_event", ev.IntentID, ev.RecordedAt, map[string]any{
			"event_id": ev.ID, "kind": ev.Kind, "duplicate_of": ev.DuplicateOf,
			"child_usage_gap": ev.ChildUsageGap, "terminal_error": ev.TerminalError,
		})
	})
	return ev, err
}

// CancelRequest marks cancellation requested (nonterminal until native outcome).
func (s *Store) CancelRequest(intentID, at string) (contract.DispatchIntent, error) {
	var out contract.DispatchIntent
	err := s.db.Update(func(tx *bolt.Tx) error {
		if e := s.dispatchReady(tx); e != nil {
			return e
		}
		intent, e := s.loadIntent(tx, intentID)
		if e != nil {
			return e
		}
		if intent.Cancel.IsTerminal() {
			out = intent
			return nil
		}
		intent.Cancel.State = contract.CancelRequested
		intent.Cancel.RequestedAt = at
		if e = s.putIntent(tx, intent); e != nil {
			return e
		}
		if e = s.appendDispatchEvent(tx, "cancel_requested", intentID, at, nil); e != nil {
			return e
		}
		out = intent
		return nil
	})
	return out, err
}

// RecordInterruptAccepted notes host accepted interrupt while process may still be alive.
func (s *Store) RecordInterruptAccepted(intentID, at string, processAlive, ackMissing, usageDelayed bool) (contract.DispatchIntent, error) {
	var out contract.DispatchIntent
	err := s.db.Update(func(tx *bolt.Tx) error {
		if e := s.dispatchReady(tx); e != nil {
			return e
		}
		intent, e := s.loadIntent(tx, intentID)
		if e != nil {
			return e
		}
		intent.Cancel.State = contract.CancelInterruptAccepted
		intent.Cancel.InterruptAckAt = at
		intent.Cancel.ProcessAlive = processAlive
		intent.Cancel.AckMissing = ackMissing
		intent.Cancel.UsageDelayed = usageDelayed
		if e = s.putIntent(tx, intent); e != nil {
			return e
		}
		if e = s.appendDispatchEvent(tx, "cancel_interrupt_accepted", intentID, at, map[string]any{
			"process_alive": processAlive, "ack_missing": ackMissing, "usage_delayed": usageDelayed,
		}); e != nil {
			return e
		}
		out = intent
		return nil
	})
	return out, err
}

// ConfirmCancelStopped marks confirmed native stop (still distinct from final reconciliation).
func (s *Store) ConfirmCancelStopped(intentID, at string) (contract.DispatchIntent, error) {
	var out contract.DispatchIntent
	err := s.db.Update(func(tx *bolt.Tx) error {
		if e := s.dispatchReady(tx); e != nil {
			return e
		}
		intent, e := s.loadIntent(tx, intentID)
		if e != nil {
			return e
		}
		intent.Cancel.State = contract.CancelConfirmedStopped
		intent.Cancel.ConfirmedStopAt = at
		intent.Cancel.ProcessAlive = false
		intent.Outcome = contract.OutcomeStopped
		if e = s.putIntent(tx, intent); e != nil {
			return e
		}
		if e = s.appendDispatchEvent(tx, "cancel_confirmed_stopped", intentID, at, nil); e != nil {
			return e
		}
		out = intent
		return nil
	})
	return out, err
}

// ReconcileIntent settles ambiguous outcomes; does not auto-redispatch.
func (s *Store) ReconcileIntent(intentID, at, status, detail string, report *contract.ReconstructionReport) (contract.DispatchIntent, error) {
	var out contract.DispatchIntent
	err := s.db.Update(func(tx *bolt.Tx) error {
		if e := s.dispatchReady(tx); e != nil {
			return e
		}
		intent, e := s.loadIntent(tx, intentID)
		if e != nil {
			return e
		}
		switch status {
		case contract.ReconcileResolved:
			intent.Status = contract.IntentReconciled
			intent.ReconciledAt = at
			if intent.Cancel.State == contract.CancelConfirmedStopped {
				intent.Cancel.State = contract.CancelFinalReconciled
				intent.Cancel.FinalReconciledAt = at
			}
		case contract.ReconcileUnresolved, contract.ReconcileUnsupported:
			intent.Status = contract.IntentUncertain
			intent.Outcome = contract.OutcomeUnknown
		default:
			return errors.New("unknown reconcile status")
		}
		if report != nil {
			if e := report.Validate(); e != nil {
				return e
			}
			intent.Reconstruction = report
		}
		if e = s.putIntent(tx, intent); e != nil {
			return e
		}
		if e = s.appendDispatchEvent(tx, "intent_reconciled", intentID, at, map[string]any{
			"status": status, "detail": detail,
		}); e != nil {
			return e
		}
		out = intent
		return nil
	})
	return out, err
}

// SetReconstruction attaches a reconstruction report without claiming native continuity.
func (s *Store) SetReconstruction(intentID string, report contract.ReconstructionReport) (contract.DispatchIntent, error) {
	if e := report.Validate(); e != nil {
		return contract.DispatchIntent{}, e
	}
	var out contract.DispatchIntent
	err := s.db.Update(func(tx *bolt.Tx) error {
		if e := s.dispatchReady(tx); e != nil {
			return e
		}
		intent, e := s.loadIntent(tx, intentID)
		if e != nil {
			return e
		}
		intent.Reconstruction = &report
		if e = s.putIntent(tx, intent); e != nil {
			return e
		}
		out = intent
		return nil
	})
	return out, err
}

// LookupByOperationID resolves an intent by stable operation identity.
func (s *Store) LookupByOperationID(operationID string) (contract.DispatchIntent, error) {
	var out contract.DispatchIntent
	err := s.db.View(func(tx *bolt.Tx) error {
		if e := s.dispatchReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("dispatch_ops")).Get([]byte(operationID))
		if raw == nil {
			return errors.New("unknown operation identity")
		}
		var intentID string
		if e := contract.StrictJSON(raw, &intentID); e != nil {
			return e
		}
		intent, e := s.loadIntent(tx, intentID)
		if e != nil {
			return e
		}
		out = intent
		return nil
	})
	return out, err
}

// LookupByIdempotencyKey resolves an intent by idempotency key when supported.
func (s *Store) LookupByIdempotencyKey(key string) (contract.DispatchIntent, error) {
	var out contract.DispatchIntent
	err := s.db.View(func(tx *bolt.Tx) error {
		if e := s.dispatchReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("dispatch_ops")).Get([]byte("idem:" + key))
		if raw == nil {
			return errors.New("unknown idempotency key")
		}
		var intentID string
		if e := contract.StrictJSON(raw, &intentID); e != nil {
			return e
		}
		intent, e := s.loadIntent(tx, intentID)
		if e != nil {
			return e
		}
		out = intent
		return nil
	})
	return out, err
}

// GetIntent returns a durable dispatch intent.
func (s *Store) GetIntent(intentID string) (contract.DispatchIntent, error) {
	var out contract.DispatchIntent
	err := s.db.View(func(tx *bolt.Tx) error {
		if e := s.dispatchReady(tx); e != nil {
			return e
		}
		intent, e := s.loadIntent(tx, intentID)
		if e != nil {
			return e
		}
		out = intent
		return nil
	})
	return out, err
}

// ListIntents returns dispatch intents for a root (or all when rootID empty).
func (s *Store) ListIntents(rootID string) ([]contract.DispatchIntent, error) {
	var out []contract.DispatchIntent
	err := s.db.View(func(tx *bolt.Tx) error {
		if e := s.dispatchReady(tx); e != nil {
			return e
		}
		return tx.Bucket([]byte("dispatch_intents")).ForEach(func(k, v []byte) error {
			if v == nil {
				return nil
			}
			var intent contract.DispatchIntent
			if e := contract.StrictJSON(v, &intent); e != nil {
				return e
			}
			if rootID != "" && intent.RootID != rootID {
				return nil
			}
			out = append(out, intent)
			return nil
		})
	})
	return out, err
}

// ListNativeEvents returns recorded native events for an intent.
func (s *Store) ListNativeEvents(intentID string) ([]contract.NativeEvent, error) {
	var out []contract.NativeEvent
	err := s.db.View(func(tx *bolt.Tx) error {
		if e := s.dispatchReady(tx); e != nil {
			return e
		}
		return tx.Bucket([]byte("dispatch_events")).ForEach(func(k, v []byte) error {
			if v == nil {
				return nil
			}
			key := string(k)
			if len(key) < 7 || key[:7] != "native/" {
				return nil
			}
			var ev contract.NativeEvent
			if e := contract.StrictJSON(v, &ev); e != nil {
				return e
			}
			if intentID != "" && ev.IntentID != intentID {
				return nil
			}
			out = append(out, ev)
			return nil
		})
	})
	return out, err
}
