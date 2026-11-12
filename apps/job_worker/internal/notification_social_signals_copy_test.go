package internal

import (
	"encoding/json"
	"strings"
	"testing"
)

// decisions § 1971: a reaction, a comment like and a mention each reach the
// email, web-push and native-push rails with their own copy in every locale
// and a link to the run the row names.
func TestSocialSignals_EveryRailCarriesItsCopyAndTheRunLink(t *testing.T) {
	const base = "https://threkir.test"
	run := "run-1"
	const link = base + "/runs/run-1"

	for _, kind := range []string{"reaction", "comment_like", "mention"} {
		row := NotificationRow{ID: "n1", UserID: "u1", Kind: kind, RunID: &run}
		for _, loc := range emailLocales {
			want, ok := emailCatalogue[loc][kind]
			if !ok {
				t.Errorf("%s/%s: no copy", loc, kind)
				continue
			}

			email := renderNotificationEmail(row, base, loc)
			if email.Subject != want.subject {
				t.Errorf("%s/%s: email subject %q, want %q", loc, kind, email.Subject, want.subject)
			}
			if !strings.Contains(email.Body, link) {
				t.Errorf("%s/%s: the email does not link to the run", loc, kind)
			}
			if !strings.Contains(email.Body, want.cta) {
				t.Errorf("%s/%s: the email does not carry its %q call to action", loc, kind, want.cta)
			}

			native := renderNativeMessage(row, base, loc)
			if native.Title != want.heading || native.Body != want.preheader || native.URL != link {
				t.Errorf("%s/%s: native push = %q / %q -> %q", loc, kind, native.Title, native.Body, native.URL)
			}
			if native.Tag != "notif-n1" {
				t.Errorf("%s/%s: native push tag %q", loc, kind, native.Tag)
			}

			raw, err := renderWebPushPayload(row, base, loc)
			if err != nil {
				t.Fatalf("%s/%s: web push render: %v", loc, kind, err)
			}
			var wp webPushPayload
			if err := json.Unmarshal(raw, &wp); err != nil {
				t.Fatalf("%s/%s: web push payload: %v", loc, kind, err)
			}
			if wp.Title != want.heading || wp.Body != want.preheader || wp.URL != link || wp.Tag != "notif-n1" {
				t.Errorf("%s/%s: web push = %+v", loc, kind, wp)
			}
		}
	}
}

// The three kinds sit beside kudos in the same inbox, so each must read as
// itself rather than as one of its neighbours.
func TestSocialSignals_SubjectsAreDistinctFromEachOtherAndFromKudos(t *testing.T) {
	for _, loc := range emailLocales {
		seen := map[string]string{}
		for _, kind := range []string{"kudos", "reaction", "comment_like", "mention"} {
			subject := emailCatalogue[loc][kind].subject
			if prev, dup := seen[subject]; dup {
				t.Errorf("%s: %s and %s share the subject %q", loc, prev, kind, subject)
			}
			seen[subject] = kind
		}
	}
}
