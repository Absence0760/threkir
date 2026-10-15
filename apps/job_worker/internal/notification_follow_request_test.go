package internal

import (
	"encoding/json"
	"strings"
	"testing"
)

// A follow_request row (migration 20270822000001, decisions § 1967) asks a
// private profile's owner to approve or decline someone. Every outbound rail
// carries its own copy and lands on /follow-requests, where both actions live:
// the asker's profile would be the wrong target.

func TestFollowRequest_EveryRailCarriesItsCopyAndTheRequestsLink(t *testing.T) {
	const base = "https://threkir.test"
	row := NotificationRow{ID: "n1", UserID: "u1", Kind: "follow_request"}
	follow := NotificationRow{ID: "n2", UserID: "u1", Kind: "follow"}
	const link = base + "/follow-requests"

	for _, loc := range emailLocales {
		want, ok := emailCatalogue[loc]["follow_request"]
		if !ok {
			t.Errorf("%s: no follow_request copy", loc)
			continue
		}

		email := renderNotificationEmail(row, base, loc)
		if email.Subject != want.subject {
			t.Errorf("%s: email subject %q, want %q", loc, email.Subject, want.subject)
		}
		if email.Subject == renderNotificationEmail(follow, base, loc).Subject {
			t.Errorf("%s: a request reads like a follow that already happened", loc)
		}
		if !strings.Contains(email.Body, link) {
			t.Errorf("%s: the email does not link to the requests page", loc)
		}
		if !strings.Contains(email.Body, want.cta) {
			t.Errorf("%s: the email does not carry its %q call to action", loc, want.cta)
		}

		native := renderNativeMessage(row, base, loc)
		if native.Title != want.heading || native.URL != link {
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
		if wp.Title != want.heading || wp.URL != link {
			t.Errorf("%s: web push = %q -> %q", loc, wp.Title, wp.URL)
		}
	}
}

func TestFollowRequest_IsEmailedToARecipientOnAllMail(t *testing.T) {
	if !shouldEmail("follow_request", map[string]interface{}{"email_notifications": "all"}) {
		t.Error("a follow request is not emailed under the \"all\" mode")
	}
	if !shouldPush("follow_request", map[string]interface{}{"push_notifications": "all"}) {
		t.Error("a follow request is not pushed under the \"all\" mode")
	}
}
