package internal

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
	"strings"
)

// ClubVerificationEmailPayload is the payload for `kind='club_verification_email'`
// jobs (migration 20271120000004, decisions § 2398): the email proof of a club
// verification request. The recipient is an address at the club's claimed
// domain and need not be a user, so the address, the submitter's locale and the
// copy's facts all travel in the payload. The token is the plaintext of the
// single-use confirm link; the database keeps only its SHA-256.
type ClubVerificationEmailPayload struct {
	Email        string `json:"email"`
	Locale       string `json:"locale"`
	ClubName     string `json:"club_name"`
	Organisation string `json:"organisation"`
	Domain       string `json:"domain"`
	Token        string `json:"token"`
}

var clubVerificationTokenRe = regexp.MustCompile(`^[0-9a-f]{48}$`)

// handleClubVerificationEmail sends the confirm link. Transactional and
// requested by the club owner for this one address, so no preference gates it;
// send_club_verification_email caps it at three a request a day. Delivery is
// at-least-once like the other transactional kinds: a retry after a send whose
// finish failed sends the same link twice, which confirms the same request.
//
// No SMTP sender configured → the job finishes done without sending. A payload
// missing its address or carrying a malformed token is a permanent skip, not a
// retry loop.
func (w *Worker) handleClubVerificationEmail(ctx context.Context, job *Job) error {
	if w.Email == nil {
		w.Log.Info("club_verification_email: sender not configured; skipping")
		return nil
	}
	var p ClubVerificationEmailPayload
	if err := json.Unmarshal(job.Payload, &p); err != nil {
		return fmt.Errorf("bad payload: %w", err)
	}
	msg, err := renderClubVerificationEmail(p, w.AppBaseURL)
	if err != nil {
		w.Log.Warn("club_verification_email: unusable payload; skipping", "error", err.Error())
		return nil
	}
	if err := w.Email.Send(ctx, strings.TrimSpace(p.Email), msg); err != nil {
		return fmt.Errorf("send: %w", err)
	}
	w.Log.Info("club_verification_email: sent", "domain", p.Domain)
	return nil
}

// renderClubVerificationEmail builds the message. The club name and the
// organisation are the club owner's own text, so they are stripped of control
// characters here and HTML-escaped by composeEmail, and neither reaches the
// subject. The link carries the token in the fragment, so it never reaches a
// server log.
func renderClubVerificationEmail(p ClubVerificationEmailPayload, baseURL string) (Email, error) {
	if strings.TrimSpace(p.Email) == "" || strings.TrimSpace(p.Domain) == "" {
		return Email{}, errors.New("payload missing email or domain")
	}
	if !clubVerificationTokenRe.MatchString(p.Token) {
		return Email{}, errors.New("payload token is malformed")
	}
	base := strings.TrimRight(baseURL, "/")
	loc := normalizeEmailLocale(p.Locale)
	s := lookupEmailStrings(loc, "club_verification_email")
	shared := lookupEmailShared(loc)
	club := sanitizeHeaderValue(strings.TrimSpace(p.ClubName))
	org := sanitizeHeaderValue(strings.TrimSpace(p.Organisation))
	domain := sanitizeHeaderValue(strings.TrimSpace(p.Domain))

	return composeEmail(emailContent{
		logoURL:   emailLogoURL(baseURL),
		lang:      loc,
		subject:   s.subject,
		preheader: s.preheader,
		heading:   s.heading,
		body: []string{
			fmt.Sprintf(s.body[0], club, org, domain),
			s.body[1],
			s.body[2],
		},
		ctaLabel: s.cta,
		ctaURL:   base + "/club-verification/confirm#token=" + p.Token,
		footer:   shared.footerClubVerification,
	}), nil
}
