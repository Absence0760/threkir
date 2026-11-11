package internal

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"image"
	"image/color"
	"image/jpeg"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"

	"github.com/Absence0760/threkir/apps/job_worker/internal/schema"
)

type fakeDmRow struct {
	DmImage
	width, height int
}

type fakeDmImages struct {
	rows    map[string]*fakeDmRow
	objects map[string][]byte

	fetchErr    error
	downloadErr error
	uploadErr   error
	markErr     error
	// rowGoneBeforeMark deletes the row as the worker marks it, as an
	// unsend or a purge landing mid-job does.
	rowGoneBeforeMark bool
	// settledBeforeMark sets the row to this status as the worker marks it,
	// as another attempt of the same job finishing first does.
	settledBeforeMark string
	// refetchErr fails every FetchDmImage after the first.
	refetchErr error
	fetches    int

	orphans    []string
	orphanErr  error
	orphanArgs [][]string
}

func (f *fakeBackend) FetchDmImage(_ context.Context, id string) (*DmImage, error) {
	if f.dm.fetchErr != nil {
		return nil, f.dm.fetchErr
	}
	f.dm.fetches++
	if f.dm.fetches > 1 && f.dm.refetchErr != nil {
		return nil, f.dm.refetchErr
	}
	r, ok := f.dm.rows[id]
	if !ok {
		return nil, nil
	}
	img := r.DmImage
	return &img, nil
}

func (f *fakeBackend) DownloadDmImage(_ context.Context, path string, maxBytes int64) ([]byte, error) {
	if f.dm.downloadErr != nil {
		return nil, f.dm.downloadErr
	}
	b, ok := f.dm.objects[path]
	if !ok {
		return nil, &HTTPError{StatusCode: http.StatusBadRequest}
	}
	if int64(len(b)) > maxBytes {
		return nil, ErrDmImageTooLarge
	}
	return b, nil
}

func (f *fakeBackend) UploadDmImage(_ context.Context, path string, body []byte) error {
	if f.dm.uploadErr != nil {
		return f.dm.uploadErr
	}
	f.dm.objects[path] = body
	return nil
}

func (f *fakeBackend) markDm(id, status string, w, h int) (bool, error) {
	if f.dm.markErr != nil {
		return false, f.dm.markErr
	}
	if f.dm.rowGoneBeforeMark {
		delete(f.dm.rows, id)
		return false, nil
	}
	if f.dm.settledBeforeMark != "" {
		f.dm.rows[id].Status = f.dm.settledBeforeMark
		return false, nil
	}
	if r, ok := f.dm.rows[id]; ok && r.Status == "pending" {
		r.Status, r.width, r.height = status, w, h
		return true, nil
	}
	return false, nil
}

func (f *fakeBackend) MarkDmImageReady(_ context.Context, id string, w, h int) (bool, error) {
	return f.markDm(id, "ready", w, h)
}

func (f *fakeBackend) MarkDmImageRejected(_ context.Context, id string) (bool, error) {
	return f.markDm(id, "rejected", 0, 0)
}

func (f *fakeBackend) DmImageOrphanPaths(_ context.Context, paths []string, limit int) ([]string, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.dm.orphanArgs = append(f.dm.orphanArgs, paths)
	if f.dm.orphanErr != nil {
		return nil, f.dm.orphanErr
	}
	var out []string
	for _, o := range f.storageObjects[schema.BucketDmImages] {
		if len(out) == limit {
			break
		}
		if !slicesContains(f.dm.orphans, o.Path) {
			continue
		}
		if paths != nil && !slicesContains(paths, o.Path) {
			continue
		}
		out = append(out, o.Path)
	}
	return out, nil
}

const (
	dmImageID  = "0b9c3f1e-2a4d-4e8f-9c1b-7d6e5f4a3b2c"
	dmOwner    = "secret-owner"
	dmUpload   = dmOwner + "/" + dmImageID + "/upload"
	dmReencode = dmOwner + "/" + dmImageID + ".jpg"
)

func dmBackend(status string, upload []byte) *fakeBackend {
	be := &fakeBackend{
		storageObjects: map[string][]StorageObject{},
		dm: &fakeDmImages{
			rows: map[string]*fakeDmRow{dmImageID: {DmImage: DmImage{
				ID: dmImageID, Status: status, UploadPath: dmUpload, StoragePath: dmReencode,
			}}},
			objects: map[string][]byte{},
		},
	}
	if upload != nil {
		be.dm.objects[dmUpload] = upload
	}
	return be
}

