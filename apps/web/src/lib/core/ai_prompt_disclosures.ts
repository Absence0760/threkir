// What each single-shot Anthropic prompt sends, field by field, and where that
// is disclosed. The AI Coach has its own registry (`COACH_CONTEXT_REGISTRY` in
// `coach/context.ts`) because its payload is gated per field on the accepted
// disclosure version; these prompts are gated as a whole, so one consent bullet
// covers each prompt and the field list is what the sub-processor record owes.
//
// `ai_prompt_disclosures.test.ts` runs each prompt's real builder over a
// fixture wrapped in a recording proxy and fails when the builder reads a field
// this table does not name, or this table names a field the builder no longer
// reads. Each `sent` line must also appear in that prompt's section of the
// Anthropic row of `docs/compliance/sub-processors.md`.

import type { MessageKey } from '../i18n/messages';

export type PromptFieldDisclosure =
	/// The phrase in the sub-processor record that discloses this field.
	| { sent: string }
	/// Read by the builder but never written into the prompt; the reason says
	/// what it is read for.
	| { notSent: string };

export interface AiPromptEntry {
	/// The handler that calls the model, relative to `apps/web/src/lib/`.
	handler: string;
	/// The exported function that builds the user turn the handler sends.
	builder: string;
	/// The consent bullet in the AI disclosure that covers this prompt.
	bullet: MessageKey;
	/// Every input path the builder reads. Array elements are written `[]`.
	fields: Readonly<Record<string, PromptFieldDisclosure>>;
}

const DONE_STATE = { sent: 'whether each workout is done, skipped, past or fixed' } as const;

export const AI_PROMPT_DISCLOSURES = {
	'route-describe': {
		handler: 'routes/route_describe/handler.ts',
		builder: 'routeDescribeUserMessage',
		bullet: 'coachPage.consentBulletRoutes',
		fields: {
			name: { sent: "the route's name, only when the viewer owns the route or it is public" },
			'parts.distanceM': { sent: 'distance' },
			'parts.elevationM': { sent: 'elevation gain' },
			'parts.gainPerKm': { sent: 'climb per kilometre or mile' },
			'parts.elevation': { sent: 'elevation character (flat, rolling, hilly or mountainous)' },
			'parts.surface': { sent: 'surface' },
			'parts.shape': { sent: 'shape (loop, out-and-back or point-to-point)' },
			unit: { sent: "the viewer's distance unit" },
			locale: { sent: "the name of the viewer's language" },
		},
	},
	'route-request': {
		handler: 'routes/route_request/handler.ts',
		builder: 'routeRequestUserMessage',
		bullet: 'coachPage.consentBulletRoutes',
		fields: {
			requestText: { sent: 'the request the runner types' },
			locationLabel: { sent: 'a place label for the start' },
		},
	},
	'plan-request': {
		handler: 'training/plan_request/handler.ts',
		builder: 'planRequestUserTurn',
		bullet: 'coachPage.consentBulletPlanRequest',
		fields: {
			requestText: { sent: 'the plan description the runner types' },
			today: { sent: "the runner's current date" },
		},
	},
	'season-request': {
		handler: 'training/season_request/handler.ts',
		builder: 'seasonRequestUserTurn',
		bullet: 'coachPage.consentBulletPlanRequest',
		fields: {
			requestText: { sent: 'the season description the runner types' },
			today: { sent: "the runner's current date" },
		},
	},
	'plan-edit': {
		handler: 'training/plan_edit/handler.ts',
		builder: 'planEditUserTurn',
		bullet: 'coachPage.consentBulletPlanEdit',
		fields: {
			requestText: { sent: 'the change the runner types' },
			today: { sent: "the runner's current date and weekday" },
			'plan.today': { notSent: 'the same date as `today`, read to tag past workouts' },
			'plan.refByWorkout': { sent: 'a per-request reference for each workout (W1, W2, …)' },
			'plan.snapshot.plan.start_date': { sent: "each open week's start and end dates" },
			'plan.snapshot.weeks[].id': { notSent: 'join key from week to workouts' },
			'plan.snapshot.weeks[].week_index': { sent: 'week number' },
			'plan.snapshot.weeks[].phase': { sent: 'phase' },
			'plan.snapshot.weeks[].target_volume_m': { sent: 'planned weekly distance' },
			'plan.snapshot.workouts[].id': { notSent: 'looked up to the per-request reference' },
			'plan.snapshot.workouts[].week_id': { notSent: 'join key from workout to week' },
			'plan.snapshot.workouts[].scheduled_date': { sent: "each workout's date and weekday" },
			'plan.snapshot.workouts[].kind': { sent: 'type' },
			'plan.snapshot.workouts[].target_distance_m': { sent: 'target distance' },
			'plan.snapshot.workouts[].target_duration_seconds': { sent: 'target duration' },
			'plan.snapshot.workouts[].completed_run_id': DONE_STATE,
			'plan.snapshot.workouts[].manually_completed': DONE_STATE,
			'plan.snapshot.workouts[].skipped_at': DONE_STATE,
		},
	},
	'plate-photo': {
		handler: 'nutrition/plate_photo/handler.ts',
		builder: 'platePhotoUserContent',
		bullet: 'coachPage.consentBulletPlatePhoto',
		fields: {
			'image.base64': { sent: 'the meal photo, with its metadata stripped' },
			'image.mediaType': { sent: 'its image format' },
			note: { sent: 'the note the runner adds, if any' },
		},
	},
} as const satisfies Record<string, AiPromptEntry>;

export type AiPromptId = keyof typeof AI_PROMPT_DISCLOSURES;
