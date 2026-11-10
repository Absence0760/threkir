package internal

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/Absence0760/threkir/apps/job_worker/internal/schema"
)

// The direct-message image orphan sweep (kind='dm_image_orphan_sweep',
// migration 20271213121604, issue #1216). The route-photo sweep's shape
// against the dm-images bucket.
//
// Deleting a direct_message_images row (a release after unsend or a purge,
// a report's retention ending, an upload never sent) leaves its two objects,
// the upload and the re-encode, referenced by nothing. The SQL tier decides
// WHAT is orphaned (`dm_image_orphan_paths` never returns an object a row
// names, so an image a report holds is never touched) and this handler
// erases through the Storage API, because a `storage.objects` row delete
// leaves the bytes on the backend (decisions § 1049). There is no flag gate
// here: with the feature off no row exists and the worklist is empty. The
// worklist is re-read after every batch, as in the route-photo sweep.

const (
	// DmImageOrphanBatchSize is the worklist page and the DELETE body size.
	DmImageOrphanBatchSize = 100
	// DmImageOrphanMaxBatches bounds one run. A backlog larger than
	// batches x size is finished by the next night's backstop, so one job
	// cannot hold a worker for an unbounded time. The delete trigger's
	// paths-per-job chunk must fit inside it (MigrationChunkFitsOneRun).
	DmImageOrphanMaxBatches = 20
)

// DmImageOrphanSweepPayload is what the enqueues write. No paths is the
// nightly backstop; paths is the prompt sweep the direct_message_images
// AFTER DELETE trigger queues.
type DmImageOrphanSweepPayload struct {
	Paths []string `json:"paths"`
}

// DmImageOrphanSweepResult reports what one run did, as counts only.
type DmImageOrphanSweepResult struct {
	Batches   int
	Deleted   int
	Exhausted bool
}

func (w *Worker) handleDmImageOrphanSweep(ctx context.Context, job *Job) error {
	var p DmImageOrphanSweepPayload
	if len(job.Payload) > 0 {
		if err := json.Unmarshal(job.Payload, &p); err != nil {
			return fmt.Errorf("dm_image_orphan_sweep: bad payload: %w", err)
		}
	}
	// A paths payload that decoded to an empty list is a trigger that found
	// nothing, not a request for the backstop: reading it as nil would turn
	// a prompt sweep into an unscoped one.
	mode := "backstop"
	if p.Paths != nil {
		mode = "paths"
		if len(p.Paths) == 0 {
			return nil
		}
	}

	res, err := w.sweepDmImageOrphans(ctx, p.Paths)
	// Counts only. The paths are `{owner}/{image}...` and do not belong in a
	// log line (/audit/pii-in-logs).
	w.Log.Info("dm image orphan sweep",
		"mode", mode,
		"batches", res.Batches,
		"deleted", res.Deleted,
		"more_remaining", res.Exhausted)
	return err
}

func (w *Worker) sweepDmImageOrphans(ctx context.Context, paths []string) (DmImageOrphanSweepResult, error) {
	var res DmImageOrphanSweepResult
	erased := make(map[string]struct{})
	for res.Batches < DmImageOrphanMaxBatches {
		batch, err := w.Backend.DmImageOrphanPaths(ctx, paths, DmImageOrphanBatchSize)
		if err != nil {
			return res, fmt.Errorf("dm_image_orphan_sweep: worklist (%d already erased): %w", res.Deleted, err)
		}
		if len(batch) == 0 {
			return res, nil
		}
		// A path this run already sent to DELETE that the worklist still
		// reports was not erased: the API accepted a name that matched no
		// object, or refused it silently. Looping on it would spin to the
		// batch bound and report success, so fail and let the job retry.
		for _, path := range batch {
			if _, seen := erased[path]; seen {
				return res, fmt.Errorf("dm_image_orphan_sweep: storage did not erase an object it accepted (%d already erased)", res.Deleted)
			}
		}
		res.Batches++
		if err := w.Backend.DeleteStorageObjects(ctx, schema.BucketDmImages, batch); err != nil {
			return res, fmt.Errorf("dm_image_orphan_sweep: delete %d object(s) (%d already erased): %w", len(batch), res.Deleted, err)
		}
		for _, path := range batch {
			erased[path] = struct{}{}
		}
		res.Deleted += len(batch)
		if len(batch) < DmImageOrphanBatchSize {
			return res, nil
		}
	}
	res.Exhausted = true
	return res, nil
}