func dmJob() *Job {
	return &Job{ID: 1, Kind: "dm_image_process", Payload: json.RawMessage(`{"image_id":"` + dmImageID + `"}`)}
}

func dmPhoto(t *testing.T, w, h int) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			img.Set(x, y, color.RGBA{R: uint8(x), G: uint8(y), B: 40, A: 255})
		}
	}
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, img, nil); err != nil {
		t.Fatal(err)
	}
	b := buf.Bytes()
	// An APP1 segment straight after SOI, the place a camera writes EXIF.
	exifSeg := append([]byte{0xFF, 0xE1, 0x00, 0x14}, []byte("Exif\x00\x00GPSLat51.50")...)
	return append(append(append([]byte{}, b[:2]...), exifSeg...), b[2:]...)
}

func uploadDeleted(be *fakeBackend) bool {
	for _, call := range be.storageDeleted {
		if slicesContains(call, dmUpload) {
			return true
		}
	}
	return false
}

func TestDmImageProcess_PendingBecomesReadyWithItsSize(t *testing.T) {
	be := dmBackend("pending", dmPhoto(t, 3000, 1500))
	w := newTestWorker(be, nil)

	if err := w.dispatch(context.Background(), dmJob()); err != nil {
		t.Fatalf("dispatch: %v", err)
	}
	row := be.dm.rows[dmImageID]
	if row.Status != "ready" || row.width != 2048 || row.height != 1024 {
		t.Fatalf("row = %s %dx%d, want ready 2048x1024", row.Status, row.width, row.height)
	}
	out, ok := be.dm.objects[dmReencode]
	if !ok {
		t.Fatal("no re-encoded object at storage_path")
	}
	if bytes.Contains(out, []byte("Exif")) || bytes.Contains(out, []byte("GPS")) {
		t.Fatal("re-encode still carries the EXIF segment")
	}
	cfg, err := jpeg.DecodeConfig(bytes.NewReader(out))
	if err != nil || cfg.Width != 2048 || cfg.Height != 1024 {
		t.Fatalf("re-encode decodes to %+v, %v", cfg, err)
	}
	if !uploadDeleted(be) {
		t.Fatalf("upload not deleted; DELETEs = %v", be.storageDeleted)
	}
}

func TestDmImageProcess_RowSettledElsewhereKeepsItsObjects(t *testing.T) {
	for _, status := range []string{"ready", "rejected"} {
		be := dmBackend("pending", dmPhoto(t, 64, 48))
		be.dm.settledBeforeMark = status
		w := newTestWorker(be, nil)

		if err := w.dispatch(context.Background(), dmJob()); err != nil {
			t.Fatalf("%s: dispatch: %v", status, err)
		}
		if len(be.storageDeleted) != 0 {
			t.Fatalf("%s: deleted objects a %s row names; DELETEs = %v", status, status, be.storageDeleted)
		}
		if _, ok := be.dm.objects[dmReencode]; !ok {
			t.Fatalf("%s: the re-encode is gone", status)
		}
		if got := be.dm.rows[dmImageID].Status; got != status {
			t.Fatalf("row status = %q, want %q", got, status)
		}
	}
}

func TestDmImageProcess_RowGoneMidJobErasesBothPaths(t *testing.T) {
	be := dmBackend("pending", dmPhoto(t, 64, 48))
	be.dm.rowGoneBeforeMark = true
	w := newTestWorker(be, nil)

	if err := w.dispatch(context.Background(), dmJob()); err != nil {
		t.Fatalf("dispatch: %v", err)
	}
	if len(be.storageDeleted) != 1 || !slicesContains(be.storageDeleted[0], dmReencode) || !slicesContains(be.storageDeleted[0], dmUpload) {
		t.Fatalf("want one DELETE of the re-encode and the upload; DELETEs = %v", be.storageDeleted)
	}
}

func TestDmImageProcess_RereadFailureRetriesAndDeletesNothing(t *testing.T) {
	be := dmBackend("pending", dmPhoto(t, 64, 48))
	be.dm.settledBeforeMark = "ready"
	be.dm.refetchErr = errors.New("connection reset")
	w := newTestWorker(be, nil)

	if err := w.dispatch(context.Background(), dmJob()); err == nil {
		t.Fatal("dispatch succeeded on a failed re-read")
	}
	if len(be.storageDeleted) != 0 {
		t.Fatalf("deleted without knowing whether the row exists; DELETEs = %v", be.storageDeleted)
	}
}

