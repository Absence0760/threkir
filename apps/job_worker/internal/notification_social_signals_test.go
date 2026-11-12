package internal

import "testing"

// decisions § 1971: each of the three social-signal kinds has its own
// opt-OUT mute, the mute only ever subtracts, and a mention reaches the
// default "important" set while a reaction or a comment like does not.
func TestSocialSignalKinds_MuteAndClassification(t *testing.T) {
	for kind, key := range map[string]string{
		"reaction":     "notify_reaction",
		"comment_like": "notify_comment_like",
		"mention":      "notify_mention",
	} {
		all := map[string]interface{}{"email_notifications": emailModeAll, "push_notifications": pushModeAll}
		if !shouldEmail(kind, all) || !shouldPush(kind, all) {
			t.Errorf("%s should go out on both channels under 'all'", kind)
		}
		all[key] = "off"
		if shouldEmail(kind, all) || shouldPush(kind, all) {
			t.Errorf("%s: %s=off must silence email and push", kind, key)
		}
		for _, v := range []interface{}{"on", true, nil, "OFF"} {
			if kindMuted(kind, map[string]interface{}{key: v}) {
				t.Errorf("%s: only the literal \"off\" mutes; %v did", kind, v)
			}
		}
		off := map[string]interface{}{"email_notifications": emailModeOff, "push_notifications": pushModeOff, key: "on"}
		if shouldEmail(kind, off) || shouldPush(kind, off) {
			t.Errorf("%s: a per-kind 'on' must not promote past a channel mute", kind)
		}
		// One kind's mute leaves the others alone.
		if kind != "mention" && kindMuted("mention", map[string]interface{}{key: "off"}) {
			t.Errorf("%s muted mention", key)
		}
	}
	def := map[string]interface{}{}
	if !shouldEmail("mention", def) || !shouldPush("mention", def) {
		t.Error("a mention is in the default important set on both channels")
	}
	for _, k := range []string{"reaction", "comment_like"} {
		if shouldEmail(k, def) || shouldPush(k, def) {
			t.Errorf("%s must not go out under the default important mode", k)
		}
	}
}
