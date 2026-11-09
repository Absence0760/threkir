package internal

import "testing"

// A verified organiser's course alert (decisions § 2407) goes out by default
// on both channels, has its own mute, and the mute only subtracts.
func TestCourseAlert_ReachesTheDefaultModeAndHasItsOwnMute(t *testing.T) {
	def := map[string]interface{}{}
	if !shouldEmail("course_alert", def) || !shouldPush("course_alert", def) {
		t.Fatal("course_alert should go out on both channels under the default important mode")
	}
	muted := map[string]interface{}{"notify_course_alert": "off"}
	if shouldEmail("course_alert", muted) || shouldPush("course_alert", muted) {
		t.Fatal("notify_course_alert=off must silence email and push")
	}
	on := map[string]interface{}{"notify_course_alert": "on", "email_notifications": "off", "push_notifications": "off"}
	if shouldEmail("course_alert", on) || shouldPush("course_alert", on) {
		t.Fatal("notify_course_alert=on lifted a muted channel")
	}
	if got := pathForKind("course_alert", "https://x.test", NotificationRow{Kind: "course_alert"}); got == "" {
		t.Fatal("a course alert with no id still links somewhere")
	}
}
