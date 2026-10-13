package internal

// Coverage for privacyDefaultAudience, the helper that makes Strava-synced
// runs honour the user's privacy_default (persona #27, decisions § 1875).
// 'public' publishes, 'followers' and an unset pref write followers_only, and
// 'private', unknown values and any read error are owner-only. Uses the same
// httptest harness as the data-export tests.

import (
	"context"
	"net/http"
	"testing"
)

func TestPrivacyDefaultAudience(t *testing.T) {
	cases := []struct {
		name          string
		body          string
		status        int
		isPublic      bool
		followersOnly bool
	}{
		{"explicit public publishes", `[{"prefs":{"privacy_default":"public"}}]`, 200, true, false},
		{"followers writes followers_only", `[{"prefs":{"privacy_default":"followers"}}]`, 200, false, true},
		{"private stays owner-only", `[{"prefs":{"privacy_default":"private"}}]`, 200, false, false},
		{"unknown value stays owner-only", `[{"prefs":{"privacy_default":"everyone"}}]`, 200, false, false},
		{"unset pref takes the followers fallback", `[{"prefs":{"preferred_unit":"km"}}]`, 200, false, true},
		{"no settings row takes the followers fallback", `[]`, 200, false, true},
		{"null prefs takes the followers fallback", `[{"prefs":null}]`, 200, false, true},
		{"read error falls closed to owner-only", `boom`, 500, false, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			client := newSupabaseTestServer(t, func(w http.ResponseWriter, r *http.Request) {
				if tc.status != 200 {
					w.WriteHeader(tc.status)
				}
				_, _ = w.Write([]byte(tc.body))
			})
			isPublic, followersOnly := client.privacyDefaultAudience(context.Background(), "user-A")
			if isPublic != tc.isPublic || followersOnly != tc.followersOnly {
				t.Errorf("privacyDefaultAudience = (%v, %v); want (%v, %v)",
					isPublic, followersOnly, tc.isPublic, tc.followersOnly)
			}
		})
	}
}
