/// Plain-English relative age of a personal-record date, e.g. "today",
/// "3 weeks ago", "2 years ago". Used to soften the PR card for returning
/// runners — an all-time best from years back reads as context, not a
/// taunt (comeback persona #28). Web-only: the phone's PR card has no
/// relative age, so there is no Dart twin.
///
/// "today" / "yesterday" are calendar words, so the count is of local calendar
/// days, not 24-hour blocks: a PR set at 19:00 and read at 08:00 the next
/// morning is "yesterday", where flooring the elapsed hours called it "today".
/// Built from each instant's local Y/M/D through `Date.UTC`, so a 23- or
/// 25-hour DST day still counts as one.
export function relativeAge(iso: string, nowMs: number = Date.now()): string {
	const then = Date.parse(iso);
	if (Number.isNaN(then)) return '';
	const a = new Date(then);
	const b = new Date(nowMs);
	const days = Math.round(
		(Date.UTC(b.getFullYear(), b.getMonth(), b.getDate()) -
			Date.UTC(a.getFullYear(), a.getMonth(), a.getDate())) /
			86_400_000,
	);
	if (days <= 0) return 'today';
	if (days === 1) return 'yesterday';
	if (days < 7) return `${days} days ago`;
	if (days < 31) {
		const w = Math.floor(days / 7);
		return w === 1 ? 'a week ago' : `${w} weeks ago`;
	}
	if (days < 365) {
		const m = Math.floor(days / 30);
		return m === 1 ? 'a month ago' : `${m} months ago`;
	}
	const y = Math.floor(days / 365);
	return y === 1 ? 'a year ago' : `${y} years ago`;
}
