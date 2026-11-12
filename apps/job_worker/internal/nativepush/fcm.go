package nativepush

import (
	"bytes"
	"context"
	"crypto/rsa"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"

	jwt "github.com/golang-jwt/jwt/v5"
)

// fcmTokenURL is Google's OAuth2 token endpoint. Overridable in tests.
const fcmTokenURL = "https://oauth2.googleapis.com/token"

// fcmScope is the single scope the FCM HTTP v1 send needs.
const fcmScope = "https://www.googleapis.com/auth/firebase.messaging"

// serviceAccount is the subset of a Firebase service-account JSON the OAuth2
// JWT-bearer grant needs. The full file carries more; we read only these.
type serviceAccount struct {
	ClientEmail string `json:"client_email"`
	PrivateKey  string `json:"private_key"`
	TokenURI    string `json:"token_uri"`
	ProjectID   string `json:"project_id"`
}

// fcmTransport sends to FCM HTTP v1. It mints a short-lived OAuth2 access token
// from the service-account key (RFC 7523 JWT-bearer grant) and caches it until
// shortly before expiry — one token serves many sends.
type fcmTransport struct {
	sa        serviceAccount
	signKey   *rsa.PrivateKey
	projectID string
	sendURL   string
	tokenURL  string
	http      *http.Client
	now       func() time.Time

	mu       sync.Mutex
	token    string
	tokenExp time.Time
}

func newFCMTransport(serviceAccountJSON []byte, projectID string, httpClient *http.Client) (*fcmTransport, error) {
	var sa serviceAccount
	if err := json.Unmarshal(serviceAccountJSON, &sa); err != nil {
		return nil, fmt.Errorf("nativepush/fcm: bad service-account JSON: %w", err)
	}
	if sa.ClientEmail == "" || sa.PrivateKey == "" {
		return nil, fmt.Errorf("nativepush/fcm: service-account JSON missing client_email/private_key")
	}
	key, err := parseRSAPrivateKey(sa.PrivateKey)
	if err != nil {
		return nil, fmt.Errorf("nativepush/fcm: %w", err)
	}
	tokenURL := sa.TokenURI
	if tokenURL == "" {
		tokenURL = fcmTokenURL
	}
	return &fcmTransport{
		sa:        sa,
		signKey:   key,
		projectID: projectID,
		sendURL:   fmt.Sprintf("https://fcm.googleapis.com/v1/projects/%s/messages:send", projectID),
		tokenURL:  tokenURL,
		http:      httpClient,
		now:       time.Now,
	}, nil
}

// fcmMessage is the FCM HTTP v1 request body. ONE body serves both platforms:
// FCM applies the android block to an Android token and the apns block to an
// iOS one, so the {title, body, url, tag} contract renders the same either way
// and nothing downstream has to know which kind of device it is addressing.
// The notification block is what the OS draws while the app is backgrounded;
// the data keys are what the tap handler reads (firebase_messaging surfaces
// them as RemoteMessage.data on both platforms — the deep-link path).
//
// The two collapse keys are how Tag keeps an at-least-once retry from stacking
// a second copy on the lock screen: Android coalesces on notification.tag,
// APNs on the apns-collapse-id header. They are the same value and must stay
// so — a retry that lands under a different key is a duplicate notification,
// which is exactly what the Tag contract promises not to do.
type fcmMessage struct {
	Message struct {
		Token        string            `json:"token"`
		Notification fcmNotification   `json:"notification"`
		Data         map[string]string `json:"data,omitempty"`
		Android      *fcmAndroid       `json:"android,omitempty"`
		APNS         *fcmAPNS          `json:"apns,omitempty"`
	} `json:"message"`
}

type fcmNotification struct {
	Title string `json:"title"`
	Body  string `json:"body,omitempty"`
}

type fcmAndroid struct {
	Notification fcmAndroidNotification `json:"notification"`
}

type fcmAndroidNotification struct {
	Tag string `json:"tag,omitempty"`
}

type fcmAPNS struct {
	Headers map[string]string `json:"headers,omitempty"`
	Payload fcmAPNSPayload    `json:"payload"`
}

type fcmAPNSPayload struct {
	APS fcmAPS `json:"aps"`
}

type fcmAPS struct {
	Sound string `json:"sound,omitempty"`
}

