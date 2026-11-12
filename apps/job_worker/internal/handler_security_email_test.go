package internal

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"
)

func securityJob(userID, browser, platform string) *Job {
	p, _ := json.Marshal(SecurityEmailPayload{
		UserID:     userID,
		Template:   "new_device_sign_in",
		Browser:    browser,
		Platform:   platform,
		SignedInAt: "2026-10-14T09:30:00Z",
	})
	return &Job{ID: 1, Kind: "security_email", Payload: p}
}

func TestSecurityEmail_NewDeviceSendsTheDeviceTheTimeAndAResetLink(t *testing.T) {
	be := &fakeBackend{userEmails: map[string]string{"u1": "runner@test.com"}}
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)

	if err := w.handleSecurityEmail(context.Background(), securityJob("u1", "firefox", "linux")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 1 {
		t.Fatalf("want 1 alert sent, got %d", len(sender.sent))
	}
	got := sender.sent[0]
	if got.to != "runner@test.com" {
		t.Errorf("wrong recipient %q", got.to)
	}
	if got.msg.Subject != "New sign-in to your Threkir account" {
		t.Errorf("unexpected subject %q", got.msg.Subject)
	}
	for _, want := range []string{"Firefox on Linux", "2026-10-14 09:30 UTC", "https://threkir.test/login?reset=1", "security@threkir.com"} {
		if !strings.Contains(got.msg.Body, want) {
			t.Errorf("text body is missing %q:\n%s", want, got.msg.Body)
		}
	}
	if !strings.Contains(got.msg.HTML, "https://threkir.test/login?reset=1") {
		t.Errorf("HTML part has no reset CTA")
	}
	if got.msg.ListUnsubscribe != "" {
		t.Errorf("a security notice is transactional and must carry no List-Unsubscribe, got %q", got.msg.ListUnsubscribe)
	}
}

func TestSecurityEmail_OptOutIsHonouredAndOnlyTheLiteralOffMutes(t *testing.T) {
	for _, tc := range []struct {
		pref     interface{}
		wantSent int
	}{
		{"off", 0},
		{"on", 1},
		{nil, 1},
		{false, 1},
		{"OFF", 1},
	} {
		prefs := map[string]interface{}{}
		if tc.pref != nil {
			prefs[newDeviceAlertsPrefKey] = tc.pref
		}
		be := &fakeBackend{
			userEmails: map[string]string{"u1": "runner@test.com"},
			userPrefs:  map[string]map[string]interface{}{"u1": prefs},
		}
		sender := &fakeEmailSender{}
		w := newEmailTestWorker(be, sender)
		if err := w.handleSecurityEmail(context.Background(), securityJob("u1", "chrome", "android")); err != nil {
			t.Fatalf("pref %v: handler: %v", tc.pref, err)
		}
		if len(sender.sent) != tc.wantSent {
			t.Errorf("pref %#v: want %d sent, got %d", tc.pref, tc.wantSent, len(sender.sent))
		}
	}
}

func TestSecurityEmail_IgnoresTheNotificationChannelMute(t *testing.T) {
	be := &fakeBackend{
		userEmails: map[string]string{"u1": "runner@test.com"},
		userPrefs:  map[string]map[string]interface{}{"u1": {"email_notifications": "off"}},
	}
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)
	if err := w.handleSecurityEmail(context.Background(), securityJob("u1", "safari", "ios")); err != nil {
		t.Fatalf("handler: %v", err)
	}
	if len(sender.sent) != 1 {
		t.Fatalf("muting social mail must not mute a security notice; got %d sent", len(sender.sent))
	}
}

func TestSecurityEmail_PrefsReadFailureRetriesRatherThanGuessing(t *testing.T) {
	be := &fakeBackend{
		userEmails:    map[string]string{"u1": "runner@test.com"},
		fetchPrefsErr: errors.New("upstream 503"),
	}
	sender := &fakeEmailSender{}
	w := newEmailTestWorker(be, sender)
	if err := w.handleSecurityEmail(context.Background(), securityJob("u1", "edge", "windows")); err == nil {
		t.Fatal("a failed prefs read carries the opt-out and must retry, not send or drop")
	}
	if len(sender.sent) != 0 {
		t.Errorf("nothing may send on a failed prefs read, got %d", len(sender.sent))
	}
}