func TestDmImageProcess_DecoderPanicRejectsTheRow(t *testing.T) {
	prev := reencodeDmImage
	reencodeDmImage = func([]byte, int, int, int) ([]byte, int, int, error) { panic("boom") }
	defer func() { reencodeDmImage = prev }()
	be := dmBackend("pending", dmPhoto(t, 64, 48))
	w := newTestWorker(be, nil)

	if err := w.dispatch(context.Background(), dmJob()); err != nil {
		t.Fatalf("dispatch: %v", err)
	}
	if got := be.dm.rows[dmImageID].Status; got != "rejected" {
		t.Fatalf("status = %s, want rejected", got)
	}
}

func TestDmImageProcess_PixelCapFitsTheClientContract(t *testing.T) {
	if DmImageMaxPixels < DmImageMaxLongSide*DmImageMaxLongSide || DmImageMaxPixels > 10_000_000 {
		t.Fatalf("DmImageMaxPixels = %d: must admit a 2048 x 2048 upload and stay far below the 40 MP that measured over 300 MB", DmImageMaxPixels)
	}
}

func TestDmImageProcess_NonPendingOrMissingRowIsANoOp(t *testing.T) {
	for _, status := range []string{"ready", "rejected", ""} {
		be := dmBackend(status, dmPhoto(t, 10, 10))
		if status == "" {
			delete(be.dm.rows, dmImageID)
		}
		w := newTestWorker(be, nil)
		if err := w.handleDmImageProcess(context.Background(), dmJob()); err != nil {
			t.Fatalf("%q: %v", status, err)
		}
		if _, ok := be.dm.objects[dmReencode]; ok || len(be.storageDeleted) != 0 {
			t.Fatalf("%q: touched storage (wrote %v, deleted %v)", status, ok, be.storageDeleted)
		}
	}
}

func TestDmImageProcess_UnusableUploadIsRejectedAndDeleted(t *testing.T) {
	cases := map[string]*fakeBackend{
		"missing upload": dmBackend("pending", nil),
		"not an image":   dmBackend("pending", []byte("not an image at all")),
		"over the limit": dmBackend("pending", make([]byte, DmImageMaxBytes+1)),
	}
	notFound := dmBackend("pending", dmPhoto(t, 4, 4))
	notFound.dm.downloadErr = &HTTPError{StatusCode: http.StatusNotFound}
	cases["storage 404"] = notFound

	for name, be := range cases {
		w := newTestWorker(be, nil)
		if err := w.handleDmImageProcess(context.Background(), dmJob()); err != nil {
			t.Fatalf("%s: a rejection is done, not an error: %v", name, err)
		}
		if got := be.dm.rows[dmImageID].Status; got != "rejected" {
			t.Fatalf("%s: status = %s, want rejected", name, got)
		}
		if _, ok := be.dm.objects[dmReencode]; ok {
			t.Fatalf("%s: wrote a re-encode for a rejected upload", name)
		}
		if !uploadDeleted(be) {
			t.Fatalf("%s: upload not deleted", name)
		}
	}
}

func TestDmImageProcess_TransientFailuresRetryAndLeaveTheRowPending(t *testing.T) {
	cases := map[string]func(*fakeBackend){
		"row read 503": func(be *fakeBackend) { be.dm.fetchErr = &HTTPError{StatusCode: http.StatusServiceUnavailable} },
		"download 502": func(be *fakeBackend) { be.dm.downloadErr = &HTTPError{StatusCode: http.StatusBadGateway} },
		"download reset": func(be *fakeBackend) {
			be.dm.downloadErr = &url.Error{Op: "Get", URL: "http://x/storage/v1/object/dm-images", Err: errors.New("connection reset by peer")}
		},
		"upload 500": func(be *fakeBackend) { be.dm.uploadErr = &HTTPError{StatusCode: http.StatusInternalServerError} },
		"mark 503":   func(be *fakeBackend) { be.dm.markErr = &HTTPError{StatusCode: http.StatusServiceUnavailable} },
	}
	for name, setup := range cases {
		be := dmBackend("pending", dmPhoto(t, 20, 20))
		setup(be)
		w := newTestWorker(be, nil)
		err := w.handleDmImageProcess(context.Background(), dmJob())
		if err == nil || !isTransient(err) {
			t.Fatalf("%s: err = %v, want a transient error", name, err)
		}
		if got := be.dm.rows[dmImageID].Status; got != "pending" {
			t.Fatalf("%s: status = %s, want pending for the retry", name, got)
		}
		if uploadDeleted(be) {
			t.Fatalf("%s: deleted the upload a retry still needs", name)
		}
	}
}

