package internal

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"

	"github.com/Absence0760/threkir/apps/job_worker/internal/nativepush"
)

// handleNativePush drains a `native_push` job: load the referenced
// notification, decide whether the recipient wants this category by push, load
// their registered device tokens, and send one FCM push to each — Android and
// iOS alike, since internal/nativepush delivers Apple through FCM too.
// Enqueued one-per-row by the notifications AFTER INSERT trigger (migration
// 20270212_001) — the THIRD sibling consumer of the same notifications row the
// in-app bell, the email channel, and the web-push channel read. This is the
// native (locked-phone) leg.
//
// Terminal-state discipline mirrors the web-push handler: every path that won't
// send (opted out, no token) stamps native_push_sent_at so the row is
// considered exactly once. The one exception is "sender not configured", which
// finishes the job done WITHOUT stamping so a later credentialed deploy can
// still send the still-pending rows.
//
// Delivery is at-least-once. A dead token (FCM UNREGISTERED 404) is pruned via
// clear_device_token and treated as handled. A transient failure
// (429/5xx/network) on any token returns an error so the queue retries the
// whole job; the Tag on the payload (notif-<id>) coalesces the re-send on the
// device so a duplicate replaces rather than stacks.
func (w *Worker) handleNativePush(ctx context.Context, job *Job) error {
	if w.NativePush == nil {
		// No FCM credentials configured. Finish done without stamping:
		// the notification stays pending so a later credentialed deploy can
		// send it (same posture as the web-push + email nil-sender branches).
		w.Log.Info("native_push: sender not configured; leaving row pending")
		return nil
	}

	var p NativePushPayload
	if err := json.Unmarshal(job.Payload, &p); err != nil {
		return fmt.Errorf("bad payload: %w", err)
	}
	if p.NotificationID == "" {
		return errors.New("payload missing notification_id")
	}

	n, err := w.Backend.FetchNotificationForNativePush(ctx, p.NotificationID)
	if err != nil {
		return fmt.Errorf("fetch notification: %w", err)
	}
	if n == nil {
		w.Log.Info("native_push: notification gone (inbox cleared)", "id", p.NotificationID)
		return nil
	}
	if n.NativePushSentAt != nil {
		// Already handled (re-enqueue or post-send retry). Idempotent.
		return nil
	}

	prefs, err := w.Backend.FetchUserSettingsPrefs(ctx, n.UserID)
	if err != nil {
		return fmt.Errorf("fetch prefs: %w", err)
	}
	if !shouldPush(n.Kind, prefs) {
		// Recipient opted this category out of the push channel. Terminal.
		// Same push_notifications pref the web-push channel gates on — one
		// "push" channel covers browser + native.
		return w.Backend.MarkNotificationNativePushed(ctx, n.ID)
	}

	tokens, err := w.Backend.FetchDeviceTokens(ctx, n.UserID)
	if err != nil {
		return fmt.Errorf("fetch device tokens: %w", err)
	}
	if len(tokens) == 0 {
		// No device registered for push. Terminal — nothing to send, and a
		// later registration shouldn't retro-deliver an old notification.
		return w.Backend.MarkNotificationNativePushed(ctx, n.ID)
	}

	msg := renderNativeMessage(*n, w.AppBaseURL, localeFromPrefs(prefs))

	var transient *HTTPError
	for _, tok := range tokens {
		status, sendErr := w.NativePush.Send(ctx, tok.Token, msg)
		switch {
		case sendErr != nil:
			// Transport failure (DNS, dial, reset) — retry the whole job.
			w.Log.Warn("native_push: transport error", "platform", tok.Platform, "err", sendErr)
			transient = &HTTPError{StatusCode: http.StatusServiceUnavailable, Body: sendErr.Error()}
		case nativepush.IsDeadToken(status):
			// The token is dead (app uninstalled / token rotated). Prune it so
			// it stops being retried for every future notification.
			// Best-effort — a failed prune isn't worth failing the job over.
			w.Log.Info("native_push: pruning dead token", "platform", tok.Platform, "status", status)
			if err := w.Backend.ClearDeviceToken(ctx, tok.Token); err != nil {
				w.Log.Warn("native_push: prune failed", "platform", tok.Platform, "err", err)
			}
		case nativepush.IsTransient(status):
			// Push service throttling or down — retry the whole job.
			w.Log.Warn("native_push: transient push-service status", "platform", tok.Platform, "status", status)
			transient = &HTTPError{StatusCode: status}
		case status >= 200 && status < 300:
			w.Log.Info("native_push: sent", "kind", n.Kind, "platform", tok.Platform, "status", status)
		default:
			// Other 4xx (400 bad payload, 403 bad auth) — permanent for this
			// token. Drop it from this send; don't fail the job.
			w.Log.Warn("native_push: permanent push-service status; dropping", "platform", tok.Platform, "status", status)
		}
	}

	if transient != nil {
		// At least one delivery should be retried. Don't stamp — the next
		// attempt re-sends (Tag coalesces on the device).
		return transient
	}
	if err := w.Backend.MarkNotificationNativePushed(ctx, n.ID); err != nil {
		return fmt.Errorf("mark sent: %w", err)
	}
	return nil
}
