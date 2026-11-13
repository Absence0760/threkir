<script lang="ts">
	import { NOT_PROVIDED, OPERATOR, OPERATOR_FACTS_COMPLETE } from '#lib/legal/operator.ts';

	const lastUpdated = '2026-11-13';
</script>

<svelte:head>
	<title>Privacy Policy — Threkir</title>
	<meta name="description" content="How Threkir collects, uses, and protects your personal data." />
</svelte:head>

<div class="legal-page">
	{#if !OPERATOR_FACTS_COMPLETE}
		<div class="pending-banner" data-testid="operator-facts-pending">
			A small number of operator details are still being finalised: our registered postal address,
			the EU and UK representative appointments, and the governing-law state. Each pending item is
			marked below. Until they are published here, direct any matter that would otherwise go to
			them to <a href="mailto:privacy@threkir.com">privacy@threkir.com</a>.
		</div>
	{/if}

	<h1>Privacy Policy</h1>
	<p class="lead">
		Threkir is a running, training, and fitness app. This policy explains what data we collect,
		why, who we share it with, how long we keep it, and how to exercise your rights.
	</p>
	<p class="meta">Last updated: {lastUpdated}</p>

	<h2>1. Who we are</h2>
	<p>
		<strong>Controller:</strong> {OPERATOR.serviceName}, operated by {OPERATOR.controllerDescription}.
		<br />
		<strong>Postal address:</strong>
		{#if OPERATOR.postalAddress === NOT_PROVIDED}we do not publish a postal address; write to
			<a href="mailto:privacy@threkir.com">privacy@threkir.com</a>, which reaches the controller
			directly{:else if OPERATOR.postalAddress}{OPERATOR.postalAddress}{:else}<em>pending publication — write to
			<a href="mailto:privacy@threkir.com">privacy@threkir.com</a> in the meantime</em>{/if}
		<br />
		<strong>Privacy contact:</strong> <a href="mailto:privacy@threkir.com">privacy@threkir.com</a>.
		We have not appointed a Data Protection Officer; we are not required to, and the privacy
		contact above reaches the controller directly.
		<br />
		<strong>EU representative (Art 27 GDPR):</strong>
		{#if OPERATOR.euRepresentative === NOT_PROVIDED}we have not appointed one; EU residents and
			supervisory authorities can contact the controller directly at
			<a href="mailto:privacy@threkir.com">privacy@threkir.com</a>{:else if OPERATOR.euRepresentative}{OPERATOR.euRepresentative.name}, {OPERATOR.euRepresentative
				.address} (<a href="mailto:{OPERATOR.euRepresentative.email}"
				>{OPERATOR.euRepresentative.email}</a
			>){:else}<em>appointment in progress; until published here, EU residents and supervisory
			authorities may contact <a href="mailto:privacy@threkir.com">privacy@threkir.com</a>
			directly</em>{/if}
		<br />
		<strong>UK representative (Art 27 UK GDPR):</strong>
		{#if OPERATOR.ukRepresentative === NOT_PROVIDED}we have not appointed one; UK residents and the
			ICO can contact the controller directly at
			<a href="mailto:privacy@threkir.com">privacy@threkir.com</a>{:else if OPERATOR.ukRepresentative}{OPERATOR.ukRepresentative.name}, {OPERATOR.ukRepresentative
				.address} (<a href="mailto:{OPERATOR.ukRepresentative.email}"
				>{OPERATOR.ukRepresentative.email}</a
			>){:else}<em>appointment in progress; until published here, UK residents and the ICO may
			contact <a href="mailto:privacy@threkir.com">privacy@threkir.com</a> directly</em>{/if}
	</p>

	<h2>2. What data we collect</h2>
	<ul>
		<li>
			<strong>Account</strong>: email address, optional display name, optional profile photo,
			optional gender and date of birth (used for tiered leaderboards and age-graded results).
		</li>
		<li>
			<strong>Settings</strong>: your app preferences, including your preferred language (the
			language of the emails, push notifications and training-plan calendar feed we send you, and
			of an AI route description when your device does not tell us its language) and your device's
			time zone (so a coach you link with sees the same "today" for your training plan as you do).
		</li>
		<li>
			<strong>Activity</strong>: GPS tracks, distance, duration, pace, elevation, heart rate
			(when paired with a sensor or imported from a third-party app), step count, activity type,
			and activity photos you upload.
		</li>
		<li>
			<strong>Health and body data (with your explicit consent)</strong>: height, body-weight
			entries, activity level, nutrition targets, food-log entries, and hydration amounts. Gym
			workouts (exercises, sets, reps, weights) are also stored. Heart rate and health imports
			fall under the same explicit-consent gate.
		</li>
		<li>
			<strong>Race checkpoint data</strong>: if you take part in an organised event that uses our
			race-director tools, aid-station staff may record your bib crossings (in/out times) and —
			at events that run medical weigh-ins — your body weight and any medical hold or note. The
			weigh-in and medical fields are special-category health data; they are scrubbed after 90
			days (the split times are your race result and are kept like any other result).
		</li>
		<li>
			<strong>Privacy zones</strong>: the coordinates of areas you designate (for example around
			your home) so that your tracks can be clipped before anyone else sees them. These
			coordinates exist to protect you and are never shown to other users.
		</li>
		<li>
			<strong>Live location</strong>: if you turn on live spectator tracking, real-time location
			pings during the run, kept for 48 hours (see section 7).
		</li>
		<li>
			<strong>Social</strong>: kudos, comments, photos, clubs you join, people you follow, event
			RSVPs, direct messages you exchange with other users (including photos you send in them and reactions you put on them), the group conversations you belong to (the group's name, who invited you and when, when you joined or left, your role, and how far you have read), and any blocks or reports you file.
		</li>
		<li>
			<strong>Park course reports</strong>: when you report a problem with a park course, the
			reason and the note you write, and an email address if you give one so we can reply. You
			can report without an account. Only Threkir's moderators see a report. To limit abuse we
			count reports per network address using a hash of the address, never the address itself,
			and delete that count within a day.
		</li>
		<li>
			<strong>Safety contacts</strong>: email addresses of people you nominate for safety
			features. If you add someone else's address, make sure you have their agreement.
		</li>
		<li>
			<strong>AI Coach</strong>: every chat message you send. We pass each prompt to our AI
			provider together with a summary of your recent training to generate a useful response.
		</li>
		<li data-testid="ai-assistants-data">
			<strong>AI assistants</strong> (only when you use them): the text you type into the route
			assistant, the plan assistant (including the season planner), or plan edits, plus the facts
			each one needs, all listed in section 5. Nothing you type there is kept by us beyond the
			settings, race list, or plan changes you choose to save.
		</li>
		<li>
			<strong>Meal photos</strong> (Pro, only if you use the plate-photo logger): the photo of a
			meal you choose, sent to our AI provider once to estimate the food on the plate. We strip
			location and camera metadata before it leaves our servers and never store the photo; only
			the food entries you review and save are kept.
		</li>
		<li>
			<strong>Subscription</strong>: subscription tier and renewal state (we do not see or store
			card numbers — that data goes directly to Stripe / Apple / Google).
		</li>
		<li>
			<strong>Paid events and fundraising</strong>: if you register for a paid event or donate to
			a fundraiser, your order state and, for donations, the display name and message you choose
			to show. If you host paid events, we store only your Stripe account identifier — your
			banking and identity documents go directly to Stripe.
		</li>
		<li>
			<strong>Device + network</strong>: device type, app version, IP address (truncated for
			analytics), error logs, and — if you enable notifications — a push token.
		</li>
		<li>
			<strong>Third-party imports</strong>: when you connect Strava, Garmin, Health Connect, or
			HealthKit, we receive the activity data they publish to us.
		</li>
		<li data-testid="signup-source">
			<strong>How you found us</strong>: when you create an account on the website, where your
			browser first arrived from in that visit — the campaign tags in the link you followed
			(<code>utm_source</code>, <code>utm_medium</code>, <code>utm_campaign</code>), or else the
			address of the site that sent you (for example <code>l.instagram.com</code>), or "direct"
			when there was none. It is held in your browser for that tab only and sent to us only if you
			sign up. We use it only to count which of our social accounts and links bring new members.
		</li>
	</ul>
	<p data-testid="health-platform-data">
		Data we read from <strong>Apple HealthKit</strong> or <strong>Android Health Connect</strong>
		is used only to provide the features you connected it for, such as importing your workouts and
		estimating calories from your body weight. We never use it for advertising, marketing, or
		data mining, we never sell it, and we never disclose it to advertisers or data brokers.
	</p>
	<p data-testid="logged-out-visitors">
		<strong>Visitors without an account</strong>: if you open a shared run, route, or other share
		page without signing in, we collect no account data about you. Our hosting providers (AWS and
		Supabase) receive your IP address and browser details (such as the user agent) with each page
		request, as any website does. On a shared run or route, the map (and, on a shared route, the 3D
		course preview) stays a placeholder until you tap "Load map" or "Load preview"; only then does your browser send
		your IP address, browser details, and the map area on screen to MapTiler (see section 5). The
		tap covers that one view: the next time you open a share page, it asks again. Error monitoring
		in your browser stays off unless you accept the cookie banner, which on share pages covers
		nothing else.
	</p>

	<h2>3. Why we process it (lawful basis)</h2>
	<table>
		<thead>
			<tr><th>Purpose</th><th>Lawful basis</th></tr>
		</thead>
		<tbody>
			<tr><td>Provide the core service (record runs, sync across devices, social features)</td><td>Contract — Art 6(1)(b) GDPR</td></tr>
			<tr><td>Heart rate, health imports, body metrics, nutrition and food logs, checkpoint medical weigh-ins</td><td>Explicit consent for special-category data — Art 9(2)(a) GDPR</td></tr>
			<tr><td>AI Coach</td><td>Consent — Art 6(1)(a) GDPR</td></tr>
			<tr><td>AI route assistant, AI plan assistant (including the season planner), and AI plan edits</td><td>Consent — Art 6(1)(a) GDPR, given by accepting the AI disclosure that names each feature</td></tr>
			<tr><td>Serving a share page to a visitor without an account, and keeping it secure (request logs)</td><td>Legitimate interest — Art 6(1)(f) GDPR</td></tr>
			<tr><td>Loading map tiles and the 3D course preview on a share page for a visitor without an account</td><td>Consent — Art 6(1)(a) GDPR, given by the "Load map" or "Load preview" tap for that view</td></tr>
			<tr><td>Paid event registration, fundraising donations, Pro subscription billing</td><td>Contract — Art 6(1)(b) GDPR</td></tr>
			<tr><td>Counting which of our social accounts and links bring new members (where you first arrived from when you signed up)</td><td>Legitimate interest — Art 6(1)(f) GDPR</td></tr>
			<tr><td>Marketing email (only if opted in)</td><td>Consent</td></tr>
			<tr><td>Error monitoring, abuse prevention, moderation of reported content, and keeping evidence of reported abuse for user safety and to establish or defend legal claims</td><td>Legitimate interest — Art 6(1)(f) GDPR</td></tr>
			<tr><td>Comply with a subpoena, court order, or store demand</td><td>Legal obligation — Art 6(1)(c) GDPR</td></tr>
		</tbody>
	</table>
	<p>
		Where processing rests on consent you can withdraw it at any time (section 8) without
		affecting the lawfulness of prior processing.
	</p>

	<h2>4. Automated decision-making</h2>
	<p>
		We do not make decisions about you that produce legal or similarly significant effects based
		solely on automated processing (Art 22 GDPR). The AI Coach, the AI assistants, and the
		training-plan generator produce suggestions only — nothing they output changes your access to
		the service, your pricing, or your account standing, and you are free to ignore them. The plan
		assistant only fills in fields you review, and plan edits change nothing until you approve
		them.
	</p>

	<h2 id="sub-processors">5. Who we share with (sub-processors)</h2>
	<p>
		Our service relies on a small set of vetted sub-processors. Each receives only the data it
		needs for its purpose. The current list — what each is for, and what it receives:
	</p>
	<ul>
		<li>
			<strong>Supabase</strong> (hosted in eu-west-2, London) — database, authentication, file
			storage, and the transactional auth emails (signup confirmation, password reset). Holds all
			account, activity (including GPS tracks and health-related fields), and social data.
		</li>
		<li>
			<strong>Amazon Web Services</strong> — web hosting (S3, CloudFront, Lambda, KMS, Route 53).
			Serves the web bundle and holds data-export Storage objects and server logs.
		</li>
		<li>
			<strong>Fly.io</strong> (London) — background workers, route processing, and the live
			spectator hub. Your run tracks transit through map-matching and route-generation jobs. The
			routing engines themselves (OSRM, GraphHopper, and our own loop-search service) are
			self-hosted on this infrastructure — no third party beyond Fly.io is involved.
		</li>
		<li>
			<strong>Upstash Redis</strong> — an optional cache for the live spectator hub. When our
			deployment uses it, it briefly holds live-run ping coordinates keyed by run id, expiring on
			the same 48-hour window as our own store. When not enabled, live pings never leave our own
			infrastructure.
		</li>
		<li>
			<strong>Anthropic</strong> (or, on fallback, OpenAI) — AI Coach. Receives your chat prompt
			plus a summary of your recent training (which can include heart-rate and goal data) and, once
			you have accepted the current AI disclosure, a summary of your recent gym sessions and, only
			with health-data consent, a 7-day summary of your food log. We use
			the provider's commercial API: your prompts and the responses are <strong>not used to train
			the provider's models</strong>, and under Anthropic's default API retention policy inputs and
			outputs are deleted from Anthropic's systems within 30 days of processing (material flagged
			by automated trust-and-safety screening can be retained longer). Your chat history itself is
			stored by us, not the provider — see section 7.
		</li>
		<li>
			<strong>Anthropic</strong> — plate-photo logger (Pro). Receives one meal photo per request,
			with its location and camera metadata already removed, and returns estimated food entries.
			The same no-training and 30-day retention terms apply; Threkir keeps no copy of the photo.
		</li>
		<li data-testid="ai-assistants-sub-processor">
			<strong>Anthropic</strong> — AI assistants, only when you use one and have accepted the AI
			disclosure that names it. No account identifier, email, or name is sent with any of them. The
			same no-training and 30-day retention terms apply. Each sends only:
			<ul>
				<li>
					<strong>Route assistant, request</strong>: the route you describe in your own words and,
					if you picked a start point, its place label (never its coordinates). It returns route
					settings; the route itself is drawn by our own routing engines.
				</li>
				<li>
					<strong>Route assistant, description</strong> (Pro): the route's distance, total climb and
					climb per kilometre or mile, surface, and shape (loop, out-and-back, or point-to-point,
					worked out on our servers from the start and end points, which are not sent), plus your
					distance unit and language. The route's name is included only when the route is yours or
					is public.
				</li>
				<li>
					<strong>Plan assistant</strong>: the plan you describe in your own words (for example your
					goal race, target and recent times, and training days) and today's date. It returns the
					plan-builder fields, which you review before a plan is built.
				</li>
				<li>
					<strong>Season planner</strong> (part of the plan assistant): the season you describe in
					your own words (races, dates, target times) and today's date. It returns a race list you
					confirm.
				</li>
				<li>
					<strong>Plan edits</strong>: the change you ask for, today's date, and the weeks of your
					active plan that are not yet over. For each week: its number, phase, dates, and planned
					distance. For each workout: its date, type, target distance or duration, and whether it is
					done, skipped, or past. Not the plan's name, notes, paces, or goal time. It returns
					proposed changes you approve before anything is saved.
				</li>
			</ul>
		</li>
		<li>
			<strong>MapTiler</strong> (EU, with global edge caching) — map tiles. Receives the map
			viewport, your IP address, and your browser details on each tile request. Signed in, maps load
			once you accept the cookie banner or tap "Load map". On a share page (a shared run or route),
			the map and the 3D course preview ask on every view: nothing loads until you tap "Load map" or
			"Load preview", whatever you chose on the cookie banner, which covers only error monitoring
			there.
		</li>
		<li>
			<strong>Open-Meteo</strong> (EU) — elevation lookup when you build or view a route. Receives
			the route's waypoint coordinates (which can include a point near your home) and your IP
			address.
		</li>
		<li>
			<strong>Open Food Facts</strong> (EU, a French non-profit) — nutrition food search. Receives
			only the search text you type (for example "rolled oats") and your IP address; no account
			identifier, no body data. Skipping search and entering macros manually avoids it entirely.
		</li>
		<li>
			<strong>Sentry</strong> — error monitoring. Receives URL paths, device and app version,
			and redacted error traces. We do not attach your account id; the mobile SDKs may tag a
			report with a random per-install identifier that is not linked to your account.
		</li>
		<li>
			<strong>RevenueCat + Stripe + Apple IAP + Google Play Billing</strong> — subscription
			billing. Receive your subscription tier and payment tokens; card numbers never reach us.
		</li>
		<li>
			<strong>Stripe Connect</strong> (marketplace — distinct from the subscription billing above)
			— paid event registration and fundraiser donations. Your email, payment, and any display
			name or message you add are sent to a Checkout Session tied to the event host's or
			fundraiser owner's <em>own</em> connected Stripe account, so that recipient — not Threkir —
			becomes a custodian of that contact data.
		</li>
		<li>
			<strong>Email delivery</strong> (Resend or AWS SES — provider selection pending) —
			transactional and digest email beyond the Supabase auth mail above. Receives your email
			address, name, and the message content (receipts, lifecycle and safety mail, the weekly
			digest).
		</li>
		<li>
			<strong>Google Sign-In</strong> — identity, only when you choose "Sign in with Google".
			Validates an ID token and returns your email and name to us. This is a separate flow from
			Google Play Billing above.
		</li>
		<li>
			<strong>Google FCM</strong> and <strong>Apple APNs</strong> — push-notification delivery,
			only when you enable notifications. Receive your device push token and the notification title
			and body.
		</li>
		<li>
			<strong>RunSignUp / ChronoTrack</strong> — race-result import, only when you import or link
			a race. We may send an optional race-platform user id and receive finisher results (names,
			bib numbers, times).
		</li>
		<li>
			<strong>Strava / Garmin Connect / Health Connect / HealthKit</strong> — only when
			you connect them. Receive OAuth tokens; return the activity data they publish to us.
		</li>
	</ul>
	<p>
		Our server-side error monitoring (Sentry) captures crash and exception reports from our
		Edge Functions. Because it runs on the server it cannot consult your in-app telemetry
		choice, so it operates on a <strong>legitimate-interest</strong> basis (Art 6(1)(f)) with
		data minimisation: it sends no default personal identifiers and strips request bodies and
		headers before transmission. On the website, client-side error monitoring stays off until
		you accept the consent banner. In the iPhone and Android apps it is on by default, on the same
		legitimate-interest basis, and you can turn it off at any time with <strong>Send error reports</strong> on the
		Privacy &amp; sharing page, in Preferences on the app's You tab. The Wear OS watch app sends crash reports with the
		same minimisation and has no separate switch.
	</p>
	<p>
		We give at least 30 days' notice before a new sub-processor goes live. The canonical
		disclosure is our maintained
		<a
			href="https://github.com/Absence0760/threkir/blob/main/docs/compliance/sub-processor-changelog.md"
			target="_blank"
			rel="noopener noreferrer">sub-processor changelog</a
		>; registered users are additionally notified by email (and, where available, in-app). You may
		object by emailing the privacy contact above, or withdraw consent and delete your account.
	</p>

	<h2>6. International transfers</h2>
	<p>
		Your core data has an EU home: <strong>Supabase</strong> — our primary database, authentication
		and file store, which holds your GPS tracks, health-related fields, and account data — is
		hosted in <strong>eu-west-2 (London)</strong>. Our background workers and live-spectator hub
		(<strong>Fly.io</strong>) also run in London, and <strong>MapTiler</strong>,
		<strong>Open-Meteo</strong>, and <strong>Open Food Facts</strong> serve from the EU (with
		global edge caching for map tiles).
	</p>
	<p>
		Several other sub-processors are based in the United States (for example AWS compute,
		Anthropic, Stripe, RevenueCat, and Sentry). For those transfers we rely on the <strong
			>EU-US Data Privacy Framework</strong
		>
		certifications where available, plus the European Commission's
		<strong>Standard Contractual Clauses</strong> (2021) for everything else. The data-processing
		agreement for each provider is held on file; email <a href="mailto:privacy@threkir.com"
			>privacy@threkir.com</a
		> to request the details for a specific sub-processor.
	</p>

	<h2>7. How long we keep it</h2>
	<ul>
		<li><strong>Account, runs, routes, gym workouts, food logs, body metrics</strong>: until you delete the item or the account.</li>
		<li><strong>How you found us</strong> (where you first arrived from when you signed up): until you delete the account.</li>
		<li><strong>Live spectator pings</strong>: 48 hours (both our database and, when enabled, the Upstash cache).</li>
		<li><strong>Race spectator pings</strong> (organised-event live results): 48 hours.</li>
		<li><strong>Checkpoint medical weigh-in fields</strong> (weight, medical hold/note): scrubbed 90 days after they were recorded; the in/out split times are race results and are kept.</li>
		<li><strong>Direct messages</strong>: 2 years from sending. Deleting your account deletes the messages you sent at once; the messages the other person sent you stay in their copy of the conversation, with your account shown as deleted, until the 2-year limit. Unsending a message removes its text, any photo in it and any reactions on it for both of you. A photo you send is re-encoded on our servers so the copy anyone sees carries no location or camera details; the photo file itself is erased by a background job shortly after its message is unsent or deleted, normally within minutes and at most within a few days, and a photo picked but never sent is deleted after a day. If the other person deletes their account, the messages they sent you are deleted with it; report a message first if you want a copy kept for moderators. "Delete conversation" hides the conversation from you and erases nothing at that moment: anyone still in the conversation keeps their copy, the messages stay in your data export, and a report's copy is untouched. Once no participant can still see a message (both of you have deleted the conversation, or the other account is gone and you have deleted it), our daily clean-up erases it.</li>
		<li><strong>Group conversations</strong>: a message you send in a group is seen by the people who are members when you send it and by anyone who joins later only from the moment they joined, never what was said before. Nobody is added to a group without accepting an invite, and an invite sees only the group's name, who invited them and how many members it has; an invite not answered in 14 days lapses. If you leave a group or are removed from it, you stop seeing other members' messages at once, your own messages stay in the group, and you can still unsend them. Deleting your account deletes every message you sent in every group. Group messages follow the same 2-year limit as direct messages, and our daily clean-up erases a group message once nobody who can see it is left, and a group once it has no members. Your data export carries the group messages you sent and your memberships, but not other members' messages: those are their data, unlike a one-to-one conversation, where the messages sent to you are also yours. Group conversations are not yet switched on.</li>
		<li><strong>Reports you file, and reports about your content</strong>: kept while a moderator reviews them, then deleted 6 months after the report is closed with no action, or 12 months after action was taken. A report we need for a legal claim, or that a court or authority has asked us to preserve, is kept until that need ends. A reported direct message is copied into the report when it is filed, together with any photo it carried, so the copy survives the message being unsent, the sender deleting their account, and the 2-year limit on messages. If you delete your account, reports you filed are kept for the same period with your name removed, so the evidence is not lost.</li>
		<li><strong>The email address on a park course report</strong>: deleted 30 days after the report is resolved, or at once if you filed it signed in and then delete your account. The report itself follows the rule above. If you filed one without an account and want it removed sooner, email us from that address.</li>
		<li><strong>Coach chat history</strong>: 18 months from the message timestamp.</li>
		<li><strong>AI-provider copies of coach prompts and AI-assistant requests</strong>: deleted by the provider within 30 days of processing (Anthropic API default retention); never used for model training.</li>
		<li><strong>Coach usage counters</strong> (per-day message counts): 7 days.</li>
		<li><strong>Notifications</strong>: 90 days from creation.</li>
		<li><strong>Push tokens (FCM / APNs)</strong>: 60 days of inactivity.</li>
		<li><strong>Payout account link (event hosts / fundraiser owners)</strong>: until account deletion, at which point we also close the connected Stripe account (Stripe retains transaction records under its own legal obligations).</li>
		<li><strong>Background-job records</strong>: 30 days after completion.</li>
		<li><strong>Rate-limit counters</strong>: 24 hours from the window start.</li>
		<li><strong>Sentry events</strong>: 90 days (Sentry's default).</li>
		<li><strong>AWS Lambda CloudWatch logs</strong>: 30 days (CloudFront access logging is not collected).</li>
		<li><strong>Backups</strong>: a deleted account may persist in encrypted point-in-time-recovery backups for up to 28 days before they roll off.</li>
	</ul>
	<p>
		The categories above are our retention schedule. Where a period is not listed, we keep the
		data only as long as needed for the purpose it was collected, then delete or anonymise it.
	</p>

	<h2>8. Your rights</h2>
	<p>Under the GDPR / UK GDPR / CCPA / LGPD you have the right to:</p>
	<ul>
		<li><strong>Access</strong> your personal data (Art 15) — ask for a full account archive: <strong>Download full account archive</strong> under Data Export on the Account page on the web (Settings → Account), or <strong>Account export</strong> on the Account page in the app's You tab. We build it on our servers from everything on your account, health data included, and keep it for you to download for 7 days.</li>
		<li><strong>Rectify</strong> inaccurate data (Art 16) — edit your profile on the Account page (Settings → Account on the web, Account in the app's You tab).</li>
		<li><strong>Erase</strong> your data (Art 17) — use Settings → Account → Delete account on the web, or Account → Delete account in the app's You tab. Deletion cascades through our database, drains your uploaded files from storage, and disconnects or deletes linked third-party resources (for example Strava authorisation and any connected Stripe account). Step-by-step instructions, including what to do if you can no longer sign in, are on the <a href="/delete-account">Delete your account</a> page.</li>
		<li><strong>Restrict</strong> or <strong>object to</strong> processing (Arts 18 + 21) — email <a href="mailto:privacy@threkir.com">privacy@threkir.com</a>. There is no self-service toggle yet; we action these manually and confirm within one month.</li>
		<li><strong>Portability</strong> (Art 20) — the same full account archive is a zip of machine-readable JSON files, one for each kind of data, with each activity's GPS track and heart-rate series as compressed JSON and your run photos as image files. On the web, <strong>Cloud export (GPX zip)</strong> under Data Export also gives you one GPX file per activity, for importing into other apps. The other export and backup buttons give narrower copies (runs only, or what is on your device).</li>
		<li><strong>Withdraw consent</strong> at any time without affecting the lawfulness of prior processing. Both consents are withdrawable self-service.
			<strong>AI features</strong>: <strong>Withdraw consent</strong> on the Account page (Settings → Account on the web, Account in the app's You tab); the AI Coach and the other AI features stop at once and stay off until you consent again.
			<strong>Health data</strong>: clear the health-data consent and save. On the web, untick the consent box under Settings → Body metrics (or the health-data box on the Account page) and press Save. In the app, open Body metrics under Profile in the You tab, turn off the switch at the top of the screen (in English it reads "Store health data"; it is the switch that says height and weight are health data), and tap Save. Every path then asks you to confirm, because withdrawing permanently erases your stored height, gender, weight history and any cycle or pregnancy details, removes heart-rate targets from your own training plans, and stops us using your date of birth for training and health calculations. Your date of birth itself stays on your account as an age record, because it also keeps under-18 members out of people search. Giving consent again later does not bring the erased data back.</li>
		<li><strong>Object to direct marketing</strong> at any time (Art 21(2)). Our marketing emails are the weekly digest and the tips and encouragement emails. Both are off unless you turn them on, each email carries a one-click unsubscribe link, and you can turn either off under Optional emails on the Notifications page (Settings → Notifications on the web, Notifications in Preferences on the app's You tab). Transactional mail (receipts, security notices) is not marketing.</li>
		<li><strong>Lodge a complaint</strong> with your local supervisory authority. UK residents may contact the <a href="https://ico.org.uk/" target="_blank" rel="noopener noreferrer">ICO</a>; EU residents the DPA of their member state; Brazilian residents the ANPD; Canadian residents the OPC (Quebec: the CAI); Australian residents the OAIC.</li>
	</ul>
	<p>
		For the purposes of Canadian law (including Quebec's Law 25), the privacy contact above is
		our designated person in charge of the protection of personal information.
	</p>
	<p>
		When you exercise a right by email, we verify the request by matching (or confirming a link
		sent to) the email address on the account. An authorised agent may act for you where local law
		provides for it, subject to the same verification.
	</p>
	<p>
		<strong>For California residents (CCPA/CPRA):</strong> we do not sell your personal
		information, and we do not share it for cross-context behavioural advertising. We honour the
		<strong>Global Privacy Control</strong> signal: a browser sending GPC is treated as a binding
		opt-out and the consent-gated services never load. The rights to know, delete, and correct are
		served by the same self-service tools listed above, and we will never discriminate against you
		for exercising them.
	</p>

	<h2>9. Children</h2>
	<p>
		Threkir requires all users to confirm they are <strong>16 or older</strong> at signup — the
		most conservative age-of-consent threshold across EU member states (GDPR Art 8) — and is not
		directed to anyone under that age (which includes children under 13 for US COPPA purposes). We
		do not knowingly collect personal data from anyone under 16. If you believe someone under 16
		has provided personal data to us, please email
		<a href="mailto:privacy@threkir.com">privacy@threkir.com</a> and we will delete the account.
	</p>

	<h2>10. Related notices</h2>
	<p>
		Cookies and similar technologies are covered in the dedicated
		<a href="/cookie-notice">Cookie Notice</a>. Washington residents (and residents of other US
		states with consumer-health-data laws) have a dedicated
		<a href="/health-data-notice">Consumer Health Data Privacy Policy</a>.
	</p>

	<h2>11. Security + breach notification</h2>
	<p>
		We use TLS in transit, AWS KMS for at-rest secrets, Postgres Row-Level Security to gate
		every database read, and signed-URL controls on storage. If a personal-data breach occurs
		that risks your rights, we will notify the competent supervisory authority within 72 hours
		(Art 33 GDPR) and, where the risk is high, notify you directly (Art 34).
	</p>
	<p>
		If you discover a vulnerability, please email <a href="mailto:security@threkir.com">security@threkir.com</a>.
	</p>

	<h2>12. Changes</h2>
	<p>
		We will update this policy from time to time. Material changes will be announced via in-app
		notice and email at least 30 days before they take effect.
	</p>

	<h2>13. Contact</h2>
	<p>
		Privacy: <a href="mailto:privacy@threkir.com">privacy@threkir.com</a>
		<br />Security: <a href="mailto:security@threkir.com">security@threkir.com</a>
		<br />Postal: {#if OPERATOR.postalAddress === NOT_PROVIDED}not published — use the privacy
			email above{:else if OPERATOR.postalAddress}{OPERATOR.postalAddress}{:else}<em>pending
			publication — use the privacy email above in the meantime</em>{/if}
	</p>
</div>

<style>
	.legal-page {
		max-width: 48rem;
		margin: 0 auto;
		padding: var(--page-padding-y) var(--page-padding-x);
		line-height: 1.6;
	}
	.pending-banner {
		background: var(--color-surface);
		color: var(--color-text-secondary);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		padding: var(--space-md) var(--space-lg);
		margin-bottom: var(--space-2xl);
		font-size: 0.9375rem;
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
	table {
		width: 100%;
		border-collapse: collapse;
		margin: var(--space-md) 0;
	}
	th,
	td {
		text-align: start;
		padding: var(--space-xs) var(--space-sm);
		border-bottom: 1px solid var(--color-border);
		vertical-align: top;
	}
	th {
		background: var(--color-surface);
		font-weight: 600;
	}
</style>
