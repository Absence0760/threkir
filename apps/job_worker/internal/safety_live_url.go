package internal

import "regexp"

var safetyViewTokenRe = regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`)

// safetyLiveURL is the spectator link an overdue / off-route alert carries.
// A safety-audience run (decisions § 1964) is private, so the bare /live link
// shows its contacts nothing: the contact's own token rides in the FRAGMENT,
// which a browser never sends to the server or in a Referer, so it stays out
// of CloudFront logs. A token that is not a lowercase UUID is dropped rather
// than interpolated — the database mints only UUIDs, so anything else is not
// one of ours.
func safetyLiveURL(base string, runID *string, token string) string {
	if runID == nil || *runID == "" {
		return base
	}
	url := base + "/live/" + *runID
	if safetyViewTokenRe.MatchString(token) {
		url += "#k=" + token
	}
	return url
}
