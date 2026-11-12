package internal

import (
	"strings"
	"testing"
)

// Gaps the arity and handler tests leave in renderSafetySms: who the message
// names when the owner has no display name, which language an unrecognised
// locale gets, and the live link surviving a trailing slash on the base.

func smsPayload(owner, lastSeen string) SafetySmsPayload {
	runID := "run-1"
	return SafetySmsPayload{
		Template:   "overdue",
		OwnerName:  owner,
		RunID:      &runID,
		StartedAt:  "2026-01-02T01:00:00Z",
		LastSeenAt: lastSeen,
	}
}

func TestSafetySms_AnUnnamedOwnerReadsAsTheLocalizedDefault(t *testing.T) {
	for _, loc := range emailLocales {
		want := lookupEmailShared(loc).safetyDefaultOwner
		if want == "" {
			t.Fatalf("%s has no safetyDefaultOwner", loc)
		}
		body, ok := renderSafetySms(smsPayload("", ""), "https://example.test", loc)
		if !ok {
			t.Fatalf("%s: refused", loc)
		}
		if !strings.HasPrefix(body, want) {
			t.Errorf("%s: an unnamed owner should read %q, got %q", loc, want, body)
		}
	}
}

func TestSafetySms_ANamedOwnerIsUsedAsGiven(t *testing.T) {
	body, _ := renderSafetySms(smsPayload("Ada Lovelace", ""), "https://example.test", "en")
	if !strings.HasPrefix(body, "Ada Lovelace ") {
		t.Errorf("got %q", body)
	}
}

func TestSafetySms_AnUnrecognisedLocaleFallsBackToEnglish(t *testing.T) {
	en, _ := renderSafetySms(smsPayload("Ada", ""), "https://example.test", "en")
	for _, loc := range []string{"", "xx", "klingon", "zz-ZZ"} {
		got, ok := renderSafetySms(smsPayload("Ada", ""), "https://example.test", loc)
		if !ok || got != en {
			t.Errorf("locale %q: got %q, want the English %q", loc, got, en)
		}
	}
}

func TestSafetySms_ARegionalTagUsesItsLanguage(t *testing.T) {
	de, _ := renderSafetySms(smsPayload("Ada", ""), "https://example.test", "de")
	got, _ := renderSafetySms(smsPayload("Ada", ""), "https://example.test", "de-AT")
	if got != de {
		t.Errorf("de-AT should read German: got %q", got)
	}
}

func TestSafetySms_ATrailingSlashOnTheBaseIsNotDoubled(t *testing.T) {
	body, _ := renderSafetySms(smsPayload("Ada", ""), "https://example.test///", "en")
	if !strings.HasSuffix(body, "https://example.test/live/run-1") {
		t.Errorf("got %q", body)
	}
}
