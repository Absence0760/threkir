/// A reader for the one GLB the course preview draws, Grisnir's trot
/// (`static/brand/grisnir/grisnir-trot.glb`, written by
/// `scripts/brand/export_grisnir_gltf.py`). It reads standard glTF 2.0: one
/// skinned mesh, its skin and node tree, and LINEAR / STEP animation
/// samplers, with `KHR_mesh_quantization`'s integer attributes dequantized to
/// floats here so the renderer only ever sees `Float32Array`s. Anything else a
/// file requires is refused, which the preview reads as "draw the plain dot".

export interface GlbNode {
	name: string | null;
	children: number[];
	translation: [number, number, number];
	rotation: [number, number, number, number];
	scale: [number, number, number];
	/// A node given as a matrix keeps it; its TRS above is then unused.
	matrix: Float32Array | null;
	mesh: number | null;
}

export interface GlbChannel {
	node: number;
	path: 'translation' | 'rotation' | 'scale';
	interpolation: 'LINEAR' | 'STEP';
	times: Float32Array;
	values: Float32Array;
	/// 3 for translation and scale, 4 for a rotation quaternion.
	width: number;
}

export interface GlbModel {
	positions: Float32Array;
	normals: Float32Array;
	colors: Float32Array;
	joints: Float32Array;
	weights: Float32Array;
	indices: Uint16Array | Uint32Array;
	vertexCount: number;
	nodes: GlbNode[];
	roots: number[];
	meshNode: number;
	skinJoints: number[];
	inverseBindMatrices: Float32Array;
	animation: { name: string | null; duration: number; channels: GlbChannel[] } | null;
}

const MAGIC = 0x46546c67;
const CHUNK_JSON = 0x4e4f534a;
const CHUNK_BIN = 0x004e4942;
const SUPPORTED_REQUIRED = new Set(['KHR_mesh_quantization']);
const COMPONENTS: Record<string, number> = { SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4, MAT4: 16 };

interface Json {
	extensionsRequired?: string[];
	accessors?: Accessor[];
	bufferViews?: { buffer: number; byteOffset?: number; byteLength: number; byteStride?: number }[];
	nodes?: {
		name?: string;
		children?: number[];
		translation?: number[];
		rotation?: number[];
		scale?: number[];
		matrix?: number[];
		mesh?: number;
		skin?: number;
	}[];
	meshes?: { primitives: { attributes: Record<string, number>; indices?: number; mode?: number }[] }[];
	skins?: { joints: number[]; inverseBindMatrices?: number }[];
	animations?: {
		name?: string;
		channels: { sampler: number; target: { node?: number; path: string } }[];
		samplers: { input: number; output: number; interpolation?: string }[];
	}[];
	scenes?: { nodes?: number[] }[];
	scene?: number;
}

interface Accessor {
	bufferView?: number;
	byteOffset?: number;
	componentType: number;
	normalized?: boolean;
	count: number;
	type: string;
}

export class GlbError extends Error {}

function fail(why: string): never {
	throw new GlbError(`grisnir glb: ${why}`);
}

function componentReader(view: DataView, componentType: number): [(at: number) => number, number] {
	switch (componentType) {
		case 5120:
			return [(at) => view.getInt8(at), 1];
		case 5121:
			return [(at) => view.getUint8(at), 1];
		case 5122:
			return [(at) => view.getInt16(at, true), 2];
		case 5123:
			return [(at) => view.getUint16(at, true), 2];
		case 5125:
			return [(at) => view.getUint32(at, true), 4];
		case 5126:
			return [(at) => view.getFloat32(at, true), 4];
		default:
			return fail(`component type ${componentType}`);
	}
}

/// glTF's normalized-integer rule: signed types clamp at -1.
function normalize(v: number, componentType: number): number {
	switch (componentType) {
		case 5120:
			return Math.max(v / 127, -1);
		case 5121:
			return v / 255;
		case 5122:
			return Math.max(v / 32767, -1);
		case 5123:
			return v / 65535;
		default:
			return v;
	}
}

