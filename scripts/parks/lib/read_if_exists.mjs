import fs from 'node:fs';

/**
 * The file's text, or null when it does not exist. Reading and catching
 * ENOENT, rather than checking first, leaves no window between the check and
 * the read for the file to change in.
 *
 * @param {string} file
 */
export function readIfExists(file) {
	try {
		return fs.readFileSync(file, 'utf8');
	} catch (err) {
		if (/** @type {NodeJS.ErrnoException} */ (err).code === 'ENOENT') return null;
		throw err;
	}
}
