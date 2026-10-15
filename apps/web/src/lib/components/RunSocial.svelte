<script lang="ts">
	import { thrownMessage } from '#lib/core/supabase_error.ts';
	import { onMount } from 'svelte';
	import Avatar from '#lib/components/Avatar.svelte';
	import { formatRelativeTime } from '#lib/format/time.ts';
	import { currentLocale, m as t } from '#lib/i18n/store.svelte.ts';
	import type { MessageKey } from '#lib/i18n/messages.ts';
	import {
		fetchKudosForRunWithError,
		giveKudos,
		rescindKudos,
		fetchRunCommentsWithError,
		postRunComment,
		deleteRunComment,
		fetchRunReactionSummary,
		addRunReaction,
		removeRunReaction,
		fetchRunCommentLikeSummary,
		likeRunComment,
		unlikeRunComment,
		resolveMentionHandles,
		searchPeople,
		type RunKudosSummary,
		type RunCommentWithAuthor,
		type CommentLikeSummary,
		type PeopleSuggestion,
	} from '#lib/core/data.ts';
	import {
		REACTION_ICONS,
		reactionTallies,
		applyReactionToggle,
		type ReactionKey,
		type ReactionTally,
	} from '#lib/social/reactions.ts';
	import {
		splitMentions,
		parseMentionHandles,
		activeMentionQuery,
		insertMention,
	} from '#lib/social/mentions.ts';
	import { auth } from '#lib/stores/auth.svelte.ts';
	import { showToast } from '#lib/stores/toast.svelte.ts';
	import { deferDestructive } from '#lib/stores/undo.svelte.ts';
	import ReportDialog from '#lib/components/ReportDialog.svelte';

	interface Props {
		runId: string;
		runOwnerId: string;
	}
	let { runId, runOwnerId }: Props = $props();

	let reportCommentId = $state<string | null>(null);

	let kudos = $state<RunKudosSummary>({ count: 0, viewer_has_kudos: false });
	let comments = $state<RunCommentWithAuthor[]>([]);
	let loading = $state(true);
	let loadError = $state<string | null>(null);
	let kudosBusy = $state(false);
	let draftBody = $state('');
	let posting = $state(false);
	let replyTo = $state<string | null>(null);
	let replyBody = $state('');
	let reactions = $state<ReactionTally[]>(reactionTallies([]));
	let reactionBusy = $state<ReactionKey | null>(null);
	let likes = $state<Map<string, CommentLikeSummary>>(new Map());
	let likeBusy = $state<string | null>(null);
	let mentionIds = $state<Map<string, string>>(new Map());

	// The @mention picker. One at a time: `field` names the input it serves.
	let mentionField = $state<'comment' | 'reply' | null>(null);
	let mentionStart = $state(0);
	let mentionCaret = $state(0);
	let mentionPeople = $state<PeopleSuggestion[]>([]);
	let mentionSeq = 0;

	let isOwn = $derived(auth.user?.id === runOwnerId);

	async function load() {
		loading = true;
		loadError = null;
		try {
			const [k, c] = await Promise.all([
				fetchKudosForRunWithError(runId),
				fetchRunCommentsWithError(runId),
			]);
			if (k.error || c.error) {
				loadError = k.error ?? c.error;
				return;
			}
			kudos = k.kudos;
			comments = c.comments;
			await loadExtras(c.comments);
		} catch (e) {
			loadError = thrownMessage(e);
		} finally {
			loading = false;
		}
	}

	// Reactions, comment likes and mention links are an L4 layer over kudos and
	// comments: a failure here is logged and leaves them empty, never the
	// load-failed banner that withholds the comments themselves.
	async function loadExtras(list: RunCommentWithAuthor[]) {
		const [r, l, ids] = await Promise.all([
			fetchRunReactionSummary(runId),
			fetchRunCommentLikeSummary(runId),
			resolveMentionHandles(list.flatMap((c) => parseMentionHandles(c.body))),
		]);
		if (r.error) console.error('run reactions failed', r.error);
		else reactions = reactionTallies(r.rows);
		if (l.error) console.error('comment likes failed', l.error);
		else likes = l.likes;
		mentionIds = ids;
	}

	onMount(load);

	const REACTION_LABEL_KEYS: Record<ReactionKey, MessageKey> = {
		fire: 'runSocial.reactionFire',
		strong: 'runSocial.reactionStrong',
		trophy: 'runSocial.reactionTrophy',
		thumbs_up: 'runSocial.reactionThumbsUp',
		wave: 'runSocial.reactionWave',
	};

	function reactionLabel(key: ReactionKey): string {
		return t(REACTION_LABEL_KEYS[key]);
	}

	async function toggleReaction(key: ReactionKey) {
		if (!auth.loggedIn || isOwn || reactionBusy) return;
		const tally = reactions.find((r) => r.key === key);
		if (!tally) return;
		reactionBusy = key;
		try {
			const nowReacted = !tally.viewerReacted;
			const changed = nowReacted
				? await addRunReaction(runId, key)
				: await removeRunReaction(runId, key);
			reactions = applyReactionToggle(reactions, key, nowReacted, changed);
		} catch (e) {
			showToast(t('runSocial.reactionUpdateFailed', { error: thrownMessage(e) }), 'error');
		} finally {
			reactionBusy = null;
		}
	}

	async function toggleLike(comment: RunCommentWithAuthor) {
		if (!auth.loggedIn || auth.user?.id === comment.author_id || likeBusy) return;
		const before = likes.get(comment.id) ?? { count: 0, viewer_liked: false };
		likeBusy = comment.id;
		try {
			const nowLiked = !before.viewer_liked;
			const changed = nowLiked
				? await likeRunComment(comment.id)
				: await unlikeRunComment(comment.id);
			const next = new Map(likes);
			next.set(comment.id, {
				count: Math.max(0, before.count + (changed ? (nowLiked ? 1 : -1) : 0)),
				viewer_liked: nowLiked,
			});
			likes = next;
		} catch (e) {
			showToast(t('runSocial.likeUpdateFailed', { error: thrownMessage(e) }), 'error');
		} finally {
			likeBusy = null;
		}
	}

	function closeMentions() {
		mentionField = null;
		mentionPeople = [];
	}

	async function onMentionInput(field: 'comment' | 'reply', el: HTMLInputElement | HTMLTextAreaElement) {
		const caret = el.selectionStart ?? el.value.length;
		const q = activeMentionQuery(el.value, caret);
		if (!q || q.query.length < 1) {
			closeMentions();
			return;
		}
		const seq = ++mentionSeq;
		mentionField = field;
		mentionStart = q.start;
		mentionCaret = caret;
		// § 269's search: the opt-out, minor and block filters all apply, so the
		// picker never offers someone People search would not.
		const found = await searchPeople(`@${q.query}`, 8);
		if (seq !== mentionSeq) return;
		mentionPeople = found.filter((p) => p.handle);
	}

	function pickMention(person: PeopleSuggestion) {
		if (!person.handle || mentionField === null) return;
		const source = mentionField === 'comment' ? draftBody : replyBody;
		const next = insertMention(source, mentionStart, mentionCaret, person.handle);
		if (mentionField === 'comment') draftBody = next.text;
		else replyBody = next.text;
		closeMentions();
	}

	function onMentionKeydown(e: KeyboardEvent) {
		if (e.key === 'Escape' && mentionField !== null) {
			e.stopPropagation();
			closeMentions();
		}
	}

	async function toggleKudos() {
		if (!auth.loggedIn || isOwn) return;
		kudosBusy = true;
		try {
			if (kudos.viewer_has_kudos) {
				const removed = await rescindKudos(runId);
				kudos = {
					count: removed ? Math.max(kudos.count - 1, 0) : kudos.count,
					viewer_has_kudos: false,
				};
			} else {
				const added = await giveKudos(runId);
				kudos = {
					count: added ? kudos.count + 1 : kudos.count,
					viewer_has_kudos: true,
				};
			}
		} catch (e) {
			showToast(t('runSocial.kudosUpdateFailed', { error: thrownMessage(e) }), 'error');
		} finally {
			kudosBusy = false;
		}
	}

	async function submitComment() {
		const body = draftBody.trim();
		if (!body || !auth.loggedIn) return;
		posting = true;
		try {
			await postRunComment({ run_id: runId, body });
			draftBody = '';
			closeMentions();
			await load();
		} catch (e) {
			showToast(t('runSocial.commentPostFailed', { error: thrownMessage(e) }), 'error');
		} finally {
			posting = false;
		}
	}

	async function submitReply(parentId: string) {
		const body = replyBody.trim();
		if (!body || !auth.loggedIn) return;
		posting = true;
		try {
			await postRunComment({ run_id: runId, body, parent_comment_id: parentId });
			replyBody = '';
			replyTo = null;
			closeMentions();
			await load();
		} catch (e) {
			showToast(t('runSocial.replyPostFailed', { error: thrownMessage(e) }), 'error');
		} finally {
			posting = false;
		}
	}

	// Undo rather than a confirm, on both the author's own delete and the
	// run owner's moderation delete: with the mutation deferred the actor
	// can put the comment back untouched, which is more than the modal
	// offered once it was dismissed. The single behaviour is deliberate —
	// a button that asks on some rows and not others reads as a bug.
	function removeComment(comment: RunCommentWithAuthor) {
		const before = comments;
		// Drop the replies too: `parent_comment_id` cascades, so leaving them
		// on screen would render children of a comment that is on its way out.
		comments = comments.filter(
			(c) => c.id !== comment.id && c.parent_comment_id !== comment.id,
		);
		deferDestructive({
			message: t('runSocial.commentRemoved'),
			commit: () => deleteRunComment(comment.id),
			restore: () => {
				comments = before;
			},
			onCommitError: (e) =>
				showToast(
					t('runSocial.deleteFailed', { error: thrownMessage(e) }),
					'error',
				),
		});
	}



	let topLevel = $derived(comments.filter((c) => c.parent_comment_id == null));
	let repliesByParent = $derived.by(() => {
		const m = new Map<string, RunCommentWithAuthor[]>();
		for (const c of comments) {
			if (c.parent_comment_id) {
				const list = m.get(c.parent_comment_id) ?? [];
				list.push(c);
				m.set(c.parent_comment_id, list);
			}
		}
		return m;
	});
