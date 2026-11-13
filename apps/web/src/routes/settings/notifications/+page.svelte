<script lang="ts">
	import ListRow from '#lib/components/ListRow.svelte';
	import SectionHeader from '#lib/components/SectionHeader.svelte';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import { supabase } from '#lib/core/supabase.ts';
	import { effective } from '#lib/settings/settings.ts';
	import { m } from '#lib/i18n/store.svelte.ts';
	import { errorCopy } from '#lib/i18n/error_copy.ts';
	import { showToast } from '#lib/stores/toast.svelte.ts';
	import { createPrefsPage } from '#lib/settings/prefs_page.svelte.ts';
	import PrefsPage from '#lib/components/settings/PrefsPage.svelte';

	let emailNotifications = $state<'all' | 'important' | 'off'>('important');
	// Independent of email_notifications — muting email must not mute push.
	let pushNotifications = $state<'all' | 'important' | 'off'>('important');
	// Opt-IN consent for the two engagement streams (bulk/promotional mail).
	// Default off; marketing consent is never inferred from the transactional
	// email_notifications key, and opting into one stream is never consent to
	// the other.
	let emailWeeklyDigest = $state(false);
	let emailLifecycleDrip = $state(false);
	// Per-kind mute for the data-export-ready notice (decisions § 729). Opt-OUT,
	// unlike the engagement streams: the subject requested the export minutes
	// earlier. It only ever subtracts — muting a channel above still silences it.
	let notifyDataExportReady = $state(true);
	// Per-kind mutes for the social signals of decisions § 1971, same opt-OUT
	// shape and the same subtract-only scope as the export notice.
	let notifyMention = $state(true);
	let notifyReaction = $state(true);
	let notifyCommentLike = $state(true);
	let notifyFollowRequest = $state(true);
	// Club and event notices in the default set (decisions § 2358): each is
	// raised by someone else's action, so each needs a control narrower than
	// the whole channel.
	let notifyEventRsvp = $state(true);
	let notifyClubJoinRequest = $state(true);
	let notifyClubJoinApproved = $state(true);
	let notifyEventUpdated = $state(true);
	// A verified organiser's course alert (decisions § 2407): raised by the
	// organiser, in the default set, so it gets its own mute.
	let notifyCourseAlert = $state(true);
	let notifyRaceStartingSoon = $state(true);
	// Unlike the mutes above this one also withholds the inbox row:
	// enqueue_workout_reminders raises nothing for a runner who turned it off,
	// because a clock raises it every morning rather than someone's action.
	let notifyWorkoutReminder = $state(true);
	// The park course month-close notice (#1343) is raised by a clock too, so
	// like the workout reminder its mute also withholds the inbox row. It is
	// in neither default set: email and push carry it only under "all".
	let notifyParkCourseMonth = $state(true);
	// Opt-OUT alert for a sign-in from a device class the account has not used
	// before (security_email new_device_sign_in). The password-changed notice
	// has no control on purpose: it is the one mail a takeover must not mute.
	let emailNewDeviceAlerts = $state(true);

	const prefs = createPrefsPage(async ({ settings }) => {
		emailNotifications = effective(settings, 'email_notifications', 'important') ?? 'important';
		pushNotifications = effective(settings, 'push_notifications', 'important') ?? 'important';
		emailWeeklyDigest = effective<string>(settings, 'email_weekly_digest', 'off') === 'on';
		emailLifecycleDrip = effective<string>(settings, 'email_lifecycle_drip', 'off') === 'on';
		// Only the literal 'off' mutes — an absent key is a runner who never
		// chose and a corrupt one is not a decision, matching the worker's own
		// read in mailer.go's kindMuted.
		notifyDataExportReady = effective<string>(settings, 'notify_data_export_ready', 'on') !== 'off';
		notifyMention = effective<string>(settings, 'notify_mention', 'on') !== 'off';
		notifyReaction = effective<string>(settings, 'notify_reaction', 'on') !== 'off';
		notifyCommentLike = effective<string>(settings, 'notify_comment_like', 'on') !== 'off';
		notifyFollowRequest = effective<string>(settings, 'notify_follow_request', 'on') !== 'off';
		notifyEventRsvp = effective<string>(settings, 'notify_event_rsvp', 'on') !== 'off';
		notifyClubJoinRequest = effective<string>(settings, 'notify_club_join_request', 'on') !== 'off';
		notifyClubJoinApproved = effective<string>(settings, 'notify_club_join_approved', 'on') !== 'off';
		notifyEventUpdated = effective<string>(settings, 'notify_event_updated', 'on') !== 'off';
		notifyCourseAlert = effective<string>(settings, 'notify_course_alert', 'on') !== 'off';
		notifyRaceStartingSoon = effective<string>(settings, 'notify_race_starting_soon', 'on') !== 'off';
		notifyWorkoutReminder = effective<string>(settings, 'notify_workout_reminder', 'on') !== 'off';
		notifyParkCourseMonth = effective<string>(settings, 'notify_park_course_month', 'on') !== 'off';
		emailNewDeviceAlerts = effective<string>(settings, 'email_new_device_alerts', 'on') !== 'off';
	});

	// Re-opting into an engagement stream must lift any prior one-click
	// unsubscribe address block (email_suppressions, reason 'unsubscribe'), or
	// the send stays silently hard-blocked while the toggle reads 'on' (#392).
	// The suppression row is address-keyed (covers every stream), so either
	// toggle turning on clears it; the SECURITY DEFINER RPC is scoped to the
	// caller's own address and never touches a bounce/complaint/manual row.
	async function setEngagementPref(key: 'email_weekly_digest' | 'email_lifecycle_drip', on: boolean) {
		prefs.save({ [key]: on ? 'on' : 'off' });
		if (!on || !auth.user) return;
		const { error } = await supabase.rpc('clear_my_unsubscribe_suppression');
		if (error) showToast(m('prefs.saveFailed', { error: errorCopy(error, m, 'prefs.saveFailed') }), 'error');
	}
