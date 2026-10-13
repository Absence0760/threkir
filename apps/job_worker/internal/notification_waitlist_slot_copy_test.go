package internal

import (
	"encoding/json"
	"strings"
	"testing"
)

// An event_waitlist_slot row (migration 20270726000002) tells a waitlister on
// a paid occurrence that a seat is being held for them until a deadline. It
// is the one notification whose value lapses if it is not delivered, so it
// must go out under the default channel settings, carry its own copy in every
// locale on every outbound rail, and land on the event page where the claim
// is made.

func TestWaitlistSlot_IsSentUnderTheDefaultSettings(t *testing.T) {
	defaults := map[string]interface{}{}
	if !shouldEmail("event_waitlist_slot", defaults) {
		t.Error("a held seat is not emailed under the default \"important\" mode")
	}
	if !shouldPush("event_waitlist_slot", defaults) {
		t.Error("a held seat is not pushed under the default \"important\" mode")
	}
	if inAppOnlyKinds["event_waitlist_slot"] {
		t.Error("a held seat must leave the inbox: it expires")
	}
}

func TestWaitlistSlot_EveryRailHasItsOwnCopyInEveryLocale(t *testing.T) {
	const base = "https://threkir.test"
	ev := "9f1c3a52-0000-4000-8000-000000000003"
	row := NotificationRow{ID: "n1", UserID: "u1", Kind: "event_waitlist_slot", EventID: &ev}
	cancel := NotificationRow{ID: "n2", UserID: "u1", Kind: "event_cancel", EventID: &ev}

	for _, loc := range emailLocales {
		want, ok := emailCatalogue[loc]["event_waitlist_slot"]
		if !ok {
			t.Errorf("%s: no event_waitlist_slot copy", loc)
			continue
		}
		if want.subject == emailCatalogue[loc]["default"].subject {
			t.Errorf("%s: the held-seat subject is the generic default", loc)
		}

		email := renderNotificationEmail(row, base, loc)
		if email.Subject != want.subject {
			t.Errorf("%s: email subject %q, want %q", loc, email.Subject, want.subject)
		}
		if email.Subject == renderNotificationEmail(cancel, base, loc).Subject {
			t.Errorf("%s: a held seat reads like a cancellation", loc)
		}
		if !strings.Contains(email.Body, base+"/events/"+ev) {
			t.Errorf("%s: the held-seat email does not link to the event, where the claim is made", loc)
		}

		native := renderNativeMessage(row, base, loc)
		if native.Title != want.heading || native.URL != base+"/events/"+ev {
			t.Errorf("%s: native push = %q -> %q", loc, native.Title, native.URL)
		}

		raw, err := renderWebPushPayload(row, base, loc)
		if err != nil {
			t.Fatalf("%s: web push render: %v", loc, err)
		}
		var wp webPushPayload
		if err := json.Unmarshal(raw, &wp); err != nil {
			t.Fatalf("%s: web push payload: %v", loc, err)
		}
		if wp.Title != want.heading || wp.Body != want.preheader {
			t.Errorf("%s: web push = %q / %q, want %q / %q", loc, wp.Title, wp.Body, want.heading, want.preheader)
		}
	}
}

func TestWaitlistSlot_WithoutAnEventFallsBackRatherThanDeadLinking(t *testing.T) {
	// The trigger always sets event_id; a row without one is malformed, and
	// eventPath's own fallback is the honest landing spot.
	got := pathForKind("event_waitlist_slot", "https://threkir.test", NotificationRow{UserID: "u1"})
	if got != eventPath("https://threkir.test", NotificationRow{UserID: "u1"}) {
		t.Errorf("event_waitlist_slot without an event routed to %q", got)
	}
}
