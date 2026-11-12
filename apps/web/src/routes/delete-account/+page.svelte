<script lang="ts">
	import { m } from '#lib/i18n/store.svelte.ts';

	const lastUpdated = '2026-07-14';
	const privacyEmail = 'privacy@threkir.com';
</script>

<svelte:head>
	<title>{m('deleteAccount.documentTitle')}</title>
	<meta name="description" content={m('deleteAccount.metaDescription')} />
</svelte:head>

<div class="legal-page">
	<h1>{m('deleteAccount.h1')}</h1>
	<p class="lead">{m('deleteAccount.lead')}</p>
	<p class="meta">{m('deleteAccount.lastUpdated', { date: lastUpdated })}</p>

	<h2>{m('deleteAccount.s1Heading')}</h2>
	<p>{m('deleteAccount.s1Intro')}</p>
	<ul>
		<li>
			<strong>{m('deleteAccount.s1WebLabel')}</strong>{m('deleteAccount.s1WebPrefix')}<a
				href="/settings/account">{m('deleteAccount.s1WebLink')}</a
			>{m('deleteAccount.s1WebMiddle')}<strong>{m('deleteAccount.s1WebAction')}</strong>{m(
				'deleteAccount.s1WebSuffix'
			)}
		</li>
		<li>
			<strong>{m('deleteAccount.s1MobileLabel')}</strong>{m('deleteAccount.s1MobileBody')}
		</li>
	</ul>
	<p>
		{m('deleteAccount.s1PermanentPrefix')}<strong>{m('deleteAccount.s1PermanentEmphasis')}</strong>{m(
			'deleteAccount.s1PermanentSuffix'
		)}
	</p>

	<h2>{m('deleteAccount.s2Heading')}</h2>
	<p>
		{m('deleteAccount.s2Prefix')}<a href="mailto:{privacyEmail}">{privacyEmail}</a>{m(
			'deleteAccount.s2Suffix'
		)}
	</p>

	<h2>{m('deleteAccount.s3Heading')}</h2>
	<p>{m('deleteAccount.s3Intro')}</p>
	<ul>
		<li>{m('deleteAccount.s3Profile')}</li>
		<li>{m('deleteAccount.s3Runs')}</li>
		<li>{m('deleteAccount.s3Files')}</li>
		<li>{m('deleteAccount.s3Gym')}</li>
		<li>{m('deleteAccount.s3Training')}</li>
		<li>{m('deleteAccount.s3Social')}</li>
		<li>{m('deleteAccount.s3Notifications')}</li>
		<li>{m('deleteAccount.s3ThirdParty')}</li>
	</ul>

	<h2>{m('deleteAccount.s4Heading')}</h2>
	<ul>
		<li>
			<strong>{m('deleteAccount.s4BackupsLabel')}</strong>{m('deleteAccount.s4BackupsPrefix')}<strong
				>{m('deleteAccount.s4BackupsWindow')}</strong
			>{m('deleteAccount.s4BackupsSuffix')}
		</li>
		<li>
			<strong>{m('deleteAccount.s4AuditLabel')}</strong>{m('deleteAccount.s4AuditBody')}
		</li>
		<li>
			<strong>{m('deleteAccount.s4PaymentsLabel')}</strong>{m('deleteAccount.s4PaymentsBody')}
		</li>
		<li>
			<strong>{m('deleteAccount.s4MessagesLabel')}</strong>{m('deleteAccount.s4MessagesBody')}
		</li>
		<li>
			<strong>{m('deleteAccount.s4ReportsLabel')}</strong>{m('deleteAccount.s4ReportsBody')}
		</li>
	</ul>
	<p>
		{m('deleteAccount.s4PolicyPrefix')}<a href="/privacy">{m('deleteAccount.privacyPolicy')}</a>{m(
			'deleteAccount.s4PolicySuffix'
		)}
	</p>

	<h2>{m('deleteAccount.s5Heading')}</h2>
	<p>{m('deleteAccount.s5Intro')}</p>
	<ul>
		<li>
			<strong>{m('deleteAccount.s5ItemsLabel')}</strong>{m('deleteAccount.s5ItemsBody')}
		</li>
		<li>
			<strong>{m('deleteAccount.s5ServicesLabel')}</strong>{m('deleteAccount.s5ServicesBody')}
		</li>
		<li>
			<strong>{m('deleteAccount.s5OtherLabel')}</strong>{m('deleteAccount.s5OtherPrefix')}<a
				href="mailto:{privacyEmail}">{privacyEmail}</a
			>{m('deleteAccount.s5OtherSuffix')}
		</li>
	</ul>
	<p>
		{m('deleteAccount.s5BackupsPrefix')}<a href="/settings/account">{m('deleteAccount.s5ExportLink')}</a
		>{m('deleteAccount.s5BackupsSuffix')}
	</p>

	<h2>{m('deleteAccount.s6Heading')}</h2>
	<p>
		<a href="/privacy">{m('deleteAccount.privacyPolicy')}</a> ·
		<a href="/terms">{m('deleteAccount.terms')}</a> ·
		<a href="/health-data-notice">{m('deleteAccount.healthNotice')}</a> ·
		<a href="/cookie-notice">{m('deleteAccount.cookieNotice')}</a>
	</p>
</div>

<style>
	.legal-page {
		max-width: 48rem;
		margin: 0 auto;
		padding: var(--page-padding-y) var(--page-padding-x);
		line-height: 1.6;
	}
	h1 {
		margin-top: 0;
	}
	h2 {
		margin-top: var(--space-2xl);
		font-size: 1.25rem;
	}
	.lead {
		font-size: 1.1rem;
		color: var(--color-text-secondary);
	}
	.meta {
		color: var(--color-text-tertiary);
		font-size: 0.875rem;
		margin-bottom: var(--space-2xl);
	}
	ul {
		padding-inline-start: 1.25rem;
	}
	li {
		margin-bottom: var(--space-xs);
	}
</style>
