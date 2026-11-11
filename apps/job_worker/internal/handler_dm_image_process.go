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
	// DmImageMaxPixels refuses a decompression bomb from its header alone. Both
	// clients upload at most 2048 x 2048 (4.2 MP); twice that bounds a decode
	// to roughly 35 MB even at 4:4:4, inside the worker's 256 MB machine,
	// where 40 MP measured over 300 MB.
	DmImageMaxPixels = 2 * 2048 * 2048
	// DmImageQuality is the re-encode's JPEG quality.
	DmImageQuality = 85
)

// reencodeDmImage is a variable so a test can stand in a re-encoder that
// panics.
var reencodeDmImage = exif.ReencodeJPEG

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

	out, width, height, err := reencodeSafely(body)
	if err != nil {
		return w.rejectDmImage(ctx, job, img, "undecodable")
	}

	if err := w.Backend.UploadDmImage(ctx, img.StoragePath, out); err != nil {
		return fmt.Errorf("dm_image_process: upload: %w", err)
	}
	matched, err := w.Backend.MarkDmImageReady(ctx, img.ID, width, height)
	if err != nil {
		return fmt.Errorf("dm_image_process: mark ready: %w", err)
	}
	if !matched {
		return w.settleUnmatchedDmImage(ctx, job, img)
	}
	w.deleteDmImageUpload(ctx, job, img)
	w.Log.Info("dm image process", "job_id", job.ID, "outcome", "ready")
	return nil
}

// settleUnmatchedDmImage handles a MarkDmImageReady that matched no pending
// row, which means either the row went (an unsend, a purge) or another
// attempt of this job settled it first (a lease that expired mid re-encode).
// Only the first may erase: its delete sweep may already have passed, so the
// object just written would otherwise wait for the 24-hour backstop. A row
// that still exists names storage_path, and a ready one serves it.
func (w *Worker) settleUnmatchedDmImage(ctx context.Context, job *Job, img *DmImage) error {
	current, err := w.Backend.FetchDmImage(ctx, img.ID)
	if err != nil {
		return fmt.Errorf("dm_image_process: re-read row: %w", err)
	}
	if current != nil {
		// Settled by another attempt: its paths are that row's to keep.
		w.Log.Info("dm image process", "job_id", job.ID, "outcome", "settled_elsewhere")
		return nil
	}
	if err := w.Backend.DeleteStorageObjects(ctx, schema.BucketDmImages, []string{img.StoragePath, img.UploadPath}); err != nil {
		return fmt.Errorf("dm_image_process: erase after the row went: %w", err)
	}
	w.Log.Info("dm image process", "job_id", job.ID, "outcome", "row_gone")
	return nil
}

// reencodeSafely turns a decoder panic into an error, so the row is marked
// rejected instead of staying pending forever.
func reencodeSafely(body []byte) (out []byte, width, height int, err error) {
	defer func() {
		if r := recover(); r != nil {
			out, width, height, err = nil, 0, 0, fmt.Errorf("dm_image_process: re-encode panicked")
		}
	}()
	return reencodeDmImage(body, DmImageMaxLongSide, DmImageQuality, DmImageMaxPixels)
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
	if _, err := w.Backend.MarkDmImageRejected(ctx, img.ID); err != nil {
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