</script>

<div class="run-social">
	<div class="kudos-row">
		<button
			class="kudos-btn"
			class:given={kudos.viewer_has_kudos}
			disabled={!auth.loggedIn || isOwn || kudosBusy}
			type="button"
			onclick={toggleKudos}
			title={!auth.loggedIn
				? t('runSocial.signInToGiveKudos')
				: isOwn
					? t('runSocial.cannotKudosOwnRun')
					: kudos.viewer_has_kudos
						? t('runSocial.rescindKudos')
						: t('runSocial.giveKudos')}
		>
			<span class="material-symbols">
				{kudos.viewer_has_kudos ? 'favorite' : 'favorite_border'}
			</span>
			<span class="kudos-count">{kudos.count}</span>
			<span class="kudos-label">{t('runSocial.kudosLabel')}</span>
		</button>
		<span class="comment-count">
			<span class="material-symbols">chat_bubble_outline</span>
			{comments.length === 1 ? t('runSocial.commentCountOne', { n: comments.length }) : t('runSocial.commentCountMany', { n: comments.length })}
		</span>
	</div>

	<div class="reactions" role="group" aria-label={t('runSocial.reactionsLabel')} data-testid="run-reactions">
		{#each reactions as r (r.key)}
			<button
				class="reaction-btn"
				class:given={r.viewerReacted}
				type="button"
				data-reaction={r.key}
				aria-pressed={r.viewerReacted}
				disabled={!auth.loggedIn || isOwn || reactionBusy !== null}
				aria-label={r.viewerReacted
					? t('runSocial.removeReaction', { label: reactionLabel(r.key) })
					: t('runSocial.reactWith', { label: reactionLabel(r.key) })}
				title={!auth.loggedIn
					? t('runSocial.signInToReact')
					: isOwn
						? t('runSocial.cannotReactOwnRun')
						: reactionLabel(r.key)}
				onclick={() => toggleReaction(r.key)}
			>
				<span class="material-symbols" aria-hidden="true">{REACTION_ICONS[r.key]}</span>
				{#if r.count > 0}<span class="reaction-count">{r.count}</span>{/if}
			</button>
		{/each}
	</div>

	{#if !loading}
		{#if loadError !== null}
			<div class="error-banner" role="alert">
				<span class="material-symbols" aria-hidden="true">error</span>
				<div>
					<strong>{t('runs.loadFailed')}</strong>
					{#if loadError}<span class="error-detail">{loadError}</span>{/if}
				</div>
				<button class="btn btn-outline btn-sm" onclick={load}>{t('runs.retry')}</button>
			</div>
		{:else}
		<div class="comments">
			{#each topLevel as comment (comment.id)}
				<article class="comment">
					<!-- Redundant image link for the same destination as the author-name
					     link below (WCAG technique H2). Avatar renders alt="" so this
					     anchor has no accessible name of its own; tabindex="-1" keeps it
					     out of the tab order, which is what makes aria-hidden legitimate
					     rather than a focusable-but-invisible node. -->
					<a href="/u/{comment.author_id}" class="comment-author" tabindex="-1" aria-hidden="true">
						<Avatar
							url={comment.author.avatar_url}
							name={comment.author.display_name}
							size="2rem"
							font="0.85rem"
						/>
					</a>
					<div class="comment-body">
						<div class="comment-head">
							<a href="/u/{comment.author_id}" class="comment-author-link">
								<strong>{comment.author.display_name ?? t('runSocial.runnerFallback')}</strong>
							</a>
							<span class="when">{formatRelativeTime(comment.created_at, undefined, currentLocale())}</span>
							{#if auth.loggedIn && auth.user?.id !== comment.author_id}
								<button
									class="icon-btn report-btn"
									type="button"
									aria-label={t('runSocial.reportComment')}
									title={t('runSocial.reportComment')}
									onclick={() => (reportCommentId = comment.id)}
								>
									<span class="material-symbols">flag</span>
								</button>
							{/if}
							{#if auth.user?.id === comment.author_id || isOwn}
								<button
									class="icon-btn"
									type="button"
									aria-label={t('runSocial.deleteComment')}
									onclick={() => removeComment(comment)}
								>
									<span class="material-symbols">close</span>
								</button>
							{/if}
						</div>
						<p>{@render body(comment.body)}</p>
						{@render likeButton(comment)}
						{#if auth.loggedIn}
							<button class="link-btn" type="button" onclick={() => (replyTo = replyTo === comment.id ? null : comment.id)}>
								{t('runSocial.reply')}
							</button>
						{/if}

						{#if (repliesByParent.get(comment.id)?.length ?? 0) > 0}
							<div class="replies">
								{#each repliesByParent.get(comment.id) ?? [] as reply (reply.id)}
									<div class="reply">
										<a
											href="/u/{reply.author_id}"
											class="reply-author"
											tabindex="-1"
											aria-hidden="true"
										>
											<Avatar
												url={reply.author.avatar_url}
												name={reply.author.display_name}
												size="2rem"
												font="0.85rem"
											/>
										</a>
										<div class="reply-body">
											<div class="comment-head">
												<a href="/u/{reply.author_id}" class="comment-author-link">
													<strong>{reply.author.display_name ?? t('runSocial.runnerFallback')}</strong>
												</a>
												<span class="when">{formatRelativeTime(reply.created_at, undefined, currentLocale())}</span>
												{#if auth.loggedIn && auth.user?.id !== reply.author_id}
													<button
														class="icon-btn report-btn"
														type="button"
														aria-label={t('runSocial.reportReply')}
														title={t('runSocial.reportReply')}
														onclick={() => (reportCommentId = reply.id)}
													>
														<span class="material-symbols">flag</span>
													</button>
												{/if}
												{#if auth.user?.id === reply.author_id || isOwn}
													<button
														class="icon-btn"
														type="button"
														aria-label={t('runSocial.deleteReply')}
														onclick={() => removeComment(reply)}
													>
														<span class="material-symbols">close</span>
													</button>
												{/if}
											</div>
											<p>{@render body(reply.body)}</p>
											{@render likeButton(reply)}
										</div>
									</div>
								{/each}
							</div>
						{/if}

						{#if replyTo === comment.id}
							<form class="reply-form" onsubmit={(e) => { e.preventDefault(); submitReply(comment.id); }}>
								<div class="mention-anchor">
									<input
										type="text"
										placeholder={t('runSocial.writeReplyPlaceholder')}
										aria-label={t('runSocial.writeReplyAriaLabel')}
										bind:value={replyBody}
										maxlength="2000"
										oninput={(e) => onMentionInput('reply', e.currentTarget)}
										onkeydown={onMentionKeydown}
									/>
									{#if mentionField === 'reply'}{@render mentionList()}{/if}
								</div>
								<button class="btn btn-primary btn-sm" type="submit" disabled={!replyBody.trim() || posting}>
									{posting ? t('runSocial.posting') : t('runSocial.reply')}
								</button>
							</form>
						{/if}
					</div>
				</article>
			{/each}
		</div>
		{/if}

		{#if auth.loggedIn}
			<form class="composer" onsubmit={(e) => { e.preventDefault(); submitComment(); }}>
				<div class="mention-anchor">
					<textarea
						bind:value={draftBody}
						placeholder={t('runSocial.addCommentPlaceholder')}
						rows="2"
						maxlength="2000"
						oninput={(e) => onMentionInput('comment', e.currentTarget)}
						onkeydown={onMentionKeydown}
					></textarea>
					{#if mentionField === 'comment'}{@render mentionList()}{/if}
				</div>
				<button class="btn btn-primary" type="submit" disabled={!draftBody.trim() || posting}>
					{posting ? t('runSocial.posting') : t('runSocial.post')}
				</button>
			</form>
		{:else}
			<p class="muted">
				<a href="/login">{t('runSocial.signIn')}</a>{t('runSocial.signInToEngageSuffix')}
			</p>
		{/if}
	{/if}
</div>

{#snippet body(text: string)}{#each splitMentions(text) as seg, i (i)}{#if seg.kind === 'mention' && mentionIds.has(seg.handle)}<a class="mention" href="/u/{mentionIds.get(seg.handle)}">{seg.text}</a>{:else}{seg.text}{/if}{/each}{/snippet}

{#snippet likeButton(c: RunCommentWithAuthor)}
	{@const like = likes.get(c.id) ?? { count: 0, viewer_liked: false }}
	{@const own = auth.user?.id === c.author_id}
	<button
		class="like-btn"
		class:given={like.viewer_liked}
		type="button"
		data-testid="comment-like"
		aria-pressed={like.viewer_liked}
		disabled={!auth.loggedIn || own || likeBusy !== null}
		aria-label={like.viewer_liked ? t('runSocial.unlikeComment') : t('runSocial.likeComment')}
		title={own ? t('runSocial.cannotLikeOwnComment') : undefined}
		onclick={() => toggleLike(c)}
	>
		<span class="material-symbols" aria-hidden="true">{like.viewer_liked ? 'favorite' : 'favorite_border'}</span>
		{#if like.count > 0}<span class="like-count">{like.count}</span>{/if}
	</button>
{/snippet}

{#snippet mentionList()}
	{#if mentionPeople.length > 0}
		<div class="mention-list" role="group" aria-label={t('runSocial.mentionSuggestions')} data-testid="mention-suggestions">
			{#each mentionPeople as person (person.id)}
				<button type="button" onmousedown={(e) => e.preventDefault()} onclick={() => pickMention(person)}>
					<Avatar url={person.avatar_url} name={person.display_name} size="1.5rem" font="0.7rem" />
					<span class="mention-name">{person.display_name ?? t('runSocial.runnerFallback')}</span>
					<span class="mention-handle">@{person.handle}</span>
				</button>
			{/each}
		</div>
	{/if}
{/snippet}

<ReportDialog
	open={reportCommentId !== null}
	targetKind="comment"
	targetId={reportCommentId ?? ''}
	onclose={() => (reportCommentId = null)}
/>

<style>
	.run-social {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}

	.kudos-row {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		padding-bottom: var(--space-sm);
		border-bottom: 1px solid var(--color-border);
	}

	.kudos-btn {
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
		padding: 0.45rem 0.85rem;
		border: 1.5px solid var(--color-border);
		border-radius: 9999px;
		background: var(--color-surface);
		color: var(--color-text-secondary);
		cursor: pointer;
		font-size: 0.9rem;
		font-weight: 600;
		transition: color var(--transition-fast),
			border-color var(--transition-fast),
			background var(--transition-fast);
	}

	.kudos-btn:disabled {
		cursor: not-allowed;
		opacity: 0.6;
	}

	.kudos-btn:not(:disabled):hover {
		border-color: var(--color-primary);
		color: var(--color-primary);
	}

	.kudos-btn.given {
		background: color-mix(in srgb, var(--color-primary) 12%, transparent);
		border-color: var(--color-primary);
		color: var(--color-primary);
	}

	.kudos-count {
		font-variant-numeric: tabular-nums;
	}

	.reactions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-xs);
	}

	.reaction-btn,
	.like-btn {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		gap: 0.25rem;
		min-width: var(--tap-target-min);
		min-height: var(--tap-target-min);
		padding: 0 0.6rem;
		border: 1px solid var(--color-border);
		border-radius: 9999px;
		background: var(--color-surface);
		color: var(--color-text-secondary);
		cursor: pointer;
		font-size: 0.85rem;
		font-variant-numeric: tabular-nums;
	}

	.like-btn {
		border-color: transparent;
		padding: 0 0.35rem;
		margin-inline-end: 0.25rem;
	}

	.reaction-btn .material-symbols,
	.like-btn .material-symbols {
		font-size: 1.1rem;
	}

	.reaction-btn:disabled,
	.like-btn:disabled {
		cursor: not-allowed;
		opacity: 0.6;
	}

	.reaction-btn.given,
	.like-btn.given {
		background: color-mix(in srgb, var(--color-primary) 12%, transparent);
		border-color: var(--color-primary);
		color: var(--color-primary);
	}

	.mention {
		color: var(--color-primary);
		font-weight: 600;
		text-decoration: none;
	}

	.mention:hover {
		text-decoration: underline;
	}

	.mention-anchor {
		position: relative;
		display: flex;
		flex-direction: column;
		flex: 1;
	}

	.mention-list {
		position: absolute;
		inset-inline-start: 0;
		top: 100%;
		z-index: 10;
		min-width: min(18rem, 100%);
		max-width: 100%;
		margin-top: 0.25rem;
		padding: 0.25rem;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		box-shadow: var(--shadow-md);
	}

	.mention-list button {
		display: flex;
		align-items: center;
		gap: 0.5rem;
		width: 100%;
		min-height: var(--tap-target-min);
		padding: 0.25rem 0.5rem;
		border: none;
		background: none;
		color: var(--color-text);
		text-align: start;
		cursor: pointer;
		border-radius: var(--radius-sm);
	}

	.mention-list button:hover,
	.mention-list button:focus-visible {
		background: color-mix(in srgb, var(--color-primary) 10%, transparent);
	}

	.mention-name {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.mention-handle {
		color: var(--color-text-tertiary);
		font-size: 0.8rem;
	}

	.kudos-label,
	.comment-count {
		color: var(--color-text-secondary);
		font-size: 0.85rem;
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
	}

	.comment-count .material-symbols {
		font-size: 1rem;
	}

	.comments {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}

	.comment {
		display: flex;
		gap: var(--space-sm);
	}

	.comment-author,
	.reply-author {
		flex-shrink: 0;
		text-decoration: none;
	}



	.comment-body,
	.reply-body {
		flex: 1;
		min-width: 0;
	}

	.comment-author-link {
		text-decoration: none;
		color: inherit;
		min-width: 0;
	}
	.comment-author-link strong {
		display: block;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.comment-author-link:hover strong {
		color: var(--color-primary);
	}

	.comment-head {
		display: flex;
		align-items: center;
		gap: 0.5rem;
		margin-bottom: 0.2rem;
		min-width: 0;
	}

	.when {
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
	}

	.icon-btn {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		min-width: var(--tap-target-min);
		min-height: var(--tap-target-min);
		background: none;
		border: none;
		color: var(--color-text-tertiary);
		cursor: pointer;
		padding: 0.15rem;
		border-radius: var(--radius-sm);
	}

	.comment-head .icon-btn:first-of-type {
		margin-inline-start: auto;
	}

	.icon-btn:hover {
		color: var(--color-danger-text);
	}

	.comment-body p,
	.reply-body p {
		margin: 0;
		white-space: pre-wrap;
		word-break: break-word;
	}

	.link-btn {
		background: none;
		border: none;
		padding: 0.25rem 0;
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		cursor: pointer;
	}

	.link-btn:hover {
		color: var(--color-primary);
	}

	.replies {
		margin-top: var(--space-sm);
		padding-inline-start: var(--space-md);
		border-inline-start: 2px solid var(--color-border);
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}

	.reply {
		display: flex;
		gap: var(--space-sm);
	}

	.reply-form {
		display: flex;
		gap: var(--space-sm);
		margin-top: var(--space-sm);
	}

	.reply-form input {
		flex: 1;
		padding: 0.4rem 0.65rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		font-size: 0.9rem;
	}

	.composer {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}

	.composer textarea {
		padding: var(--space-sm) var(--space-md);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		font-family: inherit;
		font-size: 0.95rem;
		resize: vertical;
	}

	.composer button {
		align-self: flex-end;
	}

	.muted {
		color: var(--color-text-tertiary);
		font-size: 0.9rem;
	}

	.muted a {
		color: var(--color-primary);
	}

	.error-banner {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-sm) var(--space-md);
		background: rgba(239, 68, 68, 0.08);
		border: 1px solid rgba(239, 68, 68, 0.3);
		border-radius: var(--radius-md);
		color: var(--color-text);
	}
	.error-banner > div {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
	}
	.error-detail {
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
	}
	.error-banner .material-symbols {
		color: var(--color-danger-text);
		font-size: 1.3rem;
	}
</style>
