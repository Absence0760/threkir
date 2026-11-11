/// Draws Grisnir into his own small WebGL2 canvas: the skinned GLB, the
/// model's toon ramp per part (`palette.ts`) and an inverted-hull ink line
/// extruded in screen space, so it stays about a pixel and a half wide at any
/// size. The canvas is then either the dialog's position marker or a sprite
/// the video export draws over its frame, so both show the same goat.
///
/// Auxiliary (conventions § Layered resilience): `loadMascot` resolves null
/// on any failure (no WebGL2, a failed fetch, a file it cannot read, a shader
/// that will not compile) and logs why, and the caller keeps the plain dot.

import { parseGlb, type GlbModel } from './glb.ts';
import { cycleTime, jointMatrices } from './skeleton.ts';
import {
	HIGH_FROM,
	HORN_BAND,
	HORN_RAMP,
	INK,
	LIGHT_VIEW,
	linearRgb,
	MASCOT_PARTS,
	SHADOW_BELOW,
} from './palette.ts';

export const MASCOT_GLB_URL = '/brand/grisnir/grisnir-trot.glb';
/// The marker's box in CSS px. The ground point under his hooves is its
/// centre, so the box sits centred on the course position like the dot did.
export const MASCOT_BOX_CSS_PX = 96;
/// Half the box, in model units (about a metre of goat each): his longest
/// reach from the hooves, horn tip or tail, at any heading and tilt, fits.
const VIEW_HALF_UNITS = 1.4;
const INK_PX = 1.5;
const MAX_JOINTS = 32;

export interface MascotPose {
	/// Degrees clockwise from screen-up, on the ground (`screenYawDeg`).
	yawDeg: number;
	/// The map's pitch: 0 looks straight down.
	pitchDeg: number;
	/// The trot's phase, 0..1; null is his standing rest pose.
	phase: number | null;
}

const VERT = `#version 300 es
in vec3 aPos;
in vec3 aNormal;
in vec4 aColor;
in vec4 aJoints;
in vec4 aWeights;
uniform mat4 uJoints[${MAX_JOINTS}];
uniform mat4 uModel;
uniform mat4 uView;
uniform mat4 uProj;
uniform float uInk;
uniform vec2 uInkClip;
out vec3 vNormalView;
out vec3 vNormalWorld;
out vec4 vColor;
void main() {
	mat4 skin = aWeights.x * uJoints[int(aJoints.x)] + aWeights.y * uJoints[int(aJoints.y)]
		+ aWeights.z * uJoints[int(aJoints.z)] + aWeights.w * uJoints[int(aJoints.w)];
	mat4 model = uModel * skin;
	vec3 nWorld = normalize(mat3(model) * aNormal);
	vec3 nView = mat3(uView) * nWorld;
	vec4 clip = uProj * uView * model * vec4(aPos, 1.0);
	if (uInk > 0.5) {
		vec2 dir = (uProj * vec4(nView, 0.0)).xy;
		float len = length(dir);
		if (len > 1e-5) clip.xy += (dir / len) * uInkClip * (aColor.g / 0.85) * clip.w;
		clip.z += 0.002 * clip.w;
	}
	vNormalView = nView;
	vNormalWorld = nWorld;
	vColor = aColor;
	gl_Position = clip;
}`;

const FRAG = `#version 300 es
precision highp float;
in vec3 vNormalView;
in vec3 vNormalWorld;
in vec4 vColor;
uniform float uInk;
uniform vec3 uInkColor;
uniform vec3 uShadow[8];
uniform vec3 uBase[8];
uniform vec3 uHigh[8];
uniform vec3 uHorn[3];
uniform float uHornMid;
uniform vec3 uBand;
uniform vec3 uLight;
uniform float uAlpha;
out vec4 frag;
vec3 toSrgb(vec3 c) {
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c));
}
void main() {
	if (uInk > 0.5) {
		if (vColor.g < 0.01) discard;
		frag = vec4(toSrgb(uInkColor) * uAlpha, uAlpha);
		return;
	}
	int part = int(floor(vColor.b * 15.0 + 0.5));
	vec3 n = normalize(vNormalView);
	vec3 nw = normalize(vNormalWorld);
	if (!gl_FrontFacing) { n = -n; nw = -nw; }
	float v = max(dot(n, uLight), nw.y);
	vec3 c;
	if (part == 2) {
		float t = clamp(vColor.r, 0.0, 1.0);
		vec3 g = t < uHornMid ? mix(uHorn[0], uHorn[1], t / uHornMid) : mix(uHorn[1], uHorn[2], (t - uHornMid) / (1.0 - uHornMid));
		float band = (fract(t * 13.0) > 0.8 && t < 0.38) ? 1.0 : 0.0;
		g = mix(g, uBand, band);
		vec3 s = v < ${SHADOW_BELOW.toFixed(2)} ? vec3(0.70, 0.66, 0.78) : (v < 0.90 ? vec3(1.0) : vec3(1.45, 1.4, 1.45));
		c = min(g * s, vec3(1.0));
	} else {
		int p = clamp(part, 0, 7);
		c = v < ${SHADOW_BELOW.toFixed(2)} ? uShadow[p] : (v < ${HIGH_FROM.toFixed(2)} ? uBase[p] : uHigh[p]);
	}
	frag = vec4(toSrgb(c) * uAlpha, uAlpha);
}`;

