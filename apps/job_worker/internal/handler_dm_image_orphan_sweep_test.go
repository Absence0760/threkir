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
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"testing"

	"github.com/Absence0760/threkir/apps/job_worker/internal/schema"
)

func dmOrphanBackend(present []string, orphans []string) *fakeBackend {
	objs := make([]StorageObject, 0, len(present))
	for _, p := range present {
		objs = append(objs, StorageObject{Path: p})
	}
	return &fakeBackend{
		storageObjects: map[string][]StorageObject{schema.BucketDmImages: objs},
		dm:             &fakeDmImages{orphans: orphans},
	}
}

func dmOrphanJob(payload string) *Job {
	return &Job{Kind: "dm_image_orphan_sweep", Payload: json.RawMessage(payload)}
}

func TestDmImageOrphanSweep_BackstopErasesOnlyTheWorklist(t *testing.T) {
	be := dmOrphanBackend(
		[]string{"u1/held.jpg", "u1/gone.jpg", "u2/gone/upload"},
		[]string{"u1/gone.jpg", "u2/gone/upload"},
	)
	w := newTestWorker(be, nil)

	if err := w.handleDmImageOrphanSweep(context.Background(), dmOrphanJob(`{}`)); err != nil {
		t.Fatalf("handleDmImageOrphanSweep: %v", err)
	}
	if len(be.dm.orphanArgs) == 0 || be.dm.orphanArgs[0] != nil {
		t.Fatalf("backstop must ask for the unscoped worklist (nil paths), got %v", be.dm.orphanArgs)
	}
	left := be.storageObjects[schema.BucketDmImages]
	if len(left) != 1 || left[0].Path != "u1/held.jpg" {
		t.Fatalf("bucket left holding %v, want only the referenced image", left)
	}
}

func TestDmImageOrphanSweep_PathsPayloadIsScoped(t *testing.T) {
	be := dmOrphanBackend(
		[]string{"u1/a/upload", "u1/a.jpg", "u1/elsewhere.jpg"},
		[]string{"u1/a/upload", "u1/a.jpg", "u1/elsewhere.jpg"},
	)
	w := newTestWorker(be, nil)

	if err := w.handleDmImageOrphanSweep(context.Background(),
		dmOrphanJob(`{"paths":["u1/a/upload","u1/a.jpg"]}`)); err != nil {
		t.Fatalf("handleDmImageOrphanSweep: %v", err)
	}
	left := be.storageObjects[schema.BucketDmImages]
	if len(left) != 1 || left[0].Path != "u1/elsewhere.jpg" {
		t.Fatalf("bucket left holding %v; a paths job must erase only its own paths", left)
	}
	for _, call := range be.storageDeleted {
		if slicesContains(call, "u1/elsewhere.jpg") {
			t.Fatal("a paths job deleted a path outside its payload")
		}
	}
}

func TestDmImageOrphanSweep_EmptyPathsListIsNotTheBackstop(t *testing.T) {
	be := dmOrphanBackend([]string{"u1/orphan.jpg"}, []string{"u1/orphan.jpg"})
	w := newTestWorker(be, nil)

	if err := w.handleDmImageOrphanSweep(context.Background(), dmOrphanJob(`{"paths":[]}`)); err != nil {
		t.Fatalf("handleDmImageOrphanSweep: %v", err)
	}
	if len(be.dm.orphanArgs) != 0 || len(be.storageDeleted) != 0 {
		t.Fatalf("an empty paths list read the worklist %v and deleted %v", be.dm.orphanArgs, be.storageDeleted)
	}
}