// The row is already ready, so returning the error would retry into a skip;
// the backstop sweep erases the upload instead.
func TestDmImageProcess_UploadDeleteFailureIsLoggedNotReturned(t *testing.T) {
	be := dmBackend("pending", dmPhoto(t, 20, 20))
	refusing := &refusingDeleteBackend{fakeBackend: be}
	w := newTestWorker(refusing, nil)
	if err := w.handleDmImageProcess(context.Background(), dmJob()); err != nil {
		t.Fatalf("handleDmImageProcess: %v", err)
	}
	if be.dm.rows[dmImageID].Status != "ready" {
		t.Fatalf("status = %s", be.dm.rows[dmImageID].Status)
	}
	if refusing.calls != 1 {
		t.Fatalf("DELETE attempts = %d, want 1", refusing.calls)
	}
}

type refusingDeleteBackend struct {
	*fakeBackend
	calls int
}

func (r *refusingDeleteBackend) DeleteStorageObjects(context.Context, string, []string) error {
	r.calls++
	return errors.New("storage delete refused")
}

func TestDmImageProcess_BadPayloadIsPermanent(t *testing.T) {
	w := newTestWorker(dmBackend("pending", nil), nil)
	for _, payload := range []string{`not json`, `{}`, `{"image_id":"x&status=eq.ready"}`} {
		err := w.handleDmImageProcess(context.Background(), &Job{Kind: "dm_image_process", Payload: json.RawMessage(payload)})
		if err == nil || isTransient(err) {
			t.Fatalf("%s: err = %v, want a permanent error", payload, err)
		}
	}
}

// Neither the log nor a returned error names the owner: the paths are
// `{owner}/{image}...`.
func TestDmImageProcess_LogsAndErrorsCarryNoPath(t *testing.T) {
	var buf bytes.Buffer
	be := dmBackend("pending", []byte("garbage"))
	w := newTestWorker(be, nil)
	w.Log = slog.New(slog.NewTextHandler(&buf, nil))
	if err := w.handleDmImageProcess(context.Background(), dmJob()); err != nil {
		t.Fatal(err)
	}
	be = dmBackend("pending", dmPhoto(t, 8, 8))
	w.Backend = be
	if err := w.handleDmImageProcess(context.Background(), dmJob()); err != nil {
		t.Fatal(err)
	}
	if strings.Contains(buf.String(), dmOwner) || !strings.Contains(buf.String(), "outcome=rejected") ||
		!strings.Contains(buf.String(), "outcome=ready") {
		t.Fatalf("log: %s", buf.String())
	}
}

// The real client against a Storage double: the object path must not reach
// an error's text, while the status still classifies.
func TestSupabaseClient_DmImageErrorsAreRedacted(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(rw http.ResponseWriter, r *http.Request) {
		rw.WriteHeader(http.StatusBadGateway)
	}))
	defer srv.Close()
	c := NewSupabaseClient(srv.URL, "service-key")

	_, derr := c.DownloadDmImage(context.Background(), dmUpload, 10)
	uerr := c.UploadDmImage(context.Background(), dmReencode, []byte("x"))
	for name, err := range map[string]error{"download": derr, "upload": uerr} {
		if err == nil || strings.Contains(err.Error(), dmOwner) || !isTransient(err) {
			t.Fatalf("%s: err = %v; want a transient error with no path", name, err)
		}
	}

	dead := NewSupabaseClient("http://127.0.0.1:1", "service-key")
	_, err := dead.DownloadDmImage(context.Background(), dmUpload, 10)
	if err == nil || strings.Contains(err.Error(), dmOwner) || !isTransient(err) {
		t.Fatalf("refused connection: err = %v; want a transient error with no path", err)
	}
}

