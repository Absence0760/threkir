package internal

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"testing"

	"github.com/Absence0760/threkir/apps/job_worker/internal/schema"
)

func orphanBackend(present []string, orphans []string) *fakeBackend {
	objs := make([]StorageObject, 0, len(present))
	for _, p := range present {
		objs = append(objs, StorageObject{Path: p})
	}
	return &fakeBackend{
		storageObjects:    map[string][]StorageObject{schema.BucketRoutePhotos: objs},
		routePhotoOrphans: orphans,
	}
}

func orphanJob(t *testing.T, payload string) *Job {
	t.Helper()
	return &Job{Kind: "route_photo_orphan_sweep", Payload: json.RawMessage(payload)}
}

func TestRoutePhotoOrphanSweep_BackstopErasesOnlyTheWorklist(t *testing.T) {
	be := orphanBackend(
		[]string{"u1/live.jpg", "u1/orphan.jpg", "u2/orphan_512.jpg"},
		[]string{"u1/orphan.jpg", "u2/orphan_512.jpg"},
	)
	w := newTestWorker(be, nil)

	if err := w.handleRoutePhotoOrphanSweep(context.Background(), orphanJob(t, `{}`)); err != nil {
		t.Fatalf("handleRoutePhotoOrphanSweep: %v", err)
	}
	if len(be.routePhotoOrphanArgs) == 0 || be.routePhotoOrphanArgs[0] != nil {
		t.Fatalf("backstop must ask for the unscoped worklist (nil paths), got %v", be.routePhotoOrphanArgs)
	}
	left := be.storageObjects[schema.BucketRoutePhotos]
	if len(left) != 1 || left[0].Path != "u1/live.jpg" {
		t.Fatalf("bucket left holding %v, want only the referenced photo", left)
	}
}

func TestRoutePhotoOrphanSweep_PathsPayloadIsScoped(t *testing.T) {
	be := orphanBackend(
		[]string{"u1/a.jpg", "u1/a_512.jpg", "u1/elsewhere.jpg"},
		[]string{"u1/a.jpg", "u1/a_512.jpg", "u1/elsewhere.jpg"},
	)
	w := newTestWorker(be, nil)

	if err := w.handleRoutePhotoOrphanSweep(context.Background(),
		orphanJob(t, `{"paths":["u1/a.jpg","u1/a_512.jpg"]}`)); err != nil {
		t.Fatalf("handleRoutePhotoOrphanSweep: %v", err)
	}
	left := be.storageObjects[schema.BucketRoutePhotos]
	if len(left) != 1 || left[0].Path != "u1/elsewhere.jpg" {
		t.Fatalf("bucket left holding %v; a paths job must erase only its own paths", left)
	}
}

// A trigger payload whose list came out empty is not a request for the
// unscoped backstop.
func TestRoutePhotoOrphanSweep_EmptyPathsListIsNotTheBackstop(t *testing.T) {
	be := orphanBackend([]string{"u1/orphan.jpg"}, []string{"u1/orphan.jpg"})
	w := newTestWorker(be, nil)

	if err := w.handleRoutePhotoOrphanSweep(context.Background(), orphanJob(t, `{"paths":[]}`)); err != nil {
		t.Fatalf("handleRoutePhotoOrphanSweep: %v", err)
	}
	if len(be.routePhotoOrphanArgs) != 0 || len(be.storageDeleted) != 0 {
		t.Fatalf("an empty paths list read the worklist %v and deleted %v", be.routePhotoOrphanArgs, be.storageDeleted)
	}
}