func TestDmImageOrphanSweep_BatchesAndStopsAtTheBound(t *testing.T) {
	total := DmImageOrphanBatchSize*DmImageOrphanMaxBatches + 7
	var paths []string
	for i := 0; i < total; i++ {
		paths = append(paths, fmt.Sprintf("u1/%05d.jpg", i))
	}
	be := dmOrphanBackend(paths, paths)
	w := newTestWorker(be, nil)

	res, err := w.sweepDmImageOrphans(context.Background(), nil)
	if err != nil {
		t.Fatalf("sweepDmImageOrphans: %v", err)
	}
	if res.Batches != DmImageOrphanMaxBatches || !res.Exhausted {
		t.Fatalf("result %+v, want %d batches and the bound reported", res, DmImageOrphanMaxBatches)
	}
	for _, call := range be.storageDeleted {
		if len(call) > DmImageOrphanBatchSize {
			t.Fatalf("one DELETE carried %d paths, bound is %d", len(call), DmImageOrphanBatchSize)
		}
	}
	if left := len(be.storageObjects[schema.BucketDmImages]); left != 7 {
		t.Fatalf("%d objects left, want the 7 past the per-run bound", left)
	}
	res, err = w.sweepDmImageOrphans(context.Background(), nil)
	if err != nil || res.Deleted != 7 || res.Exhausted {
		t.Fatalf("second run %+v, %v; want the remaining 7 and no bound", res, err)
	}
}

func TestDmImageOrphanSweep_FailsWhenStorageDidNotErase(t *testing.T) {
	be := dmOrphanBackend([]string{"u1/stuck.jpg"}, []string{"u1/stuck.jpg"})
	be.storageDeleteIgnored = true
	for i := 1; i < DmImageOrphanBatchSize; i++ {
		p := fmt.Sprintf("u1/stuck-%03d.jpg", i)
		be.storageObjects[schema.BucketDmImages] = append(be.storageObjects[schema.BucketDmImages], StorageObject{Path: p})
		be.dm.orphans = append(be.dm.orphans, p)
	}
	w := newTestWorker(be, nil)

	err := w.handleDmImageOrphanSweep(context.Background(), dmOrphanJob(`{}`))
	if err == nil || !strings.Contains(err.Error(), "did not erase") {
		t.Fatalf("err = %v, want the not-erased failure", err)
	}
	if len(be.storageDeleted) != 1 {
		t.Fatalf("DELETE calls = %d, want 1 before the failure", len(be.storageDeleted))
	}
}

func TestDmImageOrphanSweep_WorklistErrorFailsTheJob(t *testing.T) {
	be := dmOrphanBackend([]string{"u1/orphan.jpg"}, []string{"u1/orphan.jpg"})
	be.dm.orphanErr = errors.New("rpc down")
	w := newTestWorker(be, nil)

	if err := w.handleDmImageOrphanSweep(context.Background(), dmOrphanJob(`{}`)); err == nil {
		t.Fatal("a failed worklist read must fail the job")
	}
	if len(be.storageDeleted) != 0 {
		t.Fatalf("deleted %v with no worklist", be.storageDeleted)
	}
}

func TestDmImageOrphanSweep_DeleteErrorFailsTheJobKeepingProgress(t *testing.T) {
	var paths []string
	for i := 0; i < DmImageOrphanBatchSize+3; i++ {
		paths = append(paths, fmt.Sprintf("u1/%04d.jpg", i))
	}
	be := dmOrphanBackend(paths, paths)
	be.storageDeleteErrAfter = 1
	w := newTestWorker(be, nil)

	res, err := w.sweepDmImageOrphans(context.Background(), nil)
	if err == nil {
		t.Fatal("a refused DELETE must fail the job")
	}
	if res.Deleted != DmImageOrphanBatchSize {
		t.Fatalf("deleted %d, want the first full batch kept", res.Deleted)
	}
}

func TestDmImageOrphanSweep_LogsNoPaths(t *testing.T) {
	be := dmOrphanBackend([]string{"secret-user/img.jpg"}, []string{"secret-user/img.jpg"})
	w := newTestWorker(be, nil)
	var buf bytes.Buffer
	w.Log = slog.New(slog.NewTextHandler(&buf, nil))

	if err := w.handleDmImageOrphanSweep(context.Background(),
		dmOrphanJob(`{"paths":["secret-user/img.jpg"]}`)); err != nil {
		t.Fatalf("handleDmImageOrphanSweep: %v", err)
	}
	if strings.Contains(buf.String(), "secret-user") {
		t.Fatalf("log line carries a path: %s", buf.String())
	}
	if !strings.Contains(buf.String(), "deleted=1") {
		t.Fatalf("log line lost the count: %s", buf.String())
	}
}

