package internal

import (
	"context"
	"net/http"
	"strings"
	"testing"
)

// Each outbound rail reads its own projection of the notifications row. A rail
// whose select drops `refunded` decodes every paid registrant's cancel as a
// plain one, so the refund copy (copyKeyFor) never reaches that channel even
// though every render test passes on a hand-built row.

type notificationFetcher struct {
	name    string
	sentCol string
	fetch   func(*SupabaseClient, context.Context, string) (*NotificationRow, error)
}

var notificationFetchers = []notificationFetcher{
	{"email", "email_sent_at", (*SupabaseClient).FetchNotificationForEmail},
	{"web push", "web_push_sent_at", (*SupabaseClient).FetchNotificationForWebPush},
	{"native push", "native_push_sent_at", (*SupabaseClient).FetchNotificationForNativePush},
}

func TestNotificationFetchers_SelectRefunded(t *testing.T) {
	for _, f := range notificationFetchers {
		t.Run(f.name, func(t *testing.T) {
			var path, sel, id string
			client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
				path = r.URL.Path
				sel = r.URL.Query().Get("select")
				id = r.URL.Query().Get("id")
				w.Header().Set("Content-Type", "application/json")
				_, _ = w.Write([]byte(`[{"id":"n1","user_id":"u1","kind":"event_cancel","event_id":"e1","refunded":true}]`))
			})

			row, err := f.fetch(client, context.Background(), "n1")
			if err != nil {
				t.Fatalf("fetch: %v", err)
			}
			if path != "/rest/v1/notifications" {
				t.Errorf("path = %q, want /rest/v1/notifications", path)
			}
			if id != "eq.n1" {
				t.Errorf("id filter = %q, want eq.n1", id)
			}
			cols := map[string]bool{}
			for _, c := range strings.Split(sel, ",") {
				cols[c] = true
			}
			for _, want := range []string{"refunded", "kind", "event_id", f.sentCol} {
				if !cols[want] {
					t.Errorf("select %q is missing %q", sel, want)
				}
			}
			if row == nil || !row.Refunded {
				t.Fatalf("row = %+v, want Refunded decoded true", row)
			}
			if got := copyKeyFor(*row); got != "event_cancel_refunded" {
				t.Errorf("copyKeyFor(fetched row) = %q, want event_cancel_refunded", got)
			}
		})
	}
}

func TestNotificationFetchers_MissingRowIsNil(t *testing.T) {
	for _, f := range notificationFetchers {
		t.Run(f.name, func(t *testing.T) {
			client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
				w.Header().Set("Content-Type", "application/json")
				_, _ = w.Write([]byte(`[]`))
			})
			row, err := f.fetch(client, context.Background(), "gone")
			if err != nil || row != nil {
				t.Errorf("fetch of a cleared row = (%+v, %v), want (nil, nil)", row, err)
			}
		})
	}
}