function compile(gl: WebGL2RenderingContext, type: number, src: string): WebGLShader {
	const s = gl.createShader(type);
	if (!s) throw new Error('no shader');
	gl.shaderSource(s, src);
	gl.compileShader(s);
	if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(`shader: ${gl.getShaderInfoLog(s)}`);
	return s;
}

/// The view a map camera at `pitchDeg` has of the ground under it: screen-up
/// is the ground's -Z, and the eye tilts back toward +Z as the map pitches.
export function mascotViewMatrix(pitchDeg: number): Float32Array {
	const p = (Math.min(Math.max(pitchDeg, 0), 89) * Math.PI) / 180;
	const f = [0, -Math.cos(p), -Math.sin(p)];
	const up = [0, Math.sin(p), -Math.cos(p)];
	const r = [f[1] * up[2] - f[2] * up[1], f[2] * up[0] - f[0] * up[2], f[0] * up[1] - f[1] * up[0]];
	const eye = [0, 10 * Math.cos(p), 10 * Math.sin(p)];
	const dot = (a: number[], b: number[]) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
	return Float32Array.from([
		r[0], up[0], -f[0], 0,
		r[1], up[1], -f[1], 0,
		r[2], up[2], -f[2], 0,
		-dot(r, eye), -dot(up, eye), dot(f, eye), 1,
	]);
}

/// Turns him about his hooves to face `yawDeg` clockwise from screen-up. The
/// model faces -Z, which the view puts at screen-up.
export function mascotYawMatrix(yawDeg: number): Float32Array {
	const a = (-yawDeg * Math.PI) / 180;
	const c = Math.cos(a);
	const s = Math.sin(a);
	return Float32Array.from([c, 0, -s, 0, 0, 1, 0, 0, s, 0, c, 0, 0, 0, 0, 1]);
}

function ortho(h: number): Float32Array {
	const near = 1;
	const far = 20;
	return Float32Array.from([1 / h, 0, 0, 0, 0, 1 / h, 0, 0, 0, 0, -2 / (far - near), 0, 0, 0, -(far + near) / (far - near), 1]);
}

export class MascotRenderer {
	readonly canvas: HTMLCanvasElement;
	private gl: WebGL2RenderingContext;
	private program: WebGLProgram;
	private vao: WebGLVertexArrayObject;
	private count: number;
	private indexType: number;
	private uniforms: Record<string, WebGLUniformLocation | null> = {};
	private lost = false;
	private restPose: Float32Array;