func TestRoutePhotoOrphanSweep_BatchesAndStopsAtTheBound(t *testing.T) {
	total := RoutePhotoOrphanBatchSize*RoutePhotoOrphanMaxBatches + 7
	var paths []string
	for i := 0; i < total; i++ {
		paths = append(paths, fmt.Sprintf("u1/%05d.jpg", i))
	}
	be := orphanBackend(paths, paths)
	w := newTestWorker(be, nil)

	res, err := w.sweepRoutePhotoOrphans(context.Background(), nil)
	if err != nil {
		t.Fatalf("sweepRoutePhotoOrphans: %v", err)
	}
	if res.Batches != RoutePhotoOrphanMaxBatches || !res.Exhausted {
		t.Fatalf("result %+v, want %d batches and the bound reported", res, RoutePhotoOrphanMaxBatches)
	}
	for _, call := range be.storageDeleted {
		if len(call) > RoutePhotoOrphanBatchSize {
			t.Fatalf("one DELETE carried %d paths, bound is %d", len(call), RoutePhotoOrphanBatchSize)
		}
	}
	if left := len(be.storageObjects[schema.BucketRoutePhotos]); left != 7 {
		t.Fatalf("%d objects left, want the 7 past the per-run bound for the next night", left)
	}

	// The next run picks up exactly where this one stopped.
	res, err = w.sweepRoutePhotoOrphans(context.Background(), nil)
	if err != nil || res.Deleted != 7 || res.Exhausted {
		t.Fatalf("second run %+v, %v; want the remaining 7 and no bound", res, err)
	}
}

// Storage's multi-delete answers 200 for a name that matches nothing. If the
// worklist keeps reporting a path this run already deleted, the erase did not
// happen and the job must fail rather than spin to the bound and log success.
func TestRoutePhotoOrphanSweep_FailsWhenStorageDidNotErase(t *testing.T) {
	be := orphanBackend([]string{"u1/stuck.jpg"}, []string{"u1/stuck.jpg"})
	be.storageDeleteIgnored = true
	// One full batch, so the sweep asks again instead of stopping on a short
	// page.
	for i := 1; i < RoutePhotoOrphanBatchSize; i++ {
		p := fmt.Sprintf("u1/stuck-%03d.jpg", i)
		be.storageObjects[schema.BucketRoutePhotos] = append(be.storageObjects[schema.BucketRoutePhotos], StorageObject{Path: p})
		be.routePhotoOrphans = append(be.routePhotoOrphans, p)
	}
	w := newTestWorker(be, nil)

	err := w.handleRoutePhotoOrphanSweep(context.Background(), orphanJob(t, `{}`))
	if err == nil || !strings.Contains(err.Error(), "did not erase") {
		t.Fatalf("err = %v, want the not-erased failure", err)
	}
	if len(be.storageDeleted) != 1 {
		t.Fatalf("DELETE calls = %d, want 1 before the failure", len(be.storageDeleted))
	}
}

func TestRoutePhotoOrphanSweep_WorklistErrorFailsTheJob(t *testing.T) {
	be := orphanBackend([]string{"u1/orphan.jpg"}, []string{"u1/orphan.jpg"})
	be.routePhotoOrphanErr = errors.New("rpc down")
	w := newTestWorker(be, nil)

	if err := w.handleRoutePhotoOrphanSweep(context.Background(), orphanJob(t, `{}`)); err == nil {
		t.Fatal("a failed worklist read must fail the job")
	}
	if len(be.storageDeleted) != 0 {
		t.Fatalf("deleted %v with no worklist", be.storageDeleted)
	}
}

// A refused DELETE fails the job and keeps the batches already erased: a
// retry re-reads the worklist, so it cannot repeat them.
func TestRoutePhotoOrphanSweep_DeleteErrorFailsTheJobKeepingProgress(t *testing.T) {
	var paths []string
	for i := 0; i < RoutePhotoOrphanBatchSize+3; i++ {
		paths = append(paths, fmt.Sprintf("u1/%04d.jpg", i))
	}
	be := orphanBackend(paths, paths)
	be.storageDeleteErrAfter = 1
	w := newTestWorker(be, nil)

	res, err := w.sweepRoutePhotoOrphans(context.Background(), nil)
	if err == nil {
		t.Fatal("a refused DELETE must fail the job")
	}
	if res.Deleted != RoutePhotoOrphanBatchSize {
		t.Fatalf("deleted %d, want the first full batch kept", res.Deleted)
	}
	if left := len(be.storageObjects[schema.BucketRoutePhotos]); left != 3 {
		t.Fatalf("%d left, want the 3 the refused batch held", left)
	}
}

