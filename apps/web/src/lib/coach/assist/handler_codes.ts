/// The code a coach's client branches on when the athlete has not allowed the
/// coach assistant on this link. Its own module so the browser bundle can read
/// it without importing the handler, which carries the Anthropic SDK.
export const ATHLETE_CONSENT_REQUIRED = 'athlete_consent_required';