	constructor(
		private model: GlbModel,
		canvas: HTMLCanvasElement,
		opts: { preserveDrawingBuffer?: boolean } = {},
	) {
		if (model.skinJoints.length > MAX_JOINTS) throw new Error('too many joints');
		this.canvas = canvas;
		const gl = canvas.getContext('webgl2', {
			alpha: true,
			premultipliedAlpha: true,
			antialias: true,
			depth: true,
			preserveDrawingBuffer: opts.preserveDrawingBuffer ?? false,
		});
		if (!gl) throw new Error('no WebGL2');
		this.gl = gl;
		canvas.addEventListener('webglcontextlost', () => {
			this.lost = true;
		});
		const program = gl.createProgram();
		if (!program) throw new Error('no program');
		gl.attachShader(program, compile(gl, gl.VERTEX_SHADER, VERT));
		gl.attachShader(program, compile(gl, gl.FRAGMENT_SHADER, FRAG));
		gl.bindAttribLocation(program, 0, 'aPos');
		gl.bindAttribLocation(program, 1, 'aNormal');
		gl.bindAttribLocation(program, 2, 'aColor');
		gl.bindAttribLocation(program, 3, 'aJoints');
		gl.bindAttribLocation(program, 4, 'aWeights');
		gl.linkProgram(program);
		if (!gl.getProgramParameter(program, gl.LINK_STATUS)) throw new Error(`link: ${gl.getProgramInfoLog(program)}`);
		this.program = program;
		const vao = gl.createVertexArray();
		if (!vao) throw new Error('no vertex array');
		this.vao = vao;
		gl.bindVertexArray(vao);
		const attrs: [Float32Array, number][] = [
			[model.positions, 3],
			[model.normals, 3],
			[model.colors, 4],
			[model.joints, 4],
			[model.weights, 4],
		];
		attrs.forEach(([data, size], loc) => {
			const buf = gl.createBuffer();
			gl.bindBuffer(gl.ARRAY_BUFFER, buf);
			gl.bufferData(gl.ARRAY_BUFFER, data, gl.STATIC_DRAW);
			gl.enableVertexAttribArray(loc);
			gl.vertexAttribPointer(loc, size, gl.FLOAT, false, 0, 0);
		});
		const ibuf = gl.createBuffer();
		gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, ibuf);
		gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, model.indices, gl.STATIC_DRAW);
		this.count = model.indices.length;
		this.indexType = model.indices instanceof Uint32Array ? gl.UNSIGNED_INT : gl.UNSIGNED_SHORT;
		gl.bindVertexArray(null);
		for (const name of ['uJoints', 'uModel', 'uView', 'uProj', 'uInk', 'uInkClip', 'uInkColor', 'uShadow', 'uBase', 'uHigh', 'uHorn', 'uHornMid', 'uBand', 'uLight', 'uAlpha']) {
			this.uniforms[name] = gl.getUniformLocation(program, name);
		}
		gl.useProgram(program);
		const flat = (pick: (p: (typeof MASCOT_PARTS)[number]) => string) =>
			Float32Array.from(MASCOT_PARTS.flatMap((p) => linearRgb(pick(p))));
		gl.uniform3fv(this.uniforms.uShadow, flat((p) => p.shadow));
		gl.uniform3fv(this.uniforms.uBase, flat((p) => p.base));
		gl.uniform3fv(this.uniforms.uHigh, flat((p) => p.high));
		gl.uniform3fv(this.uniforms.uHorn, Float32Array.from(HORN_RAMP.flatMap(([, hex]) => linearRgb(hex))));
		gl.uniform1f(this.uniforms.uHornMid, HORN_RAMP[1][0]);
		gl.uniform3fv(this.uniforms.uBand, linearRgb(HORN_BAND));
		gl.uniform3fv(this.uniforms.uInkColor, linearRgb(INK));
		const l = Math.hypot(...LIGHT_VIEW);
		gl.uniform3f(this.uniforms.uLight, LIGHT_VIEW[0] / l, LIGHT_VIEW[1] / l, LIGHT_VIEW[2] / l);
		gl.uniformMatrix4fv(this.uniforms.uProj, false, ortho(VIEW_HALF_UNITS));
		this.restPose = jointMatrices(model, null);
	}

	get usable(): boolean {
		return !this.lost && !this.gl.isContextLost();
	}

	/// Sizes the drawing buffer: `px` device pixels square.
	setSize(px: number): void {
		const n = Math.max(1, Math.round(px));
		if (this.canvas.width !== n) this.canvas.width = n;
		if (this.canvas.height !== n) this.canvas.height = n;
	}

	draw(pose: MascotPose, alpha = 1): void {
		if (!this.usable) return;
		const gl = this.gl;
		const w = this.canvas.width;
		gl.viewport(0, 0, w, this.canvas.height);
		gl.clearColor(0, 0, 0, 0);
		gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
		gl.useProgram(this.program);
		gl.bindVertexArray(this.vao);
		const anim = this.model.animation;
		const joints = pose.phase == null || !anim ? this.restPose : jointMatrices(this.model, cycleTime(pose.phase, anim.duration));
		gl.uniformMatrix4fv(this.uniforms.uJoints, false, joints);
		gl.uniformMatrix4fv(this.uniforms.uModel, false, mascotYawMatrix(pose.yawDeg));
		gl.uniformMatrix4fv(this.uniforms.uView, false, mascotViewMatrix(pose.pitchDeg));
		gl.uniform1f(this.uniforms.uAlpha, alpha);
		// The box spans 2 clip units, so a CSS pixel of it is 2 / MASCOT_BOX_CSS_PX.
		const ink = (2 * INK_PX) / MASCOT_BOX_CSS_PX;
		gl.uniform2f(this.uniforms.uInkClip, ink, ink);
		gl.enable(gl.DEPTH_TEST);
		gl.depthFunc(gl.LEQUAL);
		gl.disable(gl.BLEND);
		gl.enable(gl.CULL_FACE);
		gl.cullFace(gl.FRONT);
		gl.uniform1f(this.uniforms.uInk, 1);
		gl.drawElements(gl.TRIANGLES, this.count, this.indexType, 0);
		gl.disable(gl.CULL_FACE);
		gl.uniform1f(this.uniforms.uInk, 0);
		gl.drawElements(gl.TRIANGLES, this.count, this.indexType, 0);
		gl.bindVertexArray(null);
	}

	dispose(): void {
		this.gl.getExtension('WEBGL_lose_context')?.loseContext();
	}
}

let modelPromise: Promise<GlbModel> | null = null;

/// The GLB is fetched once per page, on the first dialog that wants him, and
/// never in the page's own first paint.
function loadModel(): Promise<GlbModel> {
	modelPromise ??= fetch(MASCOT_GLB_URL)
		.then((r) => {
			if (!r.ok) throw new Error(`grisnir glb: HTTP ${r.status}`);
			return r.arrayBuffer();
		})
		.then(parseGlb)
		.catch((e: unknown) => {
			modelPromise = null;
			throw e;
		});
	return modelPromise;
}

export async function loadMascot(
	canvas: HTMLCanvasElement,
	opts: { preserveDrawingBuffer?: boolean } = {},
): Promise<MascotRenderer | null> {
	try {
		const model = await loadModel();
		return new MascotRenderer(model, canvas, opts);
	} catch (e) {
		console.warn('course preview: Grisnir unavailable, keeping the dot', e);
		return null;
	}
}
