package internal

import (
	"context"
	"strings"
	"testing"
)

const testViewToken = "0b6f2c1e-4a8d-4c3b-9e7f-1a2b3c4d5e6f"

func TestSafetyLiveURL(t *testing.T) {
	cases := []struct {
		name  string
		runID *string
		token string
		want  string
	}{
		{"no run falls back to the site", nil, testViewToken, "https://x.test"},
		{"empty run falls back to the site", strptr(""), testViewToken, "https://x.test"},
		{"public share is the bare link", strptr("run-1"), "", "https://x.test/live/run-1"},
		{"safety share carries the token in the fragment", strptr("run-1"), testViewToken,
			"https://x.test/live/run-1#k=" + testViewToken},
		{"a non-uuid token is dropped", strptr("run-1"), "x\"><script>", "https://x.test/live/run-1"},
		{"an uppercase token is not one the database mints", strptr("run-1"), strings.ToUpper(testViewToken),
			"https://x.test/live/run-1"},
	}
	for _, c := range cases {
		if got := safetyLiveURL("https://x.test", c.runID, c.token); got != c.want {
			t.Errorf("%s: got %q, want %q", c.name, got, c.want)
		}
	}
}

func TestSafetyEmail_SafetyAudienceLinkCarriesTheContactsToken(t *testing.T) {
	for _, tmpl := range []string{"overdue", "off_route"} {
		sender := &fakeEmailSender{}
		w := newEmailTestWorker(&fakeBackend{}, sender)
		job := safetyJob(SafetyEmailPayload{
			Template:     tmpl,
			ContactEmail: "partner@safe.local",
			OwnerName:    "Ada Owner",
			RunID:        strptr("run-1"),
			StartedAt:    "2026-07-06T18:00:00+00:00",
			ViewToken:    testViewToken,
		})
		if err := w.handleSafetyEmail(context.Background(), job); err != nil {
			t.Fatalf("%s handler: %v", tmpl, err)
		}
		if len(sender.sent) != 1 {
			t.Fatalf("%s must send once, got %d", tmpl, len(sender.sent))
		}
		if !strings.Contains(sender.sent[0].msg.Body, "/live/run-1#k="+testViewToken) {
			t.Errorf("%s mail must carry the contact's link, got %q", tmpl, sender.sent[0].msg.Body)
		}
	}
}

func TestSafetySms_SafetyAudienceLinkCarriesTheContactsToken(t *testing.T) {
	for _, tmpl := range []string{"overdue", "off_route"} {
		sender := &fakeSmsSender{}
		w := newSmsTestWorker(&fakeBackend{}, sender)
		job := smsJob(SafetySmsPayload{
			Template:     tmpl,
			ContactPhone: "+447700900123",
			OwnerName:    "Ada Owner",
			RunID:        strptr("run-1"),
			StartedAt:    "2026-07-06T18:00:00+00:00",
			ViewToken:    testViewToken,
		})
		if err := w.handleSafetySms(context.Background(), job); err != nil {
			t.Fatalf("%s handler: %v", tmpl, err)
		}
		if len(sender.sent) != 1 {
			t.Fatalf("%s must send once, got %d", tmpl, len(sender.sent))
		}
		if !strings.Contains(sender.sent[0].body, "/live/run-1#k="+testViewToken) {
			t.Errorf("%s SMS must carry the contact's link, got %q", tmpl, sender.sent[0].body)
		}
	}
}
