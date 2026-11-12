// Package nativepush is a dependency-light native-push sender: one FCM HTTP v1
// POST per registered device, for Android and iOS alike. It is the server leg
// of the native-push channel — the mobile clients register a token on
// device_tokens via the api_client, and the worker's handler_native_push.go
// sends through this package. Sibling of internal/webpush (the browser leg).
//
// iOS is delivered BY FCM rather than by a direct APNs HTTP/2 POST, which
// reverses the original design. Both clients register
// FirebaseMessaging.getToken(), an FCM registration token; a direct APNs POST
// addresses an APNs device token, so the two halves disagreed about what the
// word "token" meant and every iOS send answered 400 BadDeviceToken — which the
// handler read as terminal and stamped as delivered. Routing iOS through FCM
// leaves one token type, one payload contract and the tap path already proven
// on Android, and moves the APNs .p8 from the worker's environment into the
// Firebase project. That also retires APNS_SANDBOX: a development-signed build
// mints a token the production APNs host rejects, and the worker held one
// setting for every device, so it could serve TestFlight builds or Xcode builds
// but never both. FCM reads each token's own environment.
//
// Built on the standard library plus golang-jwt — already a worker dependency —
// for the service-account JWT-bearer grant. No Firebase Admin SDK: FCM HTTP v1
// is a single OAuth2-bearer POST, and vendoring the Admin SDK (a large
// transitive surface) for ~200 lines of stdlib is not worth the supply-chain
// cost — the same call internal/webpush made for Web Push.
//
// Fail-closed: NewSender returns (nil, nil) when the credentials are unset, so
// main.go leaves Worker.NativePush nil and the handler finishes each
// native_push job WITHOUT stamping native_push_sent_at — the rows stay pending
// for a later credentialed deploy.
package nativepush

import (
	"context"
	"net/http"
)

// Message is the localized notification to deliver. Title/Body surface as the
// system notification; URL is the deep link the tap handler opens; Tag (== the
// notification id) coalesces a retry so a duplicate replaces rather than
// stacks. Mirrors the {title, body, url, tag} contract the webpush payload uses
// so the two channels render identically from the shared catalogue.
type Message struct {
	Title string
	Body  string
	URL   string
	Tag   string
}

// Sender delivers one Message to one device token over FCM HTTP v1. Constructed
// only when credentialed — a Sender is never a no-op, because the nil Sender IS
// the disabled state.
type Sender struct {
	fcm *fcmTransport
}

// Config carries the operator credentials: the Firebase service-account JSON
// that signs the sends and the project id it belongs to. Either missing →
// NewSender returns (nil, nil).
//
// The APNs .p8 is deliberately absent. It belongs to the Firebase project
// (Cloud Messaging → APNs authentication key), not to the worker — see the
// package doc.
type Config struct {
	FCMServiceAccountJSON []byte
	FCMProjectID          string
}

// NewSender builds a Sender from the operator credentials. Returns (nil, nil)
// when they are unset — the fail-closed default the worker relies on. A
// configured-but-invalid credential (bad service-account JSON) returns a
// non-nil error so a deploy misconfiguration fails loudly at startup rather
// than silently dropping every push.
func NewSender(cfg Config, httpClient *http.Client) (*Sender, error) {
	if len(cfg.FCMServiceAccountJSON) == 0 || cfg.FCMProjectID == "" {
		return nil, nil
	}
	if httpClient == nil {
		httpClient = http.DefaultClient
	}
	fcm, err := newFCMTransport(cfg.FCMServiceAccountJSON, cfg.FCMProjectID, httpClient)
	if err != nil {
		return nil, err
	}
	return &Sender{fcm: fcm}, nil
}

// Send delivers msg to one device. Returns the provider HTTP status on a
// completed request (whatever the status), or a non-nil error only on a
// transport failure before the request completed. The device's platform does
// not route anything — the one message body carries both an android and an
// apns block, and FCM applies whichever matches the token.
func (s *Sender) Send(ctx context.Context, token string, msg Message) (int, error) {
	return s.fcm.send(ctx, token, msg)
}

// IsDeadToken reports whether a provider status means the token is gone and
// should be pruned. FCM HTTP v1 answers 404 (UNREGISTERED) for a stale
// registration; 410 is honoured alongside it as the same terminal verdict the
// web-push leg prunes a dead subscription on (handler_web_push.go).
func IsDeadToken(status int) bool {
	return status == http.StatusNotFound || status == http.StatusGone
}

// IsTransient reports whether a provider status warrants a job retry (the push
// service is throttling or down).
//
// 408 / 425 / 429 / any 5xx defer — the same set the worker's own classifier
// uses. This package cannot import the worker (that would cycle), so the rule
// is duplicated deliberately; internal.TestIsTransient_AgreesWithPushClassifiers
// pins the two together in BOTH directions.
func IsTransient(status int) bool {
	switch status {
	case http.StatusRequestTimeout, http.StatusTooEarly, http.StatusTooManyRequests:
		return true
	}
	return status >= 500
}