</script>

<PrefsPage heading={m('prefs.notificationsHeading')} tagline={m('prefs.notificationsTagline')} page={prefs}>
	<section class="card">
		<SectionHeader label={m('prefs.emailPushHeading')} class="prefs-section-head" />
		<div class="form-grid">
			<div class="field">
				<label>
					<span class="label-text">{m('prefs.emailNotifications')}</span>
					<select bind:value={emailNotifications} onchange={() => prefs.save({ email_notifications: emailNotifications })} aria-describedby="email-notifications-hint">
						<option value="important">{m('prefs.emailNotifImportant')}</option>
						<option value="all">{m('prefs.emailNotifAll')}</option>
						<option value="off">{m('prefs.emailNotifOff')}</option>
					</select>
				</label>
				<p class="hint" id="email-notifications-hint">{m('prefs.emailNotifHint')}</p>
			</div>
			<div class="field">
				<label>
					<span class="label-text">{m('prefs.pushNotifications')}</span>
					<select bind:value={pushNotifications} onchange={() => prefs.save({ push_notifications: pushNotifications })} aria-describedby="push-notifications-hint">
						<option value="important">{m('prefs.pushNotifImportant')}</option>
						<option value="all">{m('prefs.pushNotifAll')}</option>
						<option value="off">{m('prefs.pushNotifOff')}</option>
					</select>
				</label>
				<p class="hint" id="push-notifications-hint">{m('prefs.pushNotifHint')}</p>
			</div>
		</div>
		<ListRow
			kind="toggle"
			title={m('prefs.notifyDataExportReady')}
			subtitle={m('prefs.notifyDataExportReadyHint')}
			bind:checked={notifyDataExportReady}
			onchange={() => prefs.save({ notify_data_export_ready: notifyDataExportReady ? 'on' : 'off' })}
			testid="notify-data-export-ready"
		/>
		<ListRow
			kind="toggle"
			title={m('prefs.notifyMention')}
			subtitle={m('prefs.notifyMentionHint')}
			bind:checked={notifyMention}
			onchange={() => prefs.save({ notify_mention: notifyMention ? 'on' : 'off' })}
			testid="notify-mention"
		/>
		<ListRow
			kind="toggle"
			title={m('prefs.notifyReaction')}
			subtitle={m('prefs.notifyReactionHint')}
			bind:checked={notifyReaction}
			onchange={() => prefs.save({ notify_reaction: notifyReaction ? 'on' : 'off' })}
			testid="notify-reaction"
		/>
		<ListRow
			kind="toggle"
			title={m('prefs.notifyCommentLike')}
			subtitle={m('prefs.notifyCommentLikeHint')}
			bind:checked={notifyCommentLike}
			onchange={() => prefs.save({ notify_comment_like: notifyCommentLike ? 'on' : 'off' })}
			testid="notify-comment-like"
		/>
		<ListRow
			kind="toggle"
			title={m('prefs.notifyFollowRequest')}
			subtitle={m('prefs.notifyFollowRequestHint')}
			bind:checked={notifyFollowRequest}
			onchange={() => prefs.save({ notify_follow_request: notifyFollowRequest ? 'on' : 'off' })}
			testid="notify-follow-request"
		/>
		<ListRow
			kind="toggle"
			title={m('prefs.notifyEventRsvp')}
			subtitle={m('prefs.notifyEventRsvpHint')}
			bind:checked={notifyEventRsvp}
			onchange={() => prefs.save({ notify_event_rsvp: notifyEventRsvp ? 'on' : 'off' })}
			testid="notify-event-rsvp"
		/>
		<ListRow
			kind="toggle"
			title={m('prefs.notifyClubJoinRequest')}
			subtitle={m('prefs.notifyClubJoinRequestHint')}
			bind:checked={notifyClubJoinRequest}
			onchange={() => prefs.save({ notify_club_join_request: notifyClubJoinRequest ? 'on' : 'off' })}
			testid="notify-club-join-request"
		/>
		<ListRow
			kind="toggle"
			title={m('prefs.notifyClubJoinApproved')}
			subtitle={m('prefs.notifyClubJoinApprovedHint')}
			bind:checked={notifyClubJoinApproved}
			onchange={() => prefs.save({ notify_club_join_approved: notifyClubJoinApproved ? 'on' : 'off' })}
			testid="notify-club-join-approved"
		/>
		<ListRow
			kind="toggle"
			title={m('prefs.notifyEventUpdated')}
			subtitle={m('prefs.notifyEventUpdatedHint')}
			bind:checked={notifyEventUpdated}
			onchange={() => prefs.save({ notify_event_updated: notifyEventUpdated ? 'on' : 'off' })}
			testid="notify-event-updated"
		/>
		<ListRow
			kind="toggle"
			title={m('prefs.notifyCourseAlert')}
			subtitle={m('prefs.notifyCourseAlertHint')}
			bind:checked={notifyCourseAlert}
			onchange={() => prefs.save({ notify_course_alert: notifyCourseAlert ? 'on' : 'off' })}
			testid="notify-course-alert"
		/>
		<ListRow
			kind="toggle"
			title={m('prefs.notifyRaceStartingSoon')}
			subtitle={m('prefs.notifyRaceStartingSoonHint')}
			bind:checked={notifyRaceStartingSoon}
			onchange={() => prefs.save({ notify_race_starting_soon: notifyRaceStartingSoon ? 'on' : 'off' })}
			testid="notify-race-starting-soon"
		/>
		<ListRow
			kind="toggle"
			title={m('prefs.notifyWorkoutReminder')}
			subtitle={m('prefs.notifyWorkoutReminderHint')}
			bind:checked={notifyWorkoutReminder}
			onchange={() => prefs.save({ notify_workout_reminder: notifyWorkoutReminder ? 'on' : 'off' })}
			testid="notify-workout-reminder"
		/>
		<ListRow
			kind="toggle"
			title={m('prefs.notifyParkCourseMonth')}
			subtitle={m('prefs.notifyParkCourseMonthHint')}
			bind:checked={notifyParkCourseMonth}
			onchange={() => prefs.save({ notify_park_course_month: notifyParkCourseMonth ? 'on' : 'off' })}
			testid="notify-park-course-month"
		/>
		<ListRow
			kind="toggle"
			title={m('prefs.emailNewDeviceAlerts')}
			subtitle={m('prefs.emailNewDeviceAlertsHint')}
			bind:checked={emailNewDeviceAlerts}
			onchange={() => prefs.save({ email_new_device_alerts: emailNewDeviceAlerts ? 'on' : 'off' })}
			testid="email-new-device-alerts"
		/>
	</section>

	<section class="card">
		<SectionHeader label={m('prefs.optionalEmailsHeading')} class="prefs-section-head" />
		<div class="form-stack">
			<ListRow
				kind="toggle"
				title={m('prefs.emailWeeklyDigest')}
				subtitle={m('prefs.emailWeeklyDigestHint')}
				bind:checked={emailWeeklyDigest}
				onchange={() => setEngagementPref('email_weekly_digest', emailWeeklyDigest)}
				testid="email-weekly-digest"
			/>
			<ListRow
				kind="toggle"
				title={m('prefs.emailLifecycleDrip')}
				subtitle={m('prefs.emailLifecycleDripHint')}
				bind:checked={emailLifecycleDrip}
				onchange={() => setEngagementPref('email_lifecycle_drip', emailLifecycleDrip)}
				testid="email-lifecycle-drip"
			/>
		</div>
	</section>
</PrefsPage>
