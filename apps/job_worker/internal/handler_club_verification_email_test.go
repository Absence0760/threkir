package internal

import (
	"strings"
	"testing"
)

func validClubVerificationPayload() ClubVerificationEmailPayload {
	return ClubVerificationEmailPayload{
		Email:        "hostmaster@race.example.org",
		Locale:       "en",
		ClubName:     "Race Club",
		Organisation: "Race Org",
		Domain:       "race.example.org",
		Token:        strings.Repeat("ab", 24),
	}
}

func TestRenderClubVerificationEmail_LinkCarriesTheTokenInTheFragment(t *testing.T) {
	msg, err := renderClubVerificationEmail(validClubVerificationPayload(), "https://threkir.com/")
	if err != nil {
		t.Fatal(err)
	}
	want := "https://threkir.com/club-verification/confirm#token=" + strings.Repeat("ab", 24)
	if !strings.Contains(msg.Body, want) {
		t.Fatalf("text part has no confirm link %q:\n%s", want, msg.Body)
	}
	if strings.Contains(msg.Body, "?token=") {
		t.Fatal("the token must not travel in the query string, where server logs keep it")
	}
	for _, fact := range []string{"Race Club", "Race Org", "race.example.org"} {
		if !strings.Contains(msg.Body, fact) {
			t.Errorf("body does not name %q", fact)
		}
	}
}

func TestRenderClubVerificationEmail_UserTextNeverReachesTheSubject(t *testing.T) {
	p := validClubVerificationPayload()
	p.ClubName = "Evil\r\nBcc: victim@example.com"
	msg, err := renderClubVerificationEmail(p, "https://threkir.com")
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(msg.Subject, "Evil") {
		t.Fatalf("subject carries the club name: %q", msg.Subject)
	}
	if strings.Contains(msg.Body, "\r\nBcc:") {
		t.Fatal("a control character in the club name survived into the body")
	}
}

func TestRenderClubVerificationEmail_RefusesAnUnusablePayload(t *testing.T) {
	for name, mutate := range map[string]func(*ClubVerificationEmailPayload){
		"no address":     func(p *ClubVerificationEmailPayload) { p.Email = " " },
		"no domain":      func(p *ClubVerificationEmailPayload) { p.Domain = "" },
		"short token":    func(p *ClubVerificationEmailPayload) { p.Token = "abc" },
		"non-hex token":  func(p *ClubVerificationEmailPayload) { p.Token = strings.Repeat("zz", 24) },
		"injected token": func(p *ClubVerificationEmailPayload) { p.Token = strings.Repeat("ab", 23) + "&x" },
	} {
		p := validClubVerificationPayload()
		mutate(&p)
		if _, err := renderClubVerificationEmail(p, "https://threkir.com"); err == nil {
			t.Errorf("%s: rendered an unusable payload", name)
		}
	}
}

func TestRenderClubVerificationEmail_EveryLocaleRendersWithoutAFormatDefect(t *testing.T) {
	for _, loc := range emailLocales {
		p := validClubVerificationPayload()
		p.Locale = loc
		msg, err := renderClubVerificationEmail(p, "https://threkir.com")
		if err != nil {
			t.Fatalf("%s: %v", loc, err)
		}
		for _, part := range []string{msg.Subject, msg.Body, msg.HTML} {
			if d := formatDefect(part); d != "" {
				t.Errorf("%s: format defect %q", loc, d)
			}
		}
		if !strings.Contains(msg.Body, "Race Org") {
			t.Errorf("%s: body drops the organisation", loc)
		}
	}
}
