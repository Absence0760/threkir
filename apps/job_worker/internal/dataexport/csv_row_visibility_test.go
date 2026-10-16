package dataexport

import "testing"

// The three visibility cells sit side by side and are all booleans, so a value
// written one slot off still reads as a well-formed CSV. A run shared live on
// the safety-contacts audience (decisions § 1964) is the row that tells them
// apart: private, not followers-only, safety audience on.
func TestCSVRowPutsEachVisibilityFlagUnderItsOwnHeader(t *testing.T) {
	private := false
	row := csvRow(ExportRun{
		ID:             "run-1",
		StartedAt:      "2026-10-01T07:00:00+00:00",
		Source:         "app",
		ActivityType:   "run",
		IsPublic:       &private,
		FollowersOnly:  false,
		SafetyAudience: true,
		CreatedAt:      "2026-10-01T08:00:00+00:00",
		UpdatedAt:      "2026-10-01T08:05:00+00:00",
	})
	if len(row) != len(csvColumns) {
		t.Fatalf("csvRow emits %d values for %d columns", len(row), len(csvColumns))
	}
	at := map[string]string{}
	for i, c := range csvColumns {
		at[c] = row[i]
	}
	for col, want := range map[string]string{
		"id":              "run-1",
		"is_public":       "false",
		"followers_only":  "false",
		"safety_audience": "true",
		"metadata":        "{}",
		"created_at":      "2026-10-01T08:00:00+00:00",
		"updated_at":      "2026-10-01T08:05:00+00:00",
	} {
		if at[col] != want {
			t.Errorf("%s = %q, want %q", col, at[col], want)
		}
	}
}
