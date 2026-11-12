package internal

import (
	"encoding/json"
	"testing"
)

// race_starting_soon and race_start_moved (migration 20271121002400,
// decisions § 2400) are raised for a scheduled race: about 10 minutes before
// the server fires GO, and when an organiser delays it. Both are push-only and
// share one mute key.

func TestRaceStart_PushOnlyByDefaultAndUnderAll(t *testing.T) {
	for _, kind := range []string{"race_starting_soon", "race_start_moved"} {
		if !shouldPush(kind, map[string]interface{}{}) {
			t.Errorf("%s should push under the default important mode", kind)
		}
		if shouldEmail(kind, map[string]interface{}{}) {
			t.Errorf("%s must not email under the default mode", kind)
		}
		if shouldEmail(kind, emailPrefs(emailModeAll)) {
			t.Errorf("%s must not email even under email_notifications = all", kind)
		}
		if shouldPush(kind, pushPrefs(pushModeOff)) {
			t.Errorf("push_notifications = off silences %s", kind)
		}
	}
}

func TestRaceStart_OneMuteSilencesBothAndNothingElse(t *testing.T) {
	muted := map[string]interface{}{"notify_race_starting_soon": "off"}
	for _, kind := range []string{"race_starting_soon", "race_start_moved"} {
		if shouldPush(kind, muted) {
			t.Errorf("notify_race_starting_soon=off must silence the %s push", kind)
		}
	}
	if kindMuted("event_reminder", muted) {
		t.Error("notify_race_starting_soon muted another kind")
	}
	if !shouldPush("race_starting_soon", map[string]interface{}{"notify_race_starting_soon": false}) {
		t.Error("only the literal \"off\" mutes")
	}
}

func TestRaceStart_EveryLocaleHasDistinctCopyAndTheEventLink(t *testing.T) {
	const base = "https://threkir.test"
	ev := "evt-1"
	const link = base + "/events/evt-1"
	soon := NotificationRow{ID: "n1", UserID: "u1", Kind: "race_starting_soon", EventID: &ev}
	moved := NotificationRow{ID: "n2", UserID: "u1", Kind: "race_start_moved", EventID: &ev}
	reminder := NotificationRow{ID: "n3", UserID: "u1", Kind: "event_reminder", EventID: &ev}

	for _, loc := range emailLocales {
		for _, row := range []NotificationRow{soon, moved} {
			want, ok := emailCatalogue[loc][row.Kind]
			if !ok {
				t.Errorf("%s: no %s copy", loc, row.Kind)
				continue
			}
			native := renderNativeMessage(row, base, loc)
			if native.Title != want.heading || native.URL != link {
				t.Errorf("%s %s: native push = %q -> %q", loc, row.Kind, native.Title, native.URL)
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
				t.Errorf("%s %s: web push = %q -> %q", loc, row.Kind, wp.Title, wp.URL)
			}
		}
		if renderNativeMessage(soon, base, loc).Title == renderNativeMessage(moved, base, loc).Title {
			t.Errorf("%s: starting soon and start moved read the same", loc)
		}
		if renderNativeMessage(soon, base, loc).Title == renderNativeMessage(reminder, base, loc).Title {
			t.Errorf("%s: starting soon reads like an event reminder", loc)
		}
	}
}
