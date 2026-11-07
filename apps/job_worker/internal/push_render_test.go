package internal

import (
	"encoding/json"
	"strings"
	"testing"
)

// The push channel's own three-mode preference and its independence from the
// email channel (docs/backend/settings.md): absent, mistyped or unknown reads
// "important", the smaller set.

func TestPushMode_ReadsTheThreeModesAndFailsTowardImportant(t *testing.T) {
	cases := []struct {
		prefs map[string]interface{}
		want  string
	}{
		{map[string]interface{}{"push_notifications": "all"}, pushModeAll},
		{map[string]interface{}{"push_notifications": "important"}, pushModeImportant},
		{map[string]interface{}{"push_notifications": "off"}, pushModeOff},
		{map[string]interface{}{}, pushModeImportant},
		{nil, pushModeImportant},
		{map[string]interface{}{"push_notifications": "everything"}, pushModeImportant},
		{map[string]interface{}{"push_notifications": "OFF"}, pushModeImportant},
		{map[string]interface{}{"push_notifications": true}, pushModeImportant},
		{map[string]interface{}{"push_notifications": nil}, pushModeImportant},
	}
	for _, c := range cases {
		if got := pushMode(c.prefs); got != c.want {
			t.Errorf("pushMode(%v) = %q, want %q", c.prefs, got, c.want)
		}
	}
}

func TestShouldPush_FollowsTheModeAndTheKindSets(t *testing.T) {
	important := map[string]interface{}{}
	all := map[string]interface{}{"push_notifications": "all"}
	off := map[string]interface{}{"push_notifications": "off"}

	if !shouldPush("message", important) {
		t.Error("an important kind pushes in the default mode")
	}
	if !shouldPush("workout_reminder", important) {
		t.Error("a push-important kind pushes in the default mode")
	}
	if shouldPush("kudos", important) {
		t.Error("an ordinary kind does not push in the default mode")
	}
	if !shouldPush("kudos", all) {
		t.Error("an ordinary kind pushes under all")
	}
	if shouldPush("message", off) {
		t.Error("nothing pushes when push is off")
	}
}

func TestShouldPush_InAppOnlyKindsNeverPush(t *testing.T) {
	all := map[string]interface{}{"push_notifications": "all"}
	for kind := range inAppOnlyKinds {
		if shouldPush(kind, all) {
			t.Errorf("%s is in-app only but pushed under all", kind)
		}
	}
}

func TestShouldPush_APerKindMuteWinsOverAll(t *testing.T) {
	prefs := map[string]interface{}{"push_notifications": "all", "notify_reaction": "off"}
	if shouldPush("reaction", prefs) {
		t.Error("a muted kind pushed under all")
	}
	prefs["notify_reaction"] = "on"
	if !shouldPush("reaction", prefs) {
		t.Error("an unmuted kind should push under all")
	}
}

func TestShouldPush_MutingEmailLeavesPushAlone(t *testing.T) {
	prefs := map[string]interface{}{"email_notifications": "off"}
	if !shouldPush("message", prefs) {
		t.Error("turning email off must not silence push")
	}
	prefs = map[string]interface{}{"push_notifications": "off", "email_notifications": "all"}
	if shouldPush("message", prefs) {
		t.Error("email on must not re-enable push")
	}
}

func TestRenderPush_WebAndNativeCarryTheSameCopyAndTag(t *testing.T) {
	n := NotificationRow{ID: "n42", Kind: "message"}
	raw, err := renderWebPushPayload(n, "https://threkir.com/", "en")
	if err != nil {
		t.Fatal(err)
	}
	var web webPushPayload
	if err := json.Unmarshal(raw, &web); err != nil {
		t.Fatal(err)
	}
	native := renderNativeMessage(n, "https://threkir.com/", "en")

	if web.Tag != "notif-n42" || native.Tag != "notif-n42" {
		t.Errorf("tags: web %q native %q, want notif-n42", web.Tag, native.Tag)
	}
	if web.Title == "" || web.Title != native.Title || web.Body != native.Body || web.URL != native.URL {
		t.Errorf("web %+v and native %+v must render the same copy", web, native)
	}
	if strings.Contains(strings.TrimPrefix(web.URL, "https://"), "//") {
		t.Errorf("a trailing slash on the base doubled into the URL: %q", web.URL)
	}
}
