package nativepush

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestNewSender_NoCredentialsIsInert(t *testing.T) {
	s, err := NewSender(Config{}, nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if s != nil {
		t.Fatalf("a Sender with no credentials must be nil (fail-closed), got %#v", s)
	}
}

func TestNewSender_BadFCMServiceAccountFailsLoud(t *testing.T) {
	_, err := NewSender(Config{
		FCMServiceAccountJSON: []byte("{not json"),
		FCMProjectID:          "p",
	}, nil)
	if err == nil {
		t.Fatalf("a malformed service-account JSON must fail at construction")
	}
}

// Half a credential is no credential: a service-account JSON without the
// project id (or the reverse) addresses no send URL, so it must stay inert
// rather than construct a Sender that 404s every push.
func TestNewSender_PartialCredentialsAreInert(t *testing.T) {
	for _, cfg := range []Config{
		{FCMServiceAccountJSON: []byte(`{"client_email":"a","private_key":"b"}`)},
		{FCMProjectID: "test-project"},
	} {
		s, err := NewSender(cfg, nil)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if s != nil {
			t.Fatalf("a half-configured Sender must be nil (fail-closed), got %#v", s)
		}
	}
}

func TestStatusClassification(t *testing.T) {
	dead := []int{404, 410}
	for _, s := range dead {
		if !IsDeadToken(s) {
			t.Errorf("status %d should be a dead token", s)
		}
		if IsTransient(s) {
			t.Errorf("status %d should not be transient", s)
		}
	}
	transient := []int{429, 500, 502, 503}
	for _, s := range transient {
		if !IsTransient(s) {
			t.Errorf("status %d should be transient", s)
		}
		if IsDeadToken(s) {
			t.Errorf("status %d should not be a dead token", s)
		}
	}
	for _, s := range []int{200, 400, 403} {
		if IsDeadToken(s) || IsTransient(s) {
			t.Errorf("status %d should be neither dead nor transient", s)
		}
	}
}

// fakeServer mints a service-account-style FCM transport pointed at a test
// server so we can drive a full FCM send (OAuth2 token mint + messages:send)
// without touching Google.
func newTestFCMSender(t *testing.T, handler http.HandlerFunc) *Sender {
	t.Helper()
	srv := httptest.NewServer(handler)
	t.Cleanup(srv.Close)

	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	der, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		t.Fatal(err)
	}
	pemKey := pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der})

	sa := map[string]string{
		"client_email": "svc@test.iam.gserviceaccount.com",
		"private_key":  string(pemKey),
		"token_uri":    srv.URL + "/token",
		"project_id":   "test-project",
	}
	saJSON, _ := json.Marshal(sa)

	fcm, err := newFCMTransport(saJSON, "test-project", srv.Client())
	if err != nil {
		t.Fatal(err)
	}
	// Redirect the send URL at the test server too.
	fcm.sendURL = srv.URL + "/send"
	return &Sender{fcm: fcm}
}

func TestSender_FCMRoundTrip(t *testing.T) {
	var gotAuth, gotBody string
	s := newTestFCMSender(t, func(w http.ResponseWriter, r *http.Request) {
		switch {
		case strings.HasSuffix(r.URL.Path, "/token"):
			_ = json.NewEncoder(w).Encode(map[string]any{"access_token": "ya29.test", "expires_in": 3600})
		case strings.HasSuffix(r.URL.Path, "/send"):
			gotAuth = r.Header.Get("Authorization")
			b, _ := io.ReadAll(r.Body)
			gotBody = string(b)
			w.WriteHeader(http.StatusOK)
		default:
			http.NotFound(w, r)
		}
	})

	status, err := s.Send(context.Background(), "dev-tok",
		Message{Title: "Hi", Body: "there", URL: "https://x/events/1", Tag: "notif-1"})
	if err != nil {
		t.Fatalf("send: %v", err)
	}
	if status != http.StatusOK {
		t.Errorf("want 200, got %d", status)
	}
	if gotAuth != "Bearer ya29.test" {
		t.Errorf("send should carry the minted bearer, got %q", gotAuth)
	}
	if !strings.Contains(gotBody, `"token":"dev-tok"`) || !strings.Contains(gotBody, `"title":"Hi"`) {
		t.Errorf("send body missing token/title: %s", gotBody)
	}
	if !strings.Contains(gotBody, `"url":"https://x/events/1"`) {
		t.Errorf("send body should carry the deep-link url in data: %s", gotBody)
	}
}

