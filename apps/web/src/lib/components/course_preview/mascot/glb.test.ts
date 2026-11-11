import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { GlbError, parseGlb } from './glb.ts';
import { MASCOT_PARTS, HORN_PART } from './palette.ts';

const GLB = fileURLToPath(new URL('../../../../../static/brand/grisnir/grisnir-trot.glb', import.meta.url));
const EXPORT_SCRIPT = fileURLToPath(new URL('../../../../../../../scripts/brand/export_grisnir_gltf.py', import.meta.url));
/// The preview fetches him on the first open; past this the file needs a
/// fresh look at the simplification ratio, not a bigger number here.
const MASCOT_GLB_BUDGET_BYTES = 256 * 1024;

function readGlb(): ArrayBuffer {
	const b = readFileSync(GLB);
	return b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength);
}

/// A minimal GLB around `json` and `bin`, padded as the container requires.
function glb(json: object, bin: Uint8Array = new Uint8Array(0)): ArrayBuffer {
	const text = new TextEncoder().encode(JSON.stringify(json));
	const jsonLen = Math.ceil(text.length / 4) * 4;
	const binLen = Math.ceil(bin.length / 4) * 4;
	const total = 12 + 8 + jsonLen + 8 + binLen;
	const out = new Uint8Array(total);
	const v = new DataView(out.buffer);
	v.setUint32(0, 0x46546c67, true);
	v.setUint32(4, 2, true);
	v.setUint32(8, total, true);
	v.setUint32(12, jsonLen, true);
	v.setUint32(16, 0x4e4f534a, true);
	out.fill(0x20, 20, 20 + jsonLen);
	out.set(text, 20);
	v.setUint32(20 + jsonLen, binLen, true);
	v.setUint32(24 + jsonLen, 0x004e4942, true);
	out.set(bin, 28 + jsonLen);
	return out.buffer;
}

test('the checked-in GLB exists and stays under its budget', () => {
	const size = statSync(GLB).size;
	assert.ok(size > 0);
	assert.ok(size < MASCOT_GLB_BUDGET_BYTES, `${size} bytes`);
});

test('the GLB reads as one skinned mesh with the 21-bone rig and the trot', () => {
	const m = parseGlb(readGlb());
	assert.equal(m.skinJoints.length, 21);
	assert.ok(m.vertexCount > 1000 && m.vertexCount < 65536);
	assert.equal(m.indices.length % 3, 0);
	assert.ok(m.animation);
	assert.equal(m.animation.duration, 0.5);
	assert.ok(m.animation.channels.length >= 21);
	for (let i = 0; i < m.weights.length; i += 4) {
		const w = m.weights[i] + m.weights[i + 1] + m.weights[i + 2] + m.weights[i + 3];
		assert.ok(Math.abs(w - 1) < 0.02, `vertex ${i / 4} weights sum to ${w}`);
	}
});

test('COLOR_0 carries a known part on every vertex and the horn gradient from base to tip', () => {
	const m = parseGlb(readGlb());
	const seen = new Set<number>();
	let hornLo = 1;
	let hornHi = 0;
	for (let v = 0; v < m.vertexCount; v++) {
		const b = m.colors[v * 4 + 2] * 15;
		const part = Math.round(b);
		assert.ok(Math.abs(b - part) < 0.1, `vertex ${v} part channel ${b}`);
		assert.ok(part >= 0 && part < MASCOT_PARTS.length, `vertex ${v} part ${part}`);
		seen.add(part);
		if (part === HORN_PART) {
			hornLo = Math.min(hornLo, m.colors[v * 4]);
			hornHi = Math.max(hornHi, m.colors[v * 4]);
		}
	}
	assert.equal(seen.size, MASCOT_PARTS.length);
	assert.ok(hornLo < 0.05 && hornHi > 0.95, `horn t ${hornLo}..${hornHi}`);
});

