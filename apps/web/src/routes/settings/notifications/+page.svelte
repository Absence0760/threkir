<script lang="ts">
	import { auth } from '#lib/stores/auth.svelte.ts';
	import { supabase } from '#lib/core/supabase.ts';
	import { effective } from '#lib/settings/settings.ts';
	import { m } from '#lib/i18n/store.svelte.ts';
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
		if (error) showToast(m('prefs.saveFailed', { error: error.message }), 'error');
	}
</script>

<PrefsPage heading={m('prefs.notificationsHeading')} tagline={m('prefs.notificationsTagline')} page={prefs}>
	<section class="card">
		<h2>{m('prefs.emailPushHeading')}</h2>
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
		<label class="checkbox-row">
			<input
				type="checkbox"
				bind:checked={notifyDataExportReady}
				onchange={() => prefs.save({ notify_data_export_ready: notifyDataExportReady ? 'on' : 'off' })}
				data-testid="notify-data-export-ready"
			/>
			<span>
				{m('prefs.notifyDataExportReady')}
				<span class="hint">{m('prefs.notifyDataExportReadyHint')}</span>
			</span>
		</label>
		<label class="checkbox-row">
			<input
				type="checkbox"
				bind:checked={notifyMention}
				onchange={() => prefs.save({ notify_mention: notifyMention ? 'on' : 'off' })}
				data-testid="notify-mention"
			/>
			<span>
				{m('prefs.notifyMention')}
				<span class="hint">{m('prefs.notifyMentionHint')}</span>
			</span>
		</label>
		<label class="checkbox-row">
			<input
				type="checkbox"
				bind:checked={notifyReaction}
				onchange={() => prefs.save({ notify_reaction: notifyReaction ? 'on' : 'off' })}
				data-testid="notify-reaction"
			/>
			<span>
				{m('prefs.notifyReaction')}
				<span class="hint">{m('prefs.notifyReactionHint')}</span>
			</span>
		</label>
		<label class="checkbox-row">
			<input
				type="checkbox"
				bind:checked={notifyCommentLike}
				onchange={() => prefs.save({ notify_comment_like: notifyCommentLike ? 'on' : 'off' })}
				data-testid="notify-comment-like"
			/>
			<span>
				{m('prefs.notifyCommentLike')}
				<span class="hint">{m('prefs.notifyCommentLikeHint')}</span>
			</span>
		</label>
		<label class="checkbox-row">
			<input
				type="checkbox"
				bind:checked={emailNewDeviceAlerts}
				onchange={() => prefs.save({ email_new_device_alerts: emailNewDeviceAlerts ? 'on' : 'off' })}
				data-testid="email-new-device-alerts"
			/>
			<span>
				{m('prefs.emailNewDeviceAlerts')}
				<span class="hint">{m('prefs.emailNewDeviceAlertsHint')}</span>
			</span>
		</label>
	</section>

	<section class="card">
		<h2>{m('prefs.optionalEmailsHeading')}</h2>
		<div class="form-stack">
			<label class="checkbox-row">
				<input
					type="checkbox"
					bind:checked={emailWeeklyDigest}
					onchange={() => setEngagementPref('email_weekly_digest', emailWeeklyDigest)}
					data-testid="email-weekly-digest"
				/>
				<span>
					{m('prefs.emailWeeklyDigest')}
					<span class="hint">{m('prefs.emailWeeklyDigestHint')}</span>
				</span>
			</label>
			<label class="checkbox-row">
				<input
					type="checkbox"
					bind:checked={emailLifecycleDrip}
					onchange={() => setEngagementPref('email_lifecycle_drip', emailLifecycleDrip)}
					data-testid="email-lifecycle-drip"
				/>
				<span>
					{m('prefs.emailLifecycleDrip')}
					<span class="hint">{m('prefs.emailLifecycleDripHint')}</span>
				</span>
			</label>
		</div>
	</section>
</PrefsPage>
