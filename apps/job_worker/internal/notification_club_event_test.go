package internal

import "testing"

// The club and event notices of decisions § 2358: a join request and its
// approval, an edit to an event the recipient is going to, and the organiser's
// view of an RSVP. Each goes out by default, each has its own mute, and the
// RSVP is a push by default but an email only under "all".

func TestClubEventNotices_ReachTheDefaultModeAndHaveTheirOwnMute(t *testing.T) {
	def := map[string]interface{}{}
	for kind, key := range map[string]string{
		"club_join_request":  "notify_club_join_request",
		"club_join_approved": "notify_club_join_approved",
		"event_updated":      "notify_event_updated",
	} {
		if !shouldEmail(kind, def) || !shouldPush(kind, def) {
			t.Errorf("%s should go out on both channels under the default important mode", kind)
		}
		muted := map[string]interface{}{key: "off"}
		if shouldEmail(kind, muted) || shouldPush(kind, muted) {
			t.Errorf("%s=off must silence email and push for %s", key, kind)
		}
		// A per-kind key only subtracts: it cannot lift a muted channel.
		on := map[string]interface{}{key: "on", "email_notifications": "off", "push_notifications": "off"}
		if shouldEmail(kind, on) || shouldPush(kind, on) {
			t.Errorf("%s=on lifted a muted channel for %s", key, kind)
		}
	}
}

func TestEventRsvp_IsAPushByDefaultAndAnEmailOnlyOnAll(t *testing.T) {
	def := map[string]interface{}{}
	if !shouldPush("event_rsvp", def) {
		t.Error("an RSVP should reach an organiser's phone under the default push mode")
	}
	if shouldEmail("event_rsvp", def) {
		t.Error("an RSVP must not be emailed under the default email mode: a busy event raises one per RSVP")
	}
	if !shouldEmail("event_rsvp", map[string]interface{}{"email_notifications": "all"}) {
		t.Error("an RSVP should be emailed under \"all\"")
	}
	muted := map[string]interface{}{"notify_event_rsvp": "off"}
	if shouldPush("event_rsvp", muted) || shouldEmail("event_rsvp", map[string]interface{}{"notify_event_rsvp": "off", "email_notifications": "all"}) {
		t.Error("notify_event_rsvp=off must silence the push and the email")
	}
}

func TestClubEventNotices_CarryTheirOwnCopyInEveryLocale(t *testing.T) {
	for _, loc := range emailLocales {
		for _, kind := range []string{"club_join_request", "club_join_approved", "event_updated"} {
			got, ok := emailCatalogue[loc][kind]
			if !ok {
				t.Errorf("%s: no %s copy", loc, kind)
				continue
			}
			if got.subject == emailCatalogue[loc]["default"].subject {
				t.Errorf("%s: %s reads as the generic notification", loc, kind)
			}
		}
		if emailCatalogue[loc]["club_join_request"].subject == emailCatalogue[loc]["club_join_approved"].subject {
			t.Errorf("%s: a request and its approval read the same", loc)
		}
	}
}
