import type { GlbChannel, GlbModel } from './glb.ts';

/// Column-major 4x4 matrices, as glTF and WebGL store them.
export type Mat4 = Float32Array;

export function identity(): Mat4 {
	const m = new Float32Array(16);
	m[0] = m[5] = m[10] = m[15] = 1;
	return m;
}

export function multiply(a: Mat4, b: Mat4, out: Mat4 = new Float32Array(16)): Mat4 {
	const r = new Float32Array(16);
	for (let c = 0; c < 4; c++) {
		for (let row = 0; row < 4; row++) {
			let s = 0;
			for (let k = 0; k < 4; k++) s += a[k * 4 + row] * b[c * 4 + k];
			r[c * 4 + row] = s;
		}
	}
	out.set(r);
	return out;
}

export function fromTrs(t: ArrayLike<number>, q: ArrayLike<number>, s: ArrayLike<number>): Mat4 {
	const [x, y, z, w] = [q[0], q[1], q[2], q[3]];
	const m = new Float32Array(16);
	m[0] = (1 - 2 * (y * y + z * z)) * s[0];
	m[1] = 2 * (x * y + z * w) * s[0];
	m[2] = 2 * (x * z - y * w) * s[0];
	m[4] = 2 * (x * y - z * w) * s[1];
	m[5] = (1 - 2 * (x * x + z * z)) * s[1];
	m[6] = 2 * (y * z + x * w) * s[1];
	m[8] = 2 * (x * z + y * w) * s[2];
	m[9] = 2 * (y * z - x * w) * s[2];
	m[10] = (1 - 2 * (x * x + y * y)) * s[2];
	m[12] = t[0];
	m[13] = t[1];
	m[14] = t[2];
	m[15] = 1;
	return m;
}

export function invert(m: Mat4): Mat4 {
	const inv = new Float32Array(16);
	const a = m;
	inv[0] = a[5] * a[10] * a[15] - a[5] * a[11] * a[14] - a[9] * a[6] * a[15] + a[9] * a[7] * a[14] + a[13] * a[6] * a[11] - a[13] * a[7] * a[10];
	inv[4] = -a[4] * a[10] * a[15] + a[4] * a[11] * a[14] + a[8] * a[6] * a[15] - a[8] * a[7] * a[14] - a[12] * a[6] * a[11] + a[12] * a[7] * a[10];
	inv[8] = a[4] * a[9] * a[15] - a[4] * a[11] * a[13] - a[8] * a[5] * a[15] + a[8] * a[7] * a[13] + a[12] * a[5] * a[11] - a[12] * a[7] * a[9];
	inv[12] = -a[4] * a[9] * a[14] + a[4] * a[10] * a[13] + a[8] * a[5] * a[14] - a[8] * a[6] * a[13] - a[12] * a[5] * a[10] + a[12] * a[6] * a[9];
	inv[1] = -a[1] * a[10] * a[15] + a[1] * a[11] * a[14] + a[9] * a[2] * a[15] - a[9] * a[3] * a[14] - a[13] * a[2] * a[11] + a[13] * a[3] * a[10];
	inv[5] = a[0] * a[10] * a[15] - a[0] * a[11] * a[14] - a[8] * a[2] * a[15] + a[8] * a[3] * a[14] + a[12] * a[2] * a[11] - a[12] * a[3] * a[10];
	inv[9] = -a[0] * a[9] * a[15] + a[0] * a[11] * a[13] + a[8] * a[1] * a[15] - a[8] * a[3] * a[13] - a[12] * a[1] * a[11] + a[12] * a[3] * a[9];
	inv[13] = a[0] * a[9] * a[14] - a[0] * a[10] * a[13] - a[8] * a[1] * a[14] + a[8] * a[2] * a[13] + a[12] * a[1] * a[10] - a[12] * a[2] * a[9];
	inv[2] = a[1] * a[6] * a[15] - a[1] * a[7] * a[14] - a[5] * a[2] * a[15] + a[5] * a[3] * a[14] + a[13] * a[2] * a[7] - a[13] * a[3] * a[6];
	inv[6] = -a[0] * a[6] * a[15] + a[0] * a[7] * a[14] + a[4] * a[2] * a[15] - a[4] * a[3] * a[14] - a[12] * a[2] * a[7] + a[12] * a[3] * a[6];
	inv[10] = a[0] * a[5] * a[15] - a[0] * a[7] * a[13] - a[4] * a[1] * a[15] + a[4] * a[3] * a[13] + a[12] * a[1] * a[7] - a[12] * a[3] * a[5];
	inv[14] = -a[0] * a[5] * a[14] + a[0] * a[6] * a[13] + a[4] * a[1] * a[14] - a[4] * a[2] * a[13] - a[12] * a[1] * a[6] + a[12] * a[2] * a[5];
	inv[3] = -a[1] * a[6] * a[11] + a[1] * a[7] * a[10] + a[5] * a[2] * a[11] - a[5] * a[3] * a[10] - a[9] * a[2] * a[7] + a[9] * a[3] * a[6];
	inv[7] = a[0] * a[6] * a[11] - a[0] * a[7] * a[10] - a[4] * a[2] * a[11] + a[4] * a[3] * a[10] + a[8] * a[2] * a[7] - a[8] * a[3] * a[6];
	inv[11] = -a[0] * a[5] * a[11] + a[0] * a[7] * a[9] + a[4] * a[1] * a[11] - a[4] * a[3] * a[9] - a[8] * a[1] * a[7] + a[8] * a[3] * a[5];
	inv[15] = a[0] * a[5] * a[10] - a[0] * a[6] * a[9] - a[4] * a[1] * a[10] + a[4] * a[2] * a[9] + a[8] * a[1] * a[6] - a[8] * a[2] * a[5];
	const det = a[0] * inv[0] + a[1] * inv[4] + a[2] * inv[8] + a[3] * inv[12];
	if (det === 0) return identity();
	for (let i = 0; i < 16; i++) inv[i] /= det;
	return inv;
}

