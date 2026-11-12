// The route assistant's location hint is a place label, never a position
// (the route consent bullet promises "never your precise coordinates"). The
// route builder labels a typed or map-picked start with the point itself, to
// four decimals, so that label must not be forwarded as the hint. The client
// drops it and the handler refuses it again, so an older client cannot send
// one either.

const COORDINATE_PAIR = /-?\d{1,3}(?:\.\d+)?\s*[,;]\s*-?\d{1,3}(?:\.\d+)?/;

export function isCoordinateLabel(label: string): boolean {
	return COORDINATE_PAIR.test(label);
}

/// The label the prompt may carry: trimmed, and null when it is empty or
/// states a position.
export function promptLocationLabel(label: string | null | undefined): string | null {
	const trimmed = label?.trim() ?? '';
	return trimmed.length > 0 && !isCoordinateLabel(trimmed) ? trimmed : null;
}