function readAccessor(json: Json, bin: DataView, index: number): { data: Float32Array; width: number; count: number } {
	const a = json.accessors?.[index] ?? fail(`accessor ${index}`);
	const width = COMPONENTS[a.type] ?? fail(`accessor type ${a.type}`);
	const data = new Float32Array(a.count * width);
	if (a.bufferView == null) return { data, width, count: a.count };
	const bv = json.bufferViews?.[a.bufferView] ?? fail(`buffer view ${a.bufferView}`);
	if (bv.buffer !== 0) fail('external buffer');
	const [read, size] = componentReader(bin, a.componentType);
	const stride = bv.byteStride ?? size * width;
	const base = (bv.byteOffset ?? 0) + (a.byteOffset ?? 0);
	const end = base + stride * (a.count - 1) + size * width;
	if (a.count > 0 && end > Math.min(bin.byteLength, (bv.byteOffset ?? 0) + bv.byteLength)) fail(`accessor ${index} overruns`);
	for (let i = 0; i < a.count; i++) {
		for (let c = 0; c < width; c++) {
			const v = read(base + i * stride + c * size);
			data[i * width + c] = a.normalized ? normalize(v, a.componentType) : v;
		}
	}
	return { data, width, count: a.count };
}

function readIndices(json: Json, bin: DataView, index: number, vertexCount: number): Uint16Array | Uint32Array {
	const { data } = readAccessor(json, bin, index);
	const out = vertexCount > 65535 ? new Uint32Array(data.length) : new Uint16Array(data.length);
	for (let i = 0; i < data.length; i++) {
		if (data[i] >= vertexCount) fail('index out of range');
		out[i] = data[i];
	}
	return out;
}

function tuple<N extends 3 | 4>(v: number[] | undefined, fallback: number[], n: N): number[] {
	return v && v.length === n && v.every(Number.isFinite) ? [...v] : [...fallback];
}