func TestSecurityEmail_SkipsWithoutSenderAddressOrKnownTemplate(t *testing.T) {
	be := &fakeBackend{userEmails: map[string]string{"u1": "runner@test.com"}}
	if err := newEmailTestWorker(be, nil).handleSecurityEmail(context.Background(), securityJob("u1", "firefox", "linux")); err != nil {
		t.Fatalf("nil sender should finish done, got %v", err)
	}

	sender := &fakeEmailSender{}
	w := newEmailTestWorker(&fakeBackend{userEmails: map[string]string{}}, sender)
	if err := w.handleSecurityEmail(context.Background(), securityJob("u1", "firefox", "linux")); err != nil {
		t.Fatalf("no address should finish done, got %v", err)
	}

	p, _ := json.Marshal(SecurityEmailPayload{UserID: "u1", Template: "not_a_template"})
	w = newEmailTestWorker(be, sender)
	if err := w.handleSecurityEmail(context.Background(), &Job{ID: 2, Kind: "security_email", Payload: p}); err != nil {
		t.Fatalf("unknown template is a permanent skip, got %v", err)
	}
	if len(sender.sent) != 0 {
		t.Errorf("none of the three may send, got %d", len(sender.sent))
	}

	if err := w.handleSecurityEmail(context.Background(), &Job{ID: 3, Kind: "security_email", Payload: []byte(`{"template":"new_device_sign_in"}`)}); err == nil {
		t.Error("a payload with no user_id must fail, not skip silently")
	}
}

func TestDeviceLabel_EveryClassReadsAsAPhrase(t *testing.T) {
	en := lookupEmailShared("en")
	for _, tc := range []struct{ browser, platform, want string }{
		{"firefox", "linux", "Firefox on Linux"},
		{"samsung", "android", "Samsung Internet on Android"},
		{"threkir_app", "other", "the Threkir app"},
		{"chrome", "other", "Chrome"},
		{"other", "windows", "an unrecognised browser on Windows"},
		{"other", "other", "an unrecognised device"},
		{"made_up", "made_up", "an unrecognised device"},
	} {
		if got := deviceLabel(tc.browser, tc.platform, en); got != tc.want {
			t.Errorf("deviceLabel(%q, %q) = %q, want %q", tc.browser, tc.platform, got, tc.want)
		}
	}
	if got := deviceLabel("firefox", "linux", lookupEmailShared("ja")); got != "Linux の Firefox" {
		t.Errorf("Japanese orders platform first via the indexed verbs, got %q", got)
	}
}

func TestSecurityEmail_EveryLocaleRendersWithoutAFormatDefect(t *testing.T) {
	enSubject := ""
	for _, loc := range emailLocales {
		for _, cls := range [][2]string{{"firefox", "linux"}, {"threkir_app", "other"}, {"other", "other"}} {
			e, ok := renderSecurityEmail(SecurityEmailPayload{
				UserID: "u1", Template: "new_device_sign_in",
				Browser: cls[0], Platform: cls[1], SignedInAt: "2026-10-14T09:30:00Z",
			}, "https://example.test", loc)
			if !ok {
				t.Fatalf("renderSecurityEmail refused new_device_sign_in")
			}
			for part, s := range map[string]string{"subject": e.Subject, "body": e.Body, "html": e.HTML} {
				if d := formatDefect(s); d != "" {
					t.Errorf("new_device_sign_in/%s (%v) %s carries %q", loc, cls, part, d)
				}
			}
			if !strings.Contains(e.Body, "2026-10-14 09:30 UTC") {
				t.Errorf("new_device_sign_in/%s does not state the sign-in time", loc)
			}
			if !strings.Contains(e.Body, "/login?reset=1") {
				t.Errorf("new_device_sign_in/%s has no reset link", loc)
			}
			if loc == "en" {
				enSubject = e.Subject
			}
		}
	}
	for _, loc := range emailLocales {
		if loc == "en" {
			continue
		}
		e, _ := renderSecurityEmail(SecurityEmailPayload{Template: "new_device_sign_in", Browser: "firefox", Platform: "linux"}, "https://example.test", loc)
		if e.Subject == enSubject {
			t.Errorf("new_device_sign_in/%s subject is the English one — the catalogue entry is missing", loc)
		}
	}
}
