package internal

import (
	"encoding/json"
	"strings"
	"testing"
)

// An event_cancel row with `refunded` set (migration 20270725000002) is a paid
// registrant's cancel: every outbound rail must tell them the payment is being
// refunded, and must keep pointing at the same event the plain cancel does.

func TestCopyKeyFor_RefundedEventCancel(t *testing.T) {
	cases := []struct {
		name string
		row  NotificationRow
		want string
	}{
		{"paid registrant", NotificationRow{Kind: "event_cancel", Refunded: true}, "event_cancel_refunded"},
		{"free attendee", NotificationRow{Kind: "event_cancel"}, "event_cancel"},
		// The flag means nothing on another kind; it must not borrow the copy.
		{"other kind ignores the flag", NotificationRow{Kind: "event_reminder", Refunded: true}, "event_reminder"},
		{"comment_reply still folds", NotificationRow{Kind: "comment_reply"}, "comment"},
	}
	for _, c := range cases {
		if got := copyKeyFor(c.row); got != c.want {
			t.Errorf("%s: copyKeyFor = %q, want %q", c.name, got, c.want)
		}
	}
}

func TestRefundedEventCancel_EveryRailSaysRefundInEveryLocale(t *testing.T) {
	const base = "https://threkir.test"
	ev := "9f1c3a52-0000-4000-8000-000000000002"
	plain := NotificationRow{ID: "n1", UserID: "u1", Kind: "event_cancel", EventID: &ev}
	paid := plain
	paid.Refunded = true

	for _, loc := range emailLocales {
		if _, ok := emailCatalogue[loc]["event_cancel_refunded"]; !ok {
			t.Errorf("%s: no event_cancel_refunded copy", loc)
			continue
		}

		pe, re := renderNotificationEmail(plain, base, loc), renderNotificationEmail(paid, base, loc)
		if pe.Subject == re.Subject || pe.Body == re.Body {
			t.Errorf("%s: a refunded cancel email reads the same as a plain one", loc)
		}
		if !strings.Contains(re.Body, base+"/events/"+ev) {
			t.Errorf("%s: refunded cancel email lost the event link", loc)
		}

		pn, rn := renderNativeMessage(plain, base, loc), renderNativeMessage(paid, base, loc)
		if pn.Title == rn.Title || pn.Body == rn.Body {
			t.Errorf("%s: refunded cancel native push reads the same as a plain one", loc)
		}
		if rn.URL != pn.URL {
			t.Errorf("%s: native push URL %q, want %q", loc, rn.URL, pn.URL)
		}

		raw, err := renderWebPushPayload(paid, base, loc)
		if err != nil {
			t.Fatalf("%s: web push render: %v", loc, err)
		}
		var wp webPushPayload
		if err := json.Unmarshal(raw, &wp); err != nil {
			t.Fatalf("%s: web push payload: %v", loc, err)
		}
		want := emailCatalogue[loc]["event_cancel_refunded"]
		if wp.Title != want.heading || wp.Body != want.preheader {
			t.Errorf("%s: web push = %q / %q, want the refunded copy %q / %q",
				loc, wp.Title, wp.Body, want.heading, want.preheader)
		}
	}
}
