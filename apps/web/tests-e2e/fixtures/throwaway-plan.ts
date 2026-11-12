import { browserDate, noonOnBrowserDay } from './dates';
import { getAdminClient } from './local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from './saga-users';
import { insertRun } from './simulate';

/// A plan of its own on an account of its own, for a spec that marks
/// workouts done. Marking a workout on the shared seeded plan made every such
/// spec depend on what the others had left behind: a completion another spec
/// stamped (or its own, when a run died before teardown) turned the next
/// run's "two done" into three. Deleting the saga user takes the plan with it.
///
/// Four weeks from a week ago: a long run, an easy run and a tempo every
/// week, rest days between. The first two long runs are done through a linked
/// run, as the seed's are, so their editor cannot un-mark them.
export type ThrowawayPlan = { user: SagaUser; planId: string; name: string };

export const THROWAWAY_PLAN_DONE = 2;

export async function createThrowawayPlan(name: string): Promise<ThrowawayPlan> {
	const [user] = await createSagaUsers(1, { displayNames: [`${name} Runner`] });
	const admin = getAdminClient();
	const planId = crypto.randomUUID();
	const startOffset = -7;
	const { error: planError } = await admin.from('training_plans').insert({
		id: planId,
		user_id: user.id,
		name,
		goal_event: 'distance_half',
		goal_distance_m: 21_097,
		start_date: browserDate(startOffset),
		end_date: browserDate(startOffset + 27),
		status: 'active',
		days_per_week: 3,
	});
	if (planError) throw planError;

	const kindOnDay: Partial<Record<number, 'long' | 'easy' | 'tempo'>> = { 0: 'long', 2: 'easy', 4: 'tempo' };
	let longRunsDone = 0;
	for (let week = 0; week < 4; week++) {
		const weekId = crypto.randomUUID();
		const { error: weekError } = await admin
			.from('plan_weeks')
			.insert({ id: weekId, plan_id: planId, week_index: week, phase: 'build', target_volume_m: 30_000 });
		if (weekError) throw weekError;
		for (let day = 0; day < 7; day++) {
			const offset = startOffset + week * 7 + day;
			const kind = kindOnDay[day] ?? 'rest';
			let completed_run_id: string | null = null;
			if (kind === 'long' && longRunsDone < THROWAWAY_PLAN_DONE) {
				completed_run_id = await insertRun({
					user_id: user.id,
					started_at: noonOnBrowserDay(offset),
					distance_m: 16_000,
					duration_s: 5_400,
					source: 'app',
				});
				longRunsDone++;
			}
			const { error } = await admin.from('plan_workouts').insert({
				week_id: weekId,
				scheduled_date: browserDate(offset),
				kind,
				target_distance_m: kind === 'rest' ? null : kind === 'long' ? 16_000 : 8_000,
				completed_run_id,
			});
			if (error) throw error;
		}
	}
	return { user, planId, name };
}

export async function deleteThrowawayPlan(plan: ThrowawayPlan | undefined): Promise<void> {
	if (plan) await deleteSagaUsers([plan.user]);
}
