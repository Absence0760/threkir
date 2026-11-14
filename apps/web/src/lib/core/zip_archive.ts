/// A zip archive opened once and read by member path, on zip.js: the one zip
/// library the web bundle ships. The backup writer already used zip.js's
/// `ZipWriter`, so reading through it too keeps a second zip library (JSZip,
/// 28 KB gzipped) out of the code every reader downloads.
///
/// A missing member reads as null rather than throwing, so each caller decides
/// what an absent file means for its format.

import {
	BlobReader,
	BlobWriter,
	TextWriter,
	Uint8ArrayReader,
	Uint8ArrayWriter,
	ZipReader,
	type FileEntry,
} from '@zip.js/zip.js';

export interface ZipArchive {
	/** Every file member's path in archive order; directory entries are left out. */
	readonly paths: readonly string[];
	has(path: string): boolean;
	text(path: string): Promise<string | null>;
	bytes(path: string): Promise<Uint8Array | null>;
	blob(path: string): Promise<Blob | null>;
}

/// Reads the central directory and nothing else; each member is inflated when
/// it is asked for. Rejects when the input is not a zip.
export async function openZip(input: Blob | Uint8Array | ArrayBuffer): Promise<ZipArchive> {
	const reader =
		input instanceof Blob
			? new BlobReader(input)
			: new Uint8ArrayReader(input instanceof Uint8Array ? input : new Uint8Array(input));
	const entries = await new ZipReader(reader).getEntries();
	const files = new Map<string, FileEntry>();
	for (const entry of entries) {
		if (!entry.directory && !files.has(entry.filename)) files.set(entry.filename, entry);
	}
	const read = async <T>(path: string, get: (entry: FileEntry) => Promise<T>): Promise<T | null> => {
		const entry = files.get(path);
		return entry ? get(entry) : null;
	};
	return {
		paths: [...files.keys()],
		has: (path) => files.has(path),
		text: (path) => read(path, (e) => e.getData(new TextWriter())),
		bytes: (path) => read(path, (e) => e.getData(new Uint8ArrayWriter())),
		blob: (path) => read(path, (e) => e.getData(new BlobWriter())),
	};
}
