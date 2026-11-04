package internal

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/Absence0760/threkir/apps/job_worker/internal/schema"
)

// The route-photo orphan sweep (kind='route_photo_orphan_sweep', migration
// 20271106000020, decisions § 2305).
//
// Deleting a route takes its `route_photos` rows by cascade, and after that
// nothing references the bytes in the `route-photos` bucket. A client sweep
// that never ran, or a club admin deleting a route someone else uploaded
// photos to, left those bytes behind until account deletion.
//
// The SQL tier decides WHAT is orphaned (`route_photo_orphan_paths`, which
// knows the rows, the placeholder-upload window and the 24-hour grace) and
// this handler erases through the Storage API, because a `storage.objects`
// row delete leaves the bytes on the backend (decisions § 1049). The worklist
// is re-read after every batch rather than handed over once: an erased object
// leaves `storage.objects`, so a retry or the next night cannot repeat work,
// and a photo re-referenced between batches is never touched.

const (
	// RoutePhotoOrphanBatchSize is the worklist page and the DELETE body size.
	RoutePhotoOrphanBatchSize = 100
	// RoutePhotoOrphanMaxBatches bounds one run. A backlog larger than
	// batches x size is finished by the next night's backstop, so one job
	// cannot hold a worker for an unbounded time. The delete trigger's
	// paths-per-job cap must fit inside it (MigrationCapFitsOneRun).
	RoutePhotoOrphanMaxBatches = 20
)

// RoutePhotoOrphanSweepPayload is what the enqueues write. No paths is the
// nightly backstop; paths is the prompt sweep the route_photos AFTER DELETE
// trigger queues.
type RoutePhotoOrphanSweepPayload struct {
	Paths []string `json:"paths"`
}

// RoutePhotoOrphanSweepResult reports what one run did, as counts only.
type RoutePhotoOrphanSweepResult struct {
	Batches   int
	Deleted   int
	Exhausted bool
}

func (w *Worker) handleRoutePhotoOrphanSweep(ctx context.Context, job *Job) error {
	var p RoutePhotoOrphanSweepPayload
	if len(job.Payload) > 0 {
		if err := json.Unmarshal(job.Payload, &p); err != nil {
			return fmt.Errorf("route_photo_orphan_sweep: bad payload: %w", err)
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

	res, err := w.sweepRoutePhotoOrphans(ctx, p.Paths)
	// Counts only. The paths are `{user_id}/{photo_id}` and do not belong in
	// a log line (/audit/pii-in-logs).
	w.Log.Info("route photo orphan sweep",
		"mode", mode,
		"batches", res.Batches,
		"deleted", res.Deleted,
		"more_remaining", res.Exhausted)
	return err
}

func (w *Worker) sweepRoutePhotoOrphans(ctx context.Context, paths []string) (RoutePhotoOrphanSweepResult, error) {
	var res RoutePhotoOrphanSweepResult
	erased := make(map[string]struct{})
	for res.Batches < RoutePhotoOrphanMaxBatches {
		batch, err := w.Backend.RoutePhotoOrphanPaths(ctx, paths, RoutePhotoOrphanBatchSize)
		if err != nil {
			return res, fmt.Errorf("route_photo_orphan_sweep: worklist (%d already erased): %w", res.Deleted, err)
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
				return res, fmt.Errorf("route_photo_orphan_sweep: storage did not erase an object it accepted (%d already erased)", res.Deleted)
			}
		}
		res.Batches++
		if err := w.Backend.DeleteStorageObjects(ctx, schema.BucketRoutePhotos, batch); err != nil {
			return res, fmt.Errorf("route_photo_orphan_sweep: delete %d object(s) (%d already erased): %w", len(batch), res.Deleted, err)
		}
		for _, path := range batch {
			erased[path] = struct{}{}
		}
		res.Deleted += len(batch)
		if len(batch) < RoutePhotoOrphanBatchSize {
			return res, nil
		}
	}
	res.Exhausted = true
	return res, nil
}