func TestSupabaseClient_DmImageDownloadStopsAtTheCap(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(rw http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/storage/v1/object/dm-images/"+dmUpload {
			t.Errorf("path = %s", r.URL.Path)
		}
		_, _ = rw.Write(bytes.Repeat([]byte{1}, 11))
	}))
	defer srv.Close()
	c := NewSupabaseClient(srv.URL, "service-key")

	if _, err := c.DownloadDmImage(context.Background(), dmUpload, 10); !errors.Is(err, ErrDmImageTooLarge) {
		t.Fatalf("11 bytes against a 10-byte cap: %v", err)
	}
	if b, err := c.DownloadDmImage(context.Background(), dmUpload, 11); err != nil || len(b) != 11 {
		t.Fatalf("11 bytes against an 11-byte cap: %d, %v", len(b), err)
	}
}

func TestSupabaseClient_DmImageRequestShapes(t *testing.T) {
	type call struct {
		method, path, query, contentType, upsert string
		body                                     map[string]any
	}
	var calls []call
	srv := httptest.NewServer(http.HandlerFunc(func(rw http.ResponseWriter, r *http.Request) {
		raw, _ := io.ReadAll(r.Body)
		var m map[string]any
		_ = json.Unmarshal(raw, &m)
		calls = append(calls, call{r.Method, r.URL.Path, r.URL.RawQuery, r.Header.Get("Content-Type"), r.Header.Get("x-upsert"), m})
		if r.Method == http.MethodGet {
			_, _ = rw.Write([]byte(`[{"id":"` + dmImageID + `","status":"pending","upload_path":"a","storage_path":"b"}]`))
		}
		if r.Method == http.MethodPatch {
			_, _ = rw.Write([]byte(`[{"id":"` + dmImageID + `"}]`))
		}
	}))
	defer srv.Close()
	c := NewSupabaseClient(srv.URL, "service-key")
	ctx := context.Background()

	img, err := c.FetchDmImage(ctx, dmImageID)
	if err != nil || img == nil || img.Status != "pending" || img.UploadPath != "a" || img.StoragePath != "b" {
		t.Fatalf("FetchDmImage = %+v, %v", img, err)
	}
	if err := c.UploadDmImage(ctx, dmReencode, []byte("jpeg")); err != nil {
		t.Fatal(err)
	}
	if matched, err := c.MarkDmImageReady(ctx, dmImageID, 640, 480); err != nil || !matched {
		t.Fatalf("MarkDmImageReady = %v, %v", matched, err)
	}
	if _, err := c.MarkDmImageRejected(ctx, dmImageID); err != nil {
		t.Fatal(err)
	}

	q, _ := url.ParseQuery(calls[0].query)
	if calls[0].path != "/rest/v1/direct_message_images" || q.Get("id") != "eq."+dmImageID ||
		q.Get("select") != "id,status,upload_path,storage_path" {
		t.Fatalf("fetch = %+v", calls[0])
	}
	if calls[1].method != http.MethodPost || calls[1].path != "/storage/v1/object/dm-images/"+dmReencode ||
		calls[1].contentType != "image/jpeg" || calls[1].upsert != "true" {
		t.Fatalf("upload = %+v", calls[1])
	}
	for i, want := range []string{"ready", "rejected"} {
		c := calls[2+i]
		q, _ := url.ParseQuery(c.query)
		if c.method != http.MethodPatch || c.path != "/rest/v1/direct_message_images" ||
			q.Get("id") != "eq."+dmImageID || q.Get("status") != "eq.pending" {
			t.Fatalf("%s patch = %+v; must be filtered to the pending row", want, c)
		}
		if c.body["status"] != want || c.body["processed_at"] == nil {
			t.Fatalf("%s patch body = %v", want, c.body)
		}
	}
	if calls[2].body["width"] != float64(640) || calls[2].body["height"] != float64(480) {
		t.Fatalf("ready patch body = %v", calls[2].body)
	}
	if _, ok := calls[3].body["width"]; ok {
		t.Fatalf("rejected patch must not set a size: %v", calls[3].body)
	}
}

func TestSupabaseClient_FetchDmImageMissingRowIsNil(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(rw http.ResponseWriter, r *http.Request) {
		_, _ = rw.Write([]byte(`[]`))
	}))
	defer srv.Close()
	img, err := NewSupabaseClient(srv.URL, "k").FetchDmImage(context.Background(), dmImageID)
	if img != nil || err != nil {
		t.Fatalf("got %+v, %v; want nil, nil", img, err)
	}
}