/// A channel's value at `t` seconds, held at its first and last keys.
export function sampleChannel(ch: GlbChannel, t: number, out: Float32Array): void {
	const { times, values, width } = ch;
	const n = times.length;
	if (n === 0) return;
	if (!(t > times[0]) || n === 1) {
		for (let c = 0; c < width; c++) out[c] = values[c];
	} else if (t >= times[n - 1]) {
		for (let c = 0; c < width; c++) out[c] = values[(n - 1) * width + c];
	} else {
		let hi = 1;
		while (times[hi] < t) hi++;
		const lo = hi - 1;
		if (ch.interpolation === 'STEP') {
			for (let c = 0; c < width; c++) out[c] = values[lo * width + c];
		} else {
			const span = times[hi] - times[lo];
			const u = span > 0 ? (t - times[lo]) / span : 0;
			if (width === 4) slerp(values, lo * 4, hi * 4, u, out);
			else for (let c = 0; c < width; c++) out[c] = values[lo * width + c] + (values[hi * width + c] - values[lo * width + c]) * u;
		}
	}
	if (width === 4) normalizeQuat(out);
}

function normalizeQuat(q: Float32Array): void {
	const len = Math.hypot(q[0], q[1], q[2], q[3]);
	if (len > 0) for (let c = 0; c < 4; c++) q[c] /= len;
}

function slerp(v: Float32Array, a: number, b: number, u: number, out: Float32Array): void {
	let dot = v[a] * v[b] + v[a + 1] * v[b + 1] + v[a + 2] * v[b + 2] + v[a + 3] * v[b + 3];
	const sign = dot < 0 ? -1 : 1;
	dot *= sign;
	let wa = 1 - u;
	let wb = u * sign;
	if (dot < 0.9995) {
		const theta = Math.acos(dot);
		const s = Math.sin(theta);
		wa = Math.sin((1 - u) * theta) / s;
		wb = (Math.sin(u * theta) / s) * sign;
	}
	for (let c = 0; c < 4; c++) out[c] = v[a + c] * wa + v[b + c] * wb;
}

/// Where in the cycle `phase` falls, in the animation's seconds: a phase of
/// 0..1 is one loop, and any real number wraps onto it.
export function cycleTime(phase: number, duration: number): number {
	if (!(duration > 0) || !Number.isFinite(phase)) return 0;
	const f = phase - Math.floor(phase);
	return f * duration;
}

/// The skin's joint matrices (16 floats a joint) for the animation at `t`
/// seconds, or for the rest pose the file's nodes hold when `t` is null.
/// glTF ignores the skinned mesh node's own transform, so only the joints
/// place the vertices: `jointGlobal * inverseBind`.
export function jointMatrices(model: GlbModel, t: number | null): Float32Array {
	const local = model.nodes.map((n) => ({
		t: Float32Array.from(n.translation),
		r: Float32Array.from(n.rotation),
		s: Float32Array.from(n.scale),
	}));
	if (t != null && model.animation) {
		for (const ch of model.animation.channels) {
			const slot = ch.path === 'translation' ? local[ch.node].t : ch.path === 'rotation' ? local[ch.node].r : local[ch.node].s;
			sampleChannel(ch, t, slot);
		}
	}
	const global: (Mat4 | null)[] = model.nodes.map(() => null);
	const visit = (i: number, parent: Mat4) => {
		const n = model.nodes[i];
		const own = n.matrix ?? fromTrs(local[i].t, local[i].r, local[i].s);
		const g = multiply(parent, own);
		global[i] = g;
		for (const c of n.children) visit(c, g);
	};
	for (const r of model.roots) visit(r, identity());
	const out = new Float32Array(model.skinJoints.length * 16);
	model.skinJoints.forEach((j, k) => {
		const ibm = model.inverseBindMatrices.subarray(k * 16, k * 16 + 16);
		out.set(multiply(global[j] ?? identity(), ibm), k * 16);
	});
	return out;
}

/// One vertex skinned on the CPU: the same sum the vertex shader takes, for
/// tests and for fitting the camera to the posed goat.
export function skinVertex(model: GlbModel, joints: Float32Array, v: number): [number, number, number] {
	const p = [model.positions[v * 3], model.positions[v * 3 + 1], model.positions[v * 3 + 2], 1];
	const o = [0, 0, 0];
	for (let k = 0; k < 4; k++) {
		const w = model.weights[v * 4 + k];
		if (!w) continue;
		const m = joints.subarray(model.joints[v * 4 + k] * 16);
		for (let row = 0; row < 3; row++) {
			o[row] += w * (m[row] * p[0] + m[4 + row] * p[1] + m[8 + row] * p[2] + m[12 + row] * p[3]);
		}
	}
	return [o[0], o[1], o[2]];
}
