import { tick } from 'svelte';

/// The ARIA menu-button contract every hand-rolled menu on the web shares:
/// ArrowDown / ArrowUp on the trigger open it on the first / last item,
/// arrow keys cycle, Home / End jump, Escape closes back to the trigger, Tab
/// or Shift+Tab out closes it where focus went, a click outside closes it,
/// and a click on the trigger while it is open closes it.
///
/// The owner binds `trigger` and `panel`, wires the handlers below, and
/// calls `listen()` from `onMount` for the document-level Escape and
/// outside-click.
export class MenuButton {
	open = $state(false);
	trigger = $state<HTMLElement | null>(null);
	panel = $state<HTMLElement | null>(null);

	items(): HTMLElement[] {
		return this.panel
			? Array.from(this.panel.querySelectorAll<HTMLElement>('[role="menuitem"]'))
			: [];
	}

	focusItem(i: number) {
		const all = this.items();
		if (all.length === 0) return;
		all[(i + all.length) % all.length]?.focus();
	}

	toggle = async (focusLast = false) => {
		if (this.open) {
			this.open = false;
			this.trigger?.focus();
			return;
		}
		this.open = true;
		await tick();
		this.focusItem(focusLast ? -1 : 0);
	};

	/// Pressing the trigger would otherwise move focus out of the open panel
	/// first, and the focusout close followed by the click's toggle reopens
	/// it. Keeping focus where it is leaves the close to the click.
	onTriggerMousedown = (e: MouseEvent) => {
		if (this.open) e.preventDefault();
	};

	onTriggerKeydown = (e: KeyboardEvent) => {
		if (!this.open && (e.key === 'ArrowDown' || e.key === 'ArrowUp')) {
			e.preventDefault();
			void this.toggle(e.key === 'ArrowUp');
		}
	};

	onPanelKeydown = (e: KeyboardEvent) => {
		const all = this.items();
		if (all.length === 0) return;
		const cur = all.indexOf(document.activeElement as HTMLElement);
		if (e.key === 'ArrowDown') {
			e.preventDefault();
			this.focusItem(cur + 1);
		} else if (e.key === 'ArrowUp') {
			e.preventDefault();
			this.focusItem(cur - 1);
		} else if (e.key === 'Home') {
			e.preventDefault();
			this.focusItem(0);
		} else if (e.key === 'End') {
			e.preventDefault();
			this.focusItem(all.length - 1);
		}
	};

	/// A menu left open behind the focus covers the page it moved to. A null
	/// relatedTarget is the window losing focus, not the runner leaving.
	onPanelFocusout = (e: FocusEvent) => {
		const next = e.relatedTarget as Node | null;
		if (next && !this.panel?.contains(next)) this.open = false;
	};

	listen(): () => void {
		const onDocMousedown = (e: MouseEvent) => {
			if (!this.open) return;
			const target = e.target as Node | null;
			if (this.panel?.contains(target) || this.trigger?.contains(target)) return;
			this.open = false;
		};
		const onDocKeydown = (e: KeyboardEvent) => {
			if (this.open && e.key === 'Escape') {
				this.open = false;
				this.trigger?.focus();
			}
		};
		document.addEventListener('mousedown', onDocMousedown);
		document.addEventListener('keydown', onDocKeydown);
		return () => {
			document.removeEventListener('mousedown', onDocMousedown);
			document.removeEventListener('keydown', onDocKeydown);
		};
	}
}