export function parseGlb(buffer: ArrayBuffer): GlbModel {
	if (buffer.byteLength < 20) fail('too short');
	const head = new DataView(buffer);
	if (head.getUint32(0, true) !== MAGIC) fail('not a GLB');
	if (head.getUint32(4, true) !== 2) fail('not glTF 2');
	let jsonChunk: Json | null = null;
	let binChunk: DataView | null = null;
	let at = 12;
	const total = Math.min(head.getUint32(8, true), buffer.byteLength);
	while (at + 8 <= total) {
		const length = head.getUint32(at, true);
		const type = head.getUint32(at + 4, true);
		const start = at + 8;
		if (start + length > total) fail('chunk overruns');
		if (type === CHUNK_JSON) jsonChunk = JSON.parse(new TextDecoder().decode(new Uint8Array(buffer, start, length))) as Json;
		else if (type === CHUNK_BIN) binChunk = new DataView(buffer, start, length);
		at = start + length + ((4 - (length % 4)) % 4);
	}
	const json: Json = jsonChunk ?? fail('no JSON chunk');
	const bin: DataView = binChunk ?? fail('no BIN chunk');
	for (const ext of json.extensionsRequired ?? []) {
		if (!SUPPORTED_REQUIRED.has(ext)) fail(`requires ${ext}`);
	}

	const rawNodes = json.nodes ?? [];
	const meshNode = rawNodes.findIndex((n) => n.mesh != null && n.skin != null);
	if (meshNode < 0) fail('no skinned mesh');
	const mesh = json.meshes?.[rawNodes[meshNode].mesh as number] ?? fail('mesh');
	if (mesh.primitives.length !== 1) fail('expects one primitive');
	const prim = mesh.primitives[0];
	if ((prim.mode ?? 4) !== 4) fail('expects triangles');
	const attr = (name: string, width: number) => {
		const index = prim.attributes[name];
		if (index == null) fail(`no ${name}`);
		const a = readAccessor(json, bin, index);
		if (a.width !== width) fail(`${name} width ${a.width}`);
		if (vertexCount >= 0 && a.count !== vertexCount) fail(`${name} count ${a.count}`);
		return a;
	};
	let vertexCount = -1;
	const pos = attr('POSITION', 3);
	vertexCount = pos.count;
	const normals = attr('NORMAL', 3).data;
	const colorAcc = attr('COLOR_0', json.accessors?.[prim.attributes.COLOR_0]?.type === 'VEC3' ? 3 : 4);
	const colors = new Float32Array(vertexCount * 4);
	for (let i = 0; i < vertexCount; i++) {
		for (let c = 0; c < 4; c++) colors[i * 4 + c] = c < colorAcc.width ? colorAcc.data[i * colorAcc.width + c] : 1;
	}
	const joints = attr('JOINTS_0', 4).data;
	const weights = attr('WEIGHTS_0', 4).data;
	if (prim.indices == null) fail('no indices');
	const indices = readIndices(json, bin, prim.indices, vertexCount);

	const skin = json.skins?.[rawNodes[meshNode].skin as number] ?? fail('skin');
	const ibm =
		skin.inverseBindMatrices != null
			? readAccessor(json, bin, skin.inverseBindMatrices).data
			: identityStack(skin.joints.length);
	if (ibm.length !== skin.joints.length * 16) fail('inverse bind matrices');
	for (let i = 0; i < joints.length; i++) {
		if (joints[i] >= skin.joints.length) fail('joint out of range');
	}

	const nodes: GlbNode[] = rawNodes.map((n) => ({
		name: n.name ?? null,
		children: n.children ?? [],
		translation: tuple(n.translation, [0, 0, 0], 3) as [number, number, number],
		rotation: tuple(n.rotation, [0, 0, 0, 1], 4) as [number, number, number, number],
		scale: tuple(n.scale, [1, 1, 1], 3) as [number, number, number],
		matrix: n.matrix && n.matrix.length === 16 ? Float32Array.from(n.matrix) : null,
		mesh: n.mesh ?? null,
	}));
	for (const n of nodes) {
		for (const c of n.children) if (c < 0 || c >= nodes.length) fail('child out of range');
	}
	const scene = json.scenes?.[json.scene ?? 0];
	const childSet = new Set(nodes.flatMap((n) => n.children));
	const roots = scene?.nodes ?? nodes.map((_, i) => i).filter((i) => !childSet.has(i));

	return {
		positions: pos.data,
		normals,
		colors,
		joints,
		weights,
		indices,
		vertexCount,
		nodes,
		roots,
		meshNode,
		skinJoints: [...skin.joints],
		inverseBindMatrices: ibm,
		animation: readAnimation(json, bin, nodes.length),
	};
}

function identityStack(n: number): Float32Array {
	const out = new Float32Array(n * 16);
	for (let i = 0; i < n; i++) for (let k = 0; k < 4; k++) out[i * 16 + k * 5] = 1;
	return out;
}

function readAnimation(json: Json, bin: DataView, nodeCount: number): GlbModel['animation'] {
	const anim = json.animations?.[0];
	if (!anim) return null;
	const channels: GlbChannel[] = [];
	let duration = 0;
	for (const ch of anim.channels) {
		const path = ch.target.path;
		const node = ch.target.node;
		if (node == null || node < 0 || node >= nodeCount) continue;
		if (path !== 'translation' && path !== 'rotation' && path !== 'scale') continue;
		const sampler = anim.samplers[ch.sampler] ?? fail('sampler');
		const interpolation = sampler.interpolation ?? 'LINEAR';
		if (interpolation !== 'LINEAR' && interpolation !== 'STEP') fail(`${interpolation} interpolation`);
		const times = readAccessor(json, bin, sampler.input).data;
		const out = readAccessor(json, bin, sampler.output);
		const width = path === 'rotation' ? 4 : 3;
		if (out.width !== width || out.count !== times.length) fail('sampler shape');
		for (let i = 1; i < times.length; i++) if (!(times[i] >= times[i - 1])) fail('sampler times');
		if (times.length) duration = Math.max(duration, times[times.length - 1]);
		channels.push({ node, path, interpolation, times, values: out.data, width });
	}
	return { name: anim.name ?? null, duration, channels };
}