func (t *fcmTransport) send(ctx context.Context, token string, msg Message) (int, error) {
	access, err := t.accessToken(ctx)
	if err != nil {
		return 0, err
	}

	var body fcmMessage
	body.Message.Token = token
	body.Message.Notification = fcmNotification{Title: msg.Title, Body: msg.Body}
	body.Message.Data = map[string]string{"url": msg.URL, "tag": msg.Tag}
	// Android draws the channel's own sound; iOS plays none at all unless one
	// is named, so the sound is set on the apns leg only.
	body.Message.APNS = &fcmAPNS{Payload: fcmAPNSPayload{APS: fcmAPS{Sound: "default"}}}
	if msg.Tag != "" {
		body.Message.Android = &fcmAndroid{Notification: fcmAndroidNotification{Tag: msg.Tag}}
		// apns-collapse-id is capped at 64 bytes; the tag (notif-<uuid>) fits.
		body.Message.APNS.Headers = map[string]string{"apns-collapse-id": msg.Tag}
	}
	raw, err := json.Marshal(body)
	if err != nil {
		return 0, fmt.Errorf("nativepush/fcm: marshal: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, t.sendURL, bytes.NewReader(raw))
	if err != nil {
		return 0, fmt.Errorf("nativepush/fcm: build request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+access)
	req.Header.Set("Content-Type", "application/json")

	resp, err := t.http.Do(req)
	if err != nil {
		return 0, fmt.Errorf("nativepush/fcm: POST: %w", err)
	}
	defer resp.Body.Close()
	_, _ = io.Copy(io.Discard, resp.Body)
	return resp.StatusCode, nil
}

// accessToken returns a cached OAuth2 access token, minting a fresh one via the
// JWT-bearer grant when the cache is empty or near expiry.
func (t *fcmTransport) accessToken(ctx context.Context) (string, error) {
	t.mu.Lock()
	defer t.mu.Unlock()
	if t.token != "" && t.now().Before(t.tokenExp.Add(-1*time.Minute)) {
		return t.token, nil
	}

	now := t.now()
	assertion := jwt.NewWithClaims(jwt.SigningMethodRS256, jwt.MapClaims{
		"iss":   t.sa.ClientEmail,
		"scope": fcmScope,
		"aud":   t.tokenURL,
		"iat":   now.Unix(),
		"exp":   now.Add(time.Hour).Unix(),
	})
	signed, err := assertion.SignedString(t.signKey)
	if err != nil {
		return "", fmt.Errorf("nativepush/fcm: sign assertion: %w", err)
	}

	form := url.Values{}
	form.Set("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer")
	form.Set("assertion", signed)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, t.tokenURL, strings.NewReader(form.Encode()))
	if err != nil {
		return "", fmt.Errorf("nativepush/fcm: build token request: %w", err)
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")

	resp, err := t.http.Do(req)
	if err != nil {
		return "", fmt.Errorf("nativepush/fcm: token POST: %w", err)
	}
	defer resp.Body.Close()
	respBody, _ := io.ReadAll(resp.Body)
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return "", fmt.Errorf("nativepush/fcm: token endpoint status %d: %s", resp.StatusCode, string(respBody))
	}
	var tok struct {
		AccessToken string `json:"access_token"`
		ExpiresIn   int    `json:"expires_in"`
	}
	if err := json.Unmarshal(respBody, &tok); err != nil {
		return "", fmt.Errorf("nativepush/fcm: parse token response: %w", err)
	}
	if tok.AccessToken == "" {
		return "", fmt.Errorf("nativepush/fcm: token response missing access_token")
	}
	t.token = tok.AccessToken
	t.tokenExp = now.Add(time.Duration(tok.ExpiresIn) * time.Second)
	return t.token, nil
}

// parseRSAPrivateKey parses a PEM-encoded PKCS#1 or PKCS#8 RSA private key (the
// form a Firebase service-account JSON's private_key field carries).
func parseRSAPrivateKey(pemStr string) (*rsa.PrivateKey, error) {
	block, _ := pem.Decode([]byte(pemStr))
	if block == nil {
		return nil, fmt.Errorf("private_key is not valid PEM")
	}
	if key, err := x509.ParsePKCS1PrivateKey(block.Bytes); err == nil {
		return key, nil
	}
	parsed, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("private_key is neither PKCS#1 nor PKCS#8: %w", err)
	}
	key, ok := parsed.(*rsa.PrivateKey)
	if !ok {
		return nil, fmt.Errorf("private_key is not an RSA key")
	}
	return key, nil
}