// The log line is counts only: a path is `{user_id}/{photo_id}`.
func TestRoutePhotoOrphanSweep_LogsNoPaths(t *testing.T) {
	be := orphanBackend([]string{"secret-user/photo.jpg"}, []string{"secret-user/photo.jpg"})
	w := newTestWorker(be, nil)
	var buf bytes.Buffer
	w.Log = slog.New(slog.NewTextHandler(&buf, nil))

	if err := w.handleRoutePhotoOrphanSweep(context.Background(),
		orphanJob(t, `{"paths":["secret-user/photo.jpg"]}`)); err != nil {
		t.Fatalf("handleRoutePhotoOrphanSweep: %v", err)
	}
	if strings.Contains(buf.String(), "secret-user") {
		t.Fatalf("log line carries a path: %s", buf.String())
	}
	if !strings.Contains(buf.String(), "deleted=1") {
		t.Fatalf("log line lost the count: %s", buf.String())
	}
}

func TestRoutePhotoOrphanSweep_DispatchRoutesTheKind(t *testing.T) {
	be := orphanBackend([]string{"u1/orphan.jpg"}, []string{"u1/orphan.jpg"})
	w := newTestWorker(be, nil)
	if err := w.dispatch(context.Background(), orphanJob(t, `{}`)); err != nil {
		t.Fatalf("dispatch: %v", err)
	}
	if len(be.storageDeleted) != 1 {
		t.Fatalf("dispatch did not reach the sweep: %v", be.storageDeleted)
	}
}

// The RPC body is what PostgREST binds to `route_photo_orphan_paths`: a nil
// slice must reach SQL as NULL (the graced backstop), never as `[]`, and a
// scoped call carries its paths.
func TestSupabaseClient_RoutePhotoOrphanPathsBody(t *testing.T) {
	var bodies []map[string]any
	srv := httptest.NewServer(http.HandlerFunc(func(rw http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/rest/v1/rpc/route_photo_orphan_paths" {
			t.Errorf("path = %s", r.URL.Path)
		}
		raw, _ := io.ReadAll(r.Body)
		var m map[string]any
		_ = json.Unmarshal(raw, &m)
		bodies = append(bodies, m)
		_, _ = rw.Write([]byte(`["u1/a.jpg"]`))
	}))
	defer srv.Close()
	c := NewSupabaseClient(srv.URL, "service-key")

	got, err := c.RoutePhotoOrphanPaths(context.Background(), nil, 100)
	if err != nil || len(got) != 1 || got[0] != "u1/a.jpg" {
		t.Fatalf("got %v, %v", got, err)
	}
	if _, err := c.RoutePhotoOrphanPaths(context.Background(), []string{"u1/b.jpg"}, 50); err != nil {
		t.Fatal(err)
	}
	if v, ok := bodies[0]["p_paths"]; !ok || v != nil {
		t.Fatalf("backstop body p_paths = %#v, want JSON null", v)
	}
	if bodies[0]["p_limit"] != float64(100) {
		t.Fatalf("p_limit = %#v", bodies[0]["p_limit"])
	}
	ps, _ := bodies[1]["p_paths"].([]any)
	if len(ps) != 1 || ps[0] != "u1/b.jpg" {
		t.Fatalf("scoped body p_paths = %#v", bodies[1]["p_paths"])
	}
}