test('the renderer and the export script list the parts in one order', () => {
	const src = readFileSync(EXPORT_SCRIPT, 'utf8');
	const list = /^PARTS = \[([^\]]*)\]/m.exec(src)?.[1];
	assert.ok(list, 'PARTS in export_grisnir_gltf.py');
	const names = [...list.matchAll(/"([a-z_]+)"/g)].map((x) => x[1]);
	assert.deepEqual(names, MASCOT_PARTS.map((p) => p.name));
	assert.equal(MASCOT_PARTS[HORN_PART].name, 'horn');
});

test('a file that is not a GLB is refused', () => {
	assert.throws(() => parseGlb(new ArrayBuffer(8)), GlbError);
	assert.throws(() => parseGlb(new TextEncoder().encode('not a glb at all, really not').buffer), GlbError);
});

test('a file needing an extension the reader lacks is refused, so the preview keeps the dot', () => {
	assert.throws(() => parseGlb(glb({ asset: { version: '2.0' }, extensionsRequired: ['EXT_meshopt_compression'] })), /EXT_meshopt_compression/);
});

test('a GLB with no skinned mesh is refused', () => {
	assert.throws(() => parseGlb(glb({ asset: { version: '2.0' }, nodes: [{}] })), /no skinned mesh/);
});

/// One triangle with SHORT-normalized positions, BYTE-normalized normals and
/// UNSIGNED_BYTE colours, weights and joints, as gltfpack quantizes them.
function quantizedTriangle(jointCount: number): ArrayBuffer {
	const bin = new Uint8Array(64);
	const v = new DataView(bin.buffer);
	[32767, 0, -32768, 0, 16384, 0, 0, 0, 32767].forEach((x, i) => v.setInt16(i * 2, x, true));
	[0, 127, 0, 0, 127, 0, 0, 127, 0].forEach((x, i) => v.setInt8(20 + i, x));
	[0, 1, 2].forEach((x, i) => v.setUint16(32 + i * 2, x, true));
	for (let i = 0; i < 3; i++) bin.set([0, 0, 255, 0], 40 + i * 4);
	return glb(
		{
			asset: { version: '2.0' },
			buffers: [{ byteLength: 64 }],
			bufferViews: [
				{ buffer: 0, byteOffset: 0, byteLength: 18 },
				{ buffer: 0, byteOffset: 20, byteLength: 9 },
				{ buffer: 0, byteOffset: 32, byteLength: 6 },
				{ buffer: 0, byteOffset: 40, byteLength: 12 },
				{ buffer: 0, byteOffset: 52, byteLength: 12 },
			],
			accessors: [
				{ bufferView: 0, componentType: 5122, normalized: true, count: 3, type: 'VEC3' },
				{ bufferView: 1, componentType: 5120, normalized: true, count: 3, type: 'VEC3' },
				{ bufferView: 2, componentType: 5123, count: 3, type: 'SCALAR' },
				{ bufferView: 3, componentType: 5121, normalized: true, count: 3, type: 'VEC4' },
				{ bufferView: 4, componentType: 5121, count: jointCount, type: 'VEC4' },
			],
			meshes: [{ primitives: [{ attributes: { POSITION: 0, NORMAL: 1, COLOR_0: 3, JOINTS_0: 4, WEIGHTS_0: 3 }, indices: 2 }] }],
			skins: [{ joints: [1] }],
			nodes: [{ mesh: 0, skin: 0 }, {}],
		},
		bin,
	);
}

test('normalized integers dequantize by the glTF rule', () => {
	const m = parseGlb(quantizedTriangle(3));
	assert.deepEqual([...m.positions].map((x) => Math.round(x * 1000) / 1000), [1, 0, -1, 0, 0.5, 0, 0, 0, 1]);
	assert.deepEqual([...m.normals.subarray(0, 3)], [0, 1, 0]);
	assert.deepEqual([...m.colors.subarray(0, 4)], [0, 0, 1, 0]);
	assert.deepEqual([...m.indices], [0, 1, 2]);
});

test('an attribute with fewer entries than the mesh has vertices is refused', () => {
	assert.throws(() => parseGlb(quantizedTriangle(1)), /JOINTS_0 count/);
});
