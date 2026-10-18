package internal

import (
	"encoding/json"
	"strings"
	"testing"
)

// A workout_reminder row (migration 20270913000001) is raised once a local
// morning for the runner's active plan when today holds an outstanding
// workout. Every outbound rail carries its own copy and lands on the plan the
// row names.

func TestWorkoutReminder_EveryRailCarriesItsCopyAndThePlanLink(t *testing.T) {
	const base = "https://threkir.test"
	plan := "p1"
	row := NotificationRow{ID: "n1", UserID: "u1", Kind: "workout_reminder", PlanID: &plan}
	update := NotificationRow{ID: "n2", UserID: "u1", Kind: "plan_update", PlanID: &plan}
	const link = base + "/plans/p1"

	for _, loc := range emailLocales {
		want, ok := emailCatalogue[loc]["workout_reminder"]
		if !ok {
			t.Errorf("%s: no workout_reminder copy", loc)
			continue
		}

		email := renderNotificationEmail(row, base, loc)
		if email.Subject != want.subject {
			t.Errorf("%s: email subject %q, want %q", loc, email.Subject, want.subject)
		}
		if email.Subject == renderNotificationEmail(update, base, loc).Subject {
			t.Errorf("%s: a reminder reads like a coach editing the plan", loc)
		}
		if !strings.Contains(email.Body, link) {
			t.Errorf("%s: the email does not link to the plan", loc)
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

func TestWorkoutReminder_WithoutAPlanLandsOnThePlansList(t *testing.T) {
	row := NotificationRow{ID: "n1", UserID: "u1", Kind: "workout_reminder"}
	if got := pathForKind(row.Kind, "https://threkir.test", row); got != "https://threkir.test/plans" {
		t.Errorf("a reminder with no plan_id links to %q", got)
	}
}

func TestWorkoutReminder_PushesByDefaultEmailsOnlyWhenOptedInAndHasItsOwnMute(t *testing.T) {
	def := map[string]interface{}{}
	if !shouldPush("workout_reminder", def) {
		t.Error("a workout reminder should push under the default important mode")
	}
	if shouldEmail("workout_reminder", def) {
		t.Error("a workout reminder must not email every morning under the default important mode")
	}
	if !shouldEmail("workout_reminder", emailPrefs(emailModeAll)) {
		t.Error("email_notifications = all opts in to the reminder email")
	}
	if shouldPush("workout_reminder", pushPrefs(pushModeOff)) {
		t.Error("push_notifications = off silences the reminder push")
	}

	muted := map[string]interface{}{"notify_workout_reminder": "off"}
	if shouldEmail("workout_reminder", muted) || shouldPush("workout_reminder", muted) {
		t.Error("notify_workout_reminder=off must silence email and push")
	}
	if kindMuted("event_reminder", muted) {
		t.Error("notify_workout_reminder muted another kind")
	}

	notOff := map[string]interface{}{"notify_workout_reminder": false}
	if !shouldPush("workout_reminder", notOff) {
		t.Error("only the literal \"off\" mutes")
	}

	off := map[string]interface{}{"email_notifications": emailModeOff, "push_notifications": pushModeOff, "notify_workout_reminder": "on"}
	if shouldEmail("workout_reminder", off) || shouldPush("workout_reminder", off) {
		t.Error("a per-kind 'on' must not promote a workout reminder past a channel mute")
	}
}