// The delete trigger caps a paths job at its v_cap, and one run of this
// handler erases at most RoutePhotoOrphanMaxBatches x RoutePhotoOrphanBatchSize
// objects. A cap above that budget would leave the tail of every full job to
// the nightly backstop while the job reports success. The worklist clamp is
// the other half: a clamp below the batch size returns a short page, which
// this handler reads as "nothing left".
//
// Both numbers are read from the LAST migration that defines each function,
// in the version order release-backend applies them, so a later
// `create or replace` cannot move either one past this guard.
func TestRoutePhotoOrphanSweep_MigrationCapFitsOneRun(t *testing.T) {
	migrations, err := readMigrations(filepath.Join("..", "..", "backend", "supabase", "migrations"))
	if err != nil {
		t.Fatal(err)
	}
	only := func(fn string, re *regexp.Regexp, what string) int {
		t.Helper()
		file, body, ok := lastFunctionBody(migrations, fn)
		if !ok {
			t.Fatalf("no migration defines public.%s", fn)
		}
		m := re.FindAllStringSubmatch(body, -1)
		if len(m) != 1 {
			t.Fatalf("found %d %s in public.%s as %s last defines it, want exactly 1",
				len(m), what, fn, file)
		}
		n, err := strconv.Atoi(m[0][1])
		if err != nil {
			t.Fatal(err)
		}
		return n
	}
	pathCap := only("flush_route_photo_orphan_sweep",
		regexp.MustCompile(`v_cap\s+constant\s+integer\s*:=\s*(\d+)\s*;`), "v_cap declarations")
	clamp := only("route_photo_orphan_paths",
		regexp.MustCompile(`least\(greatest\(coalesce\(p_limit,\s*\d+\),\s*1\),\s*(\d+)\)`), "p_limit clamps")

	if budget := RoutePhotoOrphanMaxBatches * RoutePhotoOrphanBatchSize; pathCap > budget {
		t.Fatalf("the delete trigger queues up to %d paths a job, but one run erases at most %d x %d = %d",
			pathCap, RoutePhotoOrphanMaxBatches, RoutePhotoOrphanBatchSize, budget)
	}
	if clamp < RoutePhotoOrphanBatchSize {
		t.Fatalf("route_photo_orphan_paths clamps p_limit to %d, below the handler's batch of %d",
			clamp, RoutePhotoOrphanBatchSize)
	}
}

func TestLastFunctionBody_TakesTheLatestVersionNotTheLatestFilename(t *testing.T) {
	migrations := sortMigrations([]migration{
		{name: "20271201_001_later.sql", src: "create or replace function public.f(a int)\nreturns int as $$ select 3 $$;\n"},
		{name: "20271106000020_first.sql", src: "create function public.f(a int)\nreturns int as $$ select 1 $$;\n" +
			"create or replace function public.f_other()\nreturns int as $$ select 9 $$;\n"},
		{name: "20271106_001_eight_digit.sql", src: "create or replace function f(a int) returns int as $$ select 2 $$;\n"},
	})
	file, body, ok := lastFunctionBody(migrations, "f")
	if !ok || file != "20271201_001_later.sql" || !strings.Contains(body, "select 3") {
		t.Fatalf("lastFunctionBody = %q, %q, %v", file, body, ok)
	}
	if strings.Contains(body, "select 9") {
		t.Fatalf("body ran into the next definition: %q", body)
	}
	if _, _, ok := lastFunctionBody(migrations, "missing"); ok {
		t.Fatal("found a function no migration defines")
	}
}

type migration struct{ name, src string }

func readMigrations(dir string) ([]migration, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	var out []migration
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".sql") {
			continue
		}
		b, err := os.ReadFile(filepath.Join(dir, e.Name()))
		if err != nil {
			return nil, err
		}
		out = append(out, migration{name: e.Name(), src: string(b)})
	}
	return sortMigrations(out), nil
}

// sortMigrations orders by the version key the CLI and
// scripts/apply-pending-migrations.sh use (the digits before the first
// underscore, compared as strings), not by filename: '20260601' applies
// before '20260601000001' although '_' sorts after '0'.
func sortMigrations(ms []migration) []migration {
	version := func(name string) string {
		if i := strings.IndexByte(name, '_'); i >= 0 {
			return name[:i]
		}
		return name
	}
	sort.SliceStable(ms, func(i, j int) bool { return version(ms[i].name) < version(ms[j].name) })
	return ms
}

// lastFunctionBody returns the text of the last definition of public.<fn>
// across migrations in apply order, from its `create` to the next `$$;`.
func lastFunctionBody(ms []migration, fn string) (file, body string, ok bool) {
	def := regexp.MustCompile(`(?i)create\s+(?:or\s+replace\s+)?function\s+(?:public\.)?` +
		regexp.QuoteMeta(fn) + `\s*\(`)
	for _, m := range ms {
		locs := def.FindAllStringIndex(m.src, -1)
		if len(locs) == 0 {
			continue
		}
		rest := m.src[locs[len(locs)-1][0]:]
		open := strings.Index(rest, "$$")
		if open < 0 {
			continue
		}
		end := strings.Index(rest[open+2:], "$$")
		if end < 0 {
			continue
		}
		file, body, ok = m.name, rest[:open+2+end+2], true
	}
	return file, body, ok
}
