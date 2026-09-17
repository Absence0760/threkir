<script lang="ts">
	import { auth } from '$lib/stores/auth.svelte';
	import { supabase } from '$lib/core/supabase';
	import { effective } from '$lib/settings/settings';
	import { m } from '$lib/i18n/store.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import { createPrefsPage } from '$lib/settings/prefs_page.svelte';
	import PrefsPage from '$lib/components/settings/PrefsPage.svelte';

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

	const prefs = createPrefsPage(async ({ settings }) => {
		emailNotifications = effective(settings, 'email_notifications', 'important') ?? 'important';
		pushNotifications = effective(settings, 'push_notifications', 'important') ?? 'important';
		emailWeeklyDigest = effective<string>(settings, 'email_weekly_digest', 'off') === 'on';
		emailLifecycleDrip = effective<string>(settings, 'email_lifecycle_drip', 'off') === 'on';
		// Only the literal 'off' mutes — an absent key is a runner who never
		// chose and a corrupt one is not a decision, matching the worker's own
		// read in mailer.go's kindMuted.
		notifyDataExportReady = effective<string>(settings, 'notify_data_export_ready', 'on') !== 'off';
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
			<label>
				<span class="label-text">{m('prefs.emailNotifications')}</span>
				<select bind:value={emailNotifications} onchange={() => prefs.save({ email_notifications: emailNotifications })}>
					<option value="important">{m('prefs.emailNotifImportant')}</option>
					<option value="all">{m('prefs.emailNotifAll')}</option>
					<option value="off">{m('prefs.emailNotifOff')}</option>
				</select>
			</label>
			<p class="section-hint">{m('prefs.emailNotifHint')}</p>
			<label>
				<span class="label-text">{m('prefs.pushNotifications')}</span>
				<select bind:value={pushNotifications} onchange={() => prefs.save({ push_notifications: pushNotifications })}>
					<option value="important">{m('prefs.pushNotifImportant')}</option>
					<option value="all">{m('prefs.pushNotifAll')}</option>
					<option value="off">{m('prefs.pushNotifOff')}</option>
				</select>
			</label>
			<p class="section-hint">{m('prefs.pushNotifHint')}</p>
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
