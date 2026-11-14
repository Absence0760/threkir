package internal

import (
	"encoding/json"
	"os"
	"strings"
	"testing"
)

// A park course's month-close notice (issue #1343, decisions § 2426) is
// bell-only by default, goes out on email and push only under "all", has its
// own mute, and the mute only subtracts.
func TestParkCourseMonth_BellOnlyByDefaultWithItsOwnMute(t *testing.T) {
	const kind = "park_course_month_closed"
	def := map[string]interface{}{}
	if shouldEmail(kind, def) || shouldPush(kind, def) {
		t.Fatal("park_course_month_closed must stay in the bell under the default important modes")
	}
	all := map[string]interface{}{"email_notifications": "all", "push_notifications": "all"}
	if !shouldEmail(kind, all) || !shouldPush(kind, all) {
		t.Fatal("park_course_month_closed should go out on both channels under \"all\"")
	}
	muted := map[string]interface{}{"email_notifications": "all", "push_notifications": "all", "notify_park_course_month": "off"}
	if shouldEmail(kind, muted) || shouldPush(kind, muted) {
		t.Fatal("notify_park_course_month=off must silence email and push")
	}
}

// The row's embedded slugs and month become the course page on the closed
// month's board, a route the web serves; a partial read falls back to the inbox.
func TestParkCourseMonth_DeepLinksToTheMonthBoard(t *testing.T) {
	const base = "https://threkir.test"
	var row NotificationRow
	if err := json.Unmarshal([]byte(`{
		"id": "n1", "user_id": "u1", "kind": "park_course_month_closed",
		"park_course_id": "c1", "park_course_month": "2026-10-01",
		"park_course": {"slug": "beaver-lake-trail", "park": {"slug": "pocahontas", "region_code": "US-VA"}}
	}`), &row); err != nil {
		t.Fatal(err)
	}
	got := pathForKind(row.Kind, base, row)
	want := base + "/parks/us-va/pocahontas/beaver-lake-trail?period=2026-10"
	if got != want {
		t.Fatalf("pathForKind = %q, want %q", got, want)
	}
	if !resolvesOnWeb(webPageRoutes(t), base, got) {
		t.Fatalf("%q matches no route under %s", got, webRoutesDir)
	}

	partial := row
	partial.ParkCourse = nil
	if got := pathForKind(row.Kind, base, partial); got != inboxPath(base, partial) {
		t.Fatalf("a row without its course slugs should open the inbox, got %q", got)
	}
	noMonth := row
	noMonth.ParkCourseMonth = nil
	if got := pathForKind(row.Kind, base, noMonth); got != inboxPath(base, noMonth) {
		t.Fatalf("a row without its month should open the inbox, got %q", got)
	}
}

// Every locale carries the copy, and none of it names a place or a rank: the
// row carries a time and no rank (decisions § 2426), and a time is never
// called a record (decisions § 2469).
func TestParkCourseMonth_CopyInEveryLocaleWithoutARank(t *testing.T) {
	for loc, cat := range emailCatalogue {
		s, ok := cat["park_course_month_closed"]
		if !ok {
			t.Errorf("%s: no park_course_month_closed copy", loc)
			continue
		}
		if loc != "en" {
			continue
		}
		text := strings.ToLower(strings.Join(append([]string{s.subject, s.preheader, s.heading, s.cta}, s.body...), " "))
		for _, banned := range []string{"rank", "place", "record", "1st", "2nd", "winner"} {
			if strings.Contains(text, banned) {
				t.Errorf("en copy says %q, but the notice carries a time and no rank", banned)
			}
		}
	}
}

// The three notification projections select the columns the path reads.
func TestParkCourseMonth_ProjectionsSelectTheCourse(t *testing.T) {
	b, err := os.ReadFile("supabase.go")
	if err != nil {
		t.Fatal(err)
	}
	src := string(b)
	want := "park_course_id,park_course_month,park_course:park_courses(slug,park:parks(slug,region_code))"
	if n := strings.Count(src, want); n != 3 {
		t.Fatalf("expected the email, web-push and native-push projections to embed the course, found %d", n)
	}
}