func TestSender_FCMSurfaces404(t *testing.T) {
	s := newTestFCMSender(t, func(w http.ResponseWriter, r *http.Request) {
		if strings.HasSuffix(r.URL.Path, "/token") {
			_ = json.NewEncoder(w).Encode(map[string]any{"access_token": "t", "expires_in": 3600})
			return
		}
		w.WriteHeader(http.StatusNotFound) // UNREGISTERED
	})
	status, err := s.Send(context.Background(), "dead", Message{Title: "x"})
	if err != nil {
		t.Fatalf("send: %v", err)
	}
	if !IsDeadToken(status) {
		t.Errorf("a 404 should classify as a dead token, got %d", status)
	}
}

// One body serves both platforms. The apns block is what carries the
// notification to an Apple device once the .p8 is uploaded to the Firebase
// project, and the two collapse keys must agree so an at-least-once retry
// replaces the notification on either OS instead of stacking a second copy.
func TestSender_PayloadCarriesBothPlatformLegs(t *testing.T) {
	var gotBody []byte
	s := newTestFCMSender(t, func(w http.ResponseWriter, r *http.Request) {
		if strings.HasSuffix(r.URL.Path, "/token") {
			_ = json.NewEncoder(w).Encode(map[string]any{"access_token": "t", "expires_in": 3600})
			return
		}
		gotBody, _ = io.ReadAll(r.Body)
		w.WriteHeader(http.StatusOK)
	})
	status, err := s.Send(context.Background(), "ios-tok",
		Message{Title: "Hi", Body: "there", URL: "https://x/events/1", Tag: "notif-n1"})
	if err != nil {
		t.Fatalf("send: %v", err)
	}
	if status != http.StatusOK {
		t.Fatalf("want 200, got %d", status)
	}

	var body struct {
		Message struct {
			Android struct {
				Notification struct {
					Tag string `json:"tag"`
				} `json:"notification"`
			} `json:"android"`
			APNS struct {
				Headers map[string]string `json:"headers"`
				Payload struct {
					APS struct {
						Sound string `json:"sound"`
					} `json:"aps"`
				} `json:"payload"`
			} `json:"apns"`
		} `json:"message"`
	}
	if err := json.Unmarshal(gotBody, &body); err != nil {
		t.Fatalf("send body is not the FCM v1 shape: %v (%s)", err, gotBody)
	}
	if got := body.Message.APNS.Payload.APS.Sound; got != "default" {
		t.Errorf("iOS plays no sound unless one is named, got %q", got)
	}
	androidTag := body.Message.Android.Notification.Tag
	apnsCollapse := body.Message.APNS.Headers["apns-collapse-id"]
	if androidTag != "notif-n1" || apnsCollapse != "notif-n1" {
		t.Errorf("both collapse keys must carry the tag, got android=%q apns=%q", androidTag, apnsCollapse)
	}
}

// An untagged message must not assert an empty collapse key — APNs rejects an
// empty apns-collapse-id header rather than ignoring it.
func TestSender_UntaggedMessageOmitsCollapseKeys(t *testing.T) {
	var gotBody string
	s := newTestFCMSender(t, func(w http.ResponseWriter, r *http.Request) {
		if strings.HasSuffix(r.URL.Path, "/token") {
			_ = json.NewEncoder(w).Encode(map[string]any{"access_token": "t", "expires_in": 3600})
			return
		}
		b, _ := io.ReadAll(r.Body)
		gotBody = string(b)
		w.WriteHeader(http.StatusOK)
	})
	if _, err := s.Send(context.Background(), "tok", Message{Title: "x"}); err != nil {
		t.Fatalf("send: %v", err)
	}
	if strings.Contains(gotBody, "apns-collapse-id") || strings.Contains(gotBody, `"android"`) {
		t.Errorf("an untagged message should carry no collapse keys: %s", gotBody)
	}
}
