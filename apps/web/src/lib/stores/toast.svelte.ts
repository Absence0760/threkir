/// A link that takes the reader to where the toast's news can be acted on
/// ("Show it again" after hiding a card), instead of prose naming a place.
export interface ToastAction {
	label: string;
	href: string;
}

interface Toast {
	id: number;
	message: string;
	type: 'info' | 'error' | 'success';
	action?: ToastAction;
}

let toasts = $state<Toast[]>([]);
let nextId = 0;

export function showToast(
	message: string,
	type: 'info' | 'error' | 'success' = 'info',
	durationMs = 4000,
	action?: ToastAction,
) {
	const id = nextId++;
	toasts = [...toasts, { id, message, type, action }];
	setTimeout(() => {
		toasts = toasts.filter((t) => t.id !== id);
	}, durationMs);
}

export const toastStore = {
	get toasts() { return toasts; },
};
