package internal

import (
	"context"
	"encoding/json"
	"errors"
	"regexp"
)

// handleSegmentMatch drains kind='segment_match' (issue #1313 Phase 1,
// decisions § 2392): score a run's stored track against the catalogue
// segments near it, or one batch of a launch backfill.
//
// The scoring itself is not here. The matcher is a TS<->Dart parity pair
// whose TS half is apps/web/src/lib/segments/segments.ts; a Go port would be
// a third implementation for the pair to drift from. So the worker keeps what
// it is for — claiming, retrying, failing — and hands the payload to the
// `segment-match` Edge Function, which runs that module bundled. The
// function answers 2xx for done, 5xx for retry, 4xx for a payload it will
// never accept, and InvokeSegmentMatch surfaces the status as an *HTTPError
// so the generic classifier in handle() makes the same call.
//
// The payload is checked here first so a malformed row fails without a
// network round trip: exactly one of run_id or segment_id, each a lower-case
// UUID, and after_run_id only beside segment_id.
func (w *Worker) handleSegmentMatch(ctx context.Context, job *Job) error {
	if err := validateSegmentMatchPayload(job.Payload); err != nil {
		return err
	}
	return w.Backend.InvokeSegmentMatch(ctx, job.Payload)
}

var reLowerUUID = regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`)

// SegmentMatchPayload is the queue's two shapes: {run_id} or
// {segment_id, after_run_id?}.
type SegmentMatchPayload struct {
	RunID      *string `json:"run_id"`
	SegmentID  *string `json:"segment_id"`
	AfterRunID *string `json:"after_run_id"`
}

func validateSegmentMatchPayload(raw json.RawMessage) error {
	var p SegmentMatchPayload
	if err := json.Unmarshal(raw, &p); err != nil {
		return errors.New("bad payload: not a JSON object")
	}
	isID := func(s *string) bool { return s != nil && reLowerUUID.MatchString(*s) }
	switch {
	case p.RunID != nil && p.SegmentID == nil && p.AfterRunID == nil:
		if !isID(p.RunID) {
			return errors.New("bad payload: run_id is not a uuid")
		}
	case p.SegmentID != nil && p.RunID == nil:
		if !isID(p.SegmentID) {
			return errors.New("bad payload: segment_id is not a uuid")
		}
		if p.AfterRunID != nil && !isID(p.AfterRunID) {
			return errors.New("bad payload: after_run_id is not a uuid")
		}
	default:
		return errors.New("bad payload: need exactly one of run_id or segment_id")
	}
	return nil
}
