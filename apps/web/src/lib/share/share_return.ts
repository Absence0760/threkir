// What the share-page header offers a SIGNED-IN visitor to get back into the
// app. The share pages are the logged-out surface, so a signed-in reader who
// reached one (a pasted link, an email, an older in-app link) had no sidebar
// and no back control. Anonymous visitors get nothing: the page is theirs as
// it is, and crawlers must see the same markup they always have.
export type ShareReturn = { kind: 'back' } | { kind: 'open'; href: string } | null;

export interface ShareReturnInput {
	loggedIn: boolean;
	/** `document.referrer`, empty when the browser withheld it. */
	referrer: string;
	/** `location.origin`. */
	origin: string;
	/** `history.length`; 1 means this tab has nowhere to go back to. */
	historyLength: number;
	/** The in-app view of the same entity, or null when none exists. */
	appHref: string | null;
}

export function shareReturnFor(input: ShareReturnInput): ShareReturn {
	if (!input.loggedIn) return null;
	if (input.historyLength > 1 && sameOrigin(input.referrer, input.origin)) {
		return { kind: 'back' };
	}
	return { kind: 'open', href: input.appHref ?? '/dashboard' };
}

function sameOrigin(referrer: string, origin: string): boolean {
	if (!referrer) return false;
	try {
		return new URL(referrer).origin === origin;
	} catch {
		return false;
	}
}
