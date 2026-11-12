package internal

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
)

// newDeviceAlertsPrefKey is the opt-OUT universal setting that silences the
// new-device sign-in alert (docs/backend/settings.md). Only the literal "off"
// mutes it: an absent key is an account that never chose, and a corrupt one is
// not a decision to stop being told someone signed in.
const newDeviceAlertsPrefKey = "email_new_device_alerts"

// handleSecurityEmail drains a `security_email` job. Account-security mail is
// transactional — it goes out whatever `email_notifications` says, because
// muting social mail is not a choice to stop hearing that someone else is in
// your account — but the new-device alert, unlike the password-changed notice,
// has its own opt-out, read here at send time.
//
// The prefs read is NOT best-effort the way lifecycle mail's locale read is: it
// carries the opt-out, so a failed read retries the job rather than guessing
// in either direction. Delivery is at-least-once, like the recurring
// transactional templates; there is no send-once log, because each job is one
// sign-in.
//
// No SMTP sender configured → the job finishes done without sending, so the
// queue drains on a deploy without mail. An unknown template is a permanent
// skip rather than a retry loop.
func (w *Worker) handleSecurityEmail(ctx context.Context, job *Job) error {
	if w.Email == nil {
		w.Log.Info("security_email: sender not configured; skipping")
		return nil
	}

	var p SecurityEmailPayload
	if err := json.Unmarshal(job.Payload, &p); err != nil {
		return fmt.Errorf("bad payload: %w", err)
	}
	if p.UserID == "" || p.Template == "" {
		return errors.New("payload missing user_id or template")
	}
	if !securityTemplates[p.Template] {
		w.Log.Warn("security_email: unknown template; skipping", "template", p.Template)
		return nil
	}

	prefs, err := w.Backend.FetchUserSettingsPrefs(ctx, p.UserID)
	if err != nil {
		return fmt.Errorf("fetch prefs: %w", err)
	}
	if !securityEmailWanted(p.Template, prefs) {
		w.Log.Info("security_email: recipient opted out", "template", p.Template, "user_id", p.UserID)
		return nil
	}

	email, err := w.Backend.FetchUserEmail(ctx, p.UserID)
	if err != nil {
		return fmt.Errorf("fetch email: %w", err)
	}
	if email == "" {
		w.Log.Warn("security_email: recipient has no address", "user_id", p.UserID)
		return nil
	}

	msg, ok := renderSecurityEmail(p, w.AppBaseURL, localeFromPrefs(prefs))
	if !ok {
		return nil
	}
	if err := w.Email.Send(ctx, email, msg); err != nil {
		return fmt.Errorf("send: %w", err)
	}
	w.Log.Info("security_email: sent", "template", p.Template, "user_id", p.UserID)
	return nil
}

// securityEmailWanted applies a template's own opt-out, if it has one.
func securityEmailWanted(template string, prefs map[string]interface{}) bool {
	if template == "new_device_sign_in" {
		v, _ := prefs[newDeviceAlertsPrefKey].(string)
		return v != "off"
	}
	return true
}