func TestDmImageOrphanSweep_DispatchRoutesTheKindToTheDmBucket(t *testing.T) {
	be := dmOrphanBackend([]string{"u1/orphan.jpg"}, []string{"u1/orphan.jpg"})
	be.storageObjects[schema.BucketRoutePhotos] = []StorageObject{{Path: "u1/orphan.jpg"}}
	w := newTestWorker(be, nil)
	if err := w.dispatch(context.Background(), dmOrphanJob(`{}`)); err != nil {
		t.Fatalf("dispatch: %v", err)
	}
	if len(be.storageObjects[schema.BucketDmImages]) != 0 || len(be.storageObjects[schema.BucketRoutePhotos]) != 1 {
		t.Fatalf("sweep erased in the wrong bucket: %v", be.storageObjects)
	}
}

func TestSupabaseClient_DmImageOrphanPathsBody(t *testing.T) {
	var bodies []map[string]any
	srv := httptest.NewServer(http.HandlerFunc(func(rw http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/rest/v1/rpc/dm_image_orphan_paths" {
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

	got, err := c.DmImageOrphanPaths(context.Background(), nil, 100)
	if err != nil || len(got) != 1 || got[0] != "u1/a.jpg" {
		t.Fatalf("got %v, %v", got, err)
	}
	if _, err := c.DmImageOrphanPaths(context.Background(), []string{"u1/b.jpg"}, 50); err != nil {
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

// The delete trigger chunks a statement's paths into jobs of N, and one run
// of this handler erases at most DmImageOrphanMaxBatches x
// DmImageOrphanBatchSize; the worklist clamp must not fall below one batch.
// Both are read from the last migration defining each function.
func TestDmImageOrphanSweep_MigrationChunkFitsOneRun(t *testing.T) {
	migrations, err := readMigrations(filepath.Join("..", "..", "backend", "supabase", "migrations"))
	if err != nil {
		t.Fatal(err)
	}
	lastBody := func(qualified string) string {
		t.Helper()
		def := regexp.MustCompile(`(?i)create\s+(?:or\s+replace\s+)?function\s+` + regexp.QuoteMeta(qualified) + `\s*\(`)
		var body string
		for _, m := range migrations {
			locs := def.FindAllStringIndex(m.src, -1)
			if len(locs) == 0 {
				continue
			}
			rest := m.src[locs[len(locs)-1][0]:]
			open := strings.Index(rest, "$$")
			end := strings.Index(rest[open+2:], "$$")
			body = rest[:open+2+end+2]
		}
		if body == "" {
			t.Fatalf("no migration defines %s", qualified)
		}
		return body
	}
	num := func(body string, re *regexp.Regexp, what string) int {
		t.Helper()
		m := re.FindAllStringSubmatch(body, -1)
		if len(m) != 1 {
			t.Fatalf("found %d %s, want exactly 1", len(m), what)
		}
		n, _ := strconv.Atoi(m[0][1])
		return n
	}
	chunk := num(lastBody("private.direct_message_images_enqueue_erase"),
		regexp.MustCompile(`generate_series\(1,\s*cardinality\(v_paths\),\s*(\d+)\)`), "path chunk sizes")
	clamp := num(lastBody("public.dm_image_orphan_paths"),
		regexp.MustCompile(`least\(greatest\(coalesce\(p_limit,\s*\d+\),\s*1\),\s*(\d+)\)`), "p_limit clamps")

	if budget := DmImageOrphanMaxBatches * DmImageOrphanBatchSize; chunk > budget {
		t.Fatalf("the delete trigger queues up to %d paths a job, but one run erases at most %d", chunk, budget)
	}
	if clamp < DmImageOrphanBatchSize {
		t.Fatalf("dm_image_orphan_paths clamps p_limit to %d, below the batch of %d", clamp, DmImageOrphanBatchSize)
	}
}
