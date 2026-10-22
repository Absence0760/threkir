package internal

import (
	"strings"
	"testing"
)

// Every reports spec but the subject's own history names someone else as the
// reporter, so its projection must leave out reporter_id and notes (the
// reporter's own free text; Art 15(4)) and legal_hold: a hold marks a report a moderator is keeping for a legal claim,
// and disclosing it to the reported person tips them off (decisions § 2231).
// The twin of backup_spec.test.ts's against-me projection tests.
func TestAgainstMeReportSpecsProjectNoReporterOrHold(t *testing.T) {
	seen := 0
	for _, spec := range exportPersonalDataSpecs("user-A") {
		if spec.table != "reports" || strings.HasPrefix(spec.filter, "reporter_id=") {
			continue
		}
		seen++
		if spec.sel == "*" {
			t.Errorf("%s selects *; an against-me reports spec must name its columns", spec.name)
			continue
		}
		for _, col := range strings.Split(spec.sel, ",") {
			if col == "reporter_id" || col == "notes" || col == "legal_hold" {
				t.Errorf("%s discloses %s", spec.name, col)
			}
		}
	}
	if seen == 0 {
		t.Fatal("no against-me reports spec found; the filter this test reads has moved")
	}
}

// Only the recipient can report a direct message, so the sender can identify
// the reporter: a report still under review stays out of their archive.
func TestReportsAgainstMyMessagesHoldsBackPending(t *testing.T) {
	for _, spec := range exportPersonalDataSpecs("user-A") {
		if spec.name != "reports_against_my_messages.json" {
			continue
		}
		if !strings.Contains(spec.filter, "status=neq.pending") {
			t.Errorf("%s ships pending reports: filter %q", spec.name, spec.filter)
		}
		return
	}
	t.Fatal("reports_against_my_messages.json spec not found")
}
