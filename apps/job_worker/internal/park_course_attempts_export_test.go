package internal

import (
	"testing"

	"github.com/jaredhoward-dev/threkir/apps/job_worker/internal/schema"
)

// park_course_attempts says where the subject ran and why a run got no time
// on a park course (issue #1446). It is owner-only by RLS, so the Art 20
// archive carries the subject's own rows, keyed on user_id, every column:
// the run, the course, the outcome, the progress and the matcher version.
func TestParkCourseAttemptsExportIsTheSubjectsOwnRowsWhole(t *testing.T) {
	var found []exportTableSpec
	for _, spec := range exportPersonalDataSpecs("user-A") {
		if spec.table == schema.TableParkCourseAttempts {
			found = append(found, spec)
		}
	}
	if len(found) != 1 {
		t.Fatalf("park_course_attempts has %d export specs, want exactly 1", len(found))
	}
	spec := found[0]
	if spec.name != "park_course_attempts.json" {
		t.Errorf("entry name %q, want park_course_attempts.json", spec.name)
	}
	if spec.filter != "user_id=eq.user-A" {
		t.Errorf("filter %q, want the subject's own rows by user_id", spec.filter)
	}
	if spec.sel != "*" {
		t.Errorf("select %q, want every column", spec.sel)
	}
}
