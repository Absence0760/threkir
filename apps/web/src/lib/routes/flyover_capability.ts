/// A two-core or two-gigabyte device stutters through a terrain flight badly
/// enough that the 2D map is the better experience.

export type FlyoverMode = 'flight' | 'static3d' | 'flat2d';

export interface FlyoverCapability {
	webgl2: boolean;
	reducedMotion: boolean;
	lowEnd: boolean;
}

const LOW_END_CORES = 2;
const LOW_END_MEMORY_GB = 2;

export function flyoverMode(c: FlyoverCapability): FlyoverMode {
	if (!c.webgl2 || c.lowEnd) return 'flat2d';
	if (c.reducedMotion) return 'static3d';
	return 'flight';
}

/// `deviceMemory` is Chromium-only and `hardwareConcurrency` can be absent;
/// a missing reading is not evidence of a slow device, so only a present,
/// low value counts.
export function isLowEnd(nav: { hardwareConcurrency?: number; deviceMemory?: number }): boolean {
	const cores = nav.hardwareConcurrency;
	const memory = nav.deviceMemory;
	if (typeof cores === 'number' && cores > 0 && cores <= LOW_END_CORES) return true;
	if (typeof memory === 'number' && memory > 0 && memory <= LOW_END_MEMORY_GB) return true;
	return false;
}

/// The probe context is released straight away: browsers cap live WebGL
/// contexts per page (16 in Chromium) and evict the oldest, which would be
/// the map's own.
function hasWebgl2(w: Window): boolean {
	try {
		const gl = w.document.createElement('canvas').getContext('webgl2');
		if (!gl) return false;
		gl.getExtension('WEBGL_lose_context')?.loseContext();
		return true;
	} catch {
		return false;
	}
}

function prefersReducedMotion(w: Window): boolean {
	try {
		return w.matchMedia('(prefers-reduced-motion: reduce)').matches;
	} catch {
		return false;
	}
}

export function detectFlyoverCapability(w: Window): FlyoverCapability {
	return {
		webgl2: hasWebgl2(w),
		reducedMotion: prefersReducedMotion(w),
		lowEnd: isLowEnd(w.navigator as Navigator & { deviceMemory?: number }),
	};
}
