package internal

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"

	"github.com/Absence0760/threkir/apps/job_worker/internal/exif"
	"github.com/Absence0760/threkir/apps/job_worker/internal/schema"
)

const (
	// DmImageMaxBytes matches the dm-images bucket's file_size_limit.
	DmImageMaxBytes = 5 << 20
	// DmImageMaxLongSide is the direct_message_images size CHECK's bound.
	DmImageMaxLongSide = 2048
	// DmImageMaxPixels refuses a decompression bomb from its header alone.
	DmImageMaxPixels = 40_000_000
	// DmImageQuality is the re-encode's JPEG quality.
	DmImageQuality = 85
)

// DmImageProcessPayload is what the direct_messages_link_image trigger
// queues (migration 20271213121604).
type DmImageProcessPayload struct {
	ImageID string `json:"image_id"`
}

// handleDmImageProcess turns a direct-message photo upload into the only
// copy anyone reads (kind='dm_image_process', issue #1216):
//
//  1. Read the direct_message_images row. Gone, or no longer pending, is
//     done: a retry or a duplicate job after the row settled.
//  2. Download the upload and re-encode it with exif.ReencodeJPEG, which
//     keeps nothing of the file but its pixels.
//  3. Upload the result to storage_path, mark the row ready with its size,
//     and delete the upload.
//
// An upload that is missing, over the bucket's size limit or not a usable
// JPEG / PNG marks the row rejected and is deleted: retrying cannot change
// those bytes. Everything else returns its error so the job retries.
//
// Nothing here names a path or a user: an image path is `{owner}/{image}`.
func (w *Worker) handleDmImageProcess(ctx context.Context, job *Job) error {
	var p DmImageProcessPayload
	if err := json.Unmarshal(job.Payload, &p); err != nil {
		return fmt.Errorf("dm_image_process: bad payload: %w", err)
	}
	if !reLowerUUID.MatchString(p.ImageID) {
		return fmt.Errorf("dm_image_process: payload image_id is not a uuid")
	}

	img, err := w.Backend.FetchDmImage(ctx, p.ImageID)
	if err != nil {
		return fmt.Errorf("dm_image_process: read row: %w", err)
	}
	if img == nil || img.Status != "pending" {
		w.Log.Info("dm image process", "job_id", job.ID, "outcome", "skipped")
		return nil
	}

	body, err := w.Backend.DownloadDmImage(ctx, img.UploadPath, DmImageMaxBytes)
	if err != nil {
		if !dmImageUploadUnusable(err) {
			return fmt.Errorf("dm_image_process: download: %w", err)
		}
		return w.rejectDmImage(ctx, job, img, "unreadable")
	}

	out, width, height, err := exif.ReencodeJPEG(body, DmImageMaxLongSide, DmImageQuality, DmImageMaxPixels)
	if err != nil {
		return w.rejectDmImage(ctx, job, img, "undecodable")
	}

	if err := w.Backend.UploadDmImage(ctx, img.StoragePath, out); err != nil {
		return fmt.Errorf("dm_image_process: upload: %w", err)
	}
	if err := w.Backend.MarkDmImageReady(ctx, img.ID, width, height); err != nil {
		return fmt.Errorf("dm_image_process: mark ready: %w", err)
	}
	w.deleteDmImageUpload(ctx, job, img)
	w.Log.Info("dm image process", "job_id", job.ID, "outcome", "ready")
	return nil
}

// dmImageUploadUnusable reports whether a download failure is about the
// object rather than the transport: Storage answers 400 or 404 for an
// object that is not there.
func dmImageUploadUnusable(err error) bool {
	if errors.Is(err, ErrDmImageTooLarge) {
		return true
	}
	var hErr *HTTPError
	return errors.As(err, &hErr) &&
		(hErr.StatusCode == http.StatusBadRequest || hErr.StatusCode == http.StatusNotFound)
}

func (w *Worker) rejectDmImage(ctx context.Context, job *Job, img *DmImage, reason string) error {
	if err := w.Backend.MarkDmImageRejected(ctx, img.ID); err != nil {
		return fmt.Errorf("dm_image_process: mark rejected: %w", err)
	}
	w.deleteDmImageUpload(ctx, job, img)
	w.Log.Info("dm image process", "job_id", job.ID, "outcome", "rejected", "reason", reason)
	return nil
}

// deleteDmImageUpload logs rather than returns a failure: the row is already
// settled, so a retry would skip it, and once no pending row names the upload
// the nightly dm_image_orphan_sweep backstop erases it.
func (w *Worker) deleteDmImageUpload(ctx context.Context, job *Job, img *DmImage) {
	if err := w.Backend.DeleteStorageObjects(ctx, schema.BucketDmImages, []string{img.UploadPath}); err != nil {
		w.Log.Warn("dm image upload delete failed; left to the backstop sweep", "job_id", job.ID)
	}
}
