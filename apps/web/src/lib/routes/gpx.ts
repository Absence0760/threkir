/**
 * Generate a GPX XML string from route coordinates and metadata.
 */

import { escapeHtml } from '../util/html_escape';

/// Code points outside XML 1.0's `Char` production — C0 controls other than
/// tab / LF / CR, lone surrogates, U+FFFE / U+FFFF. No entity can carry them,
/// so one in a name made every reader refuse the whole file. Same set and
/// U+FFFD replacement as the Art 20 exporter (export-data/render.ts).
const XML_FORBIDDEN_CHARS = /[^\t\n\r\u0020-\uD7FF\uE000-\uFFFD\u{10000}-\u{10FFFF}]/gu;

/// A string as XML character data or attribute text.
function xmlText(v: string): string {
	return escapeHtml(v.replace(XML_FORBIDDEN_CHARS, '\uFFFD'));
}

/// A stored value as an XML number, or null when it is not a finite number.
/// The tracks are JSON blobs with no schema between them and this writer, and
/// `lat` / `lon` land inside quoted attributes, so anything else is dropped
/// rather than written as `NaN` or as markup.
function xmlNumber(v: unknown): string | null {
	return typeof v === 'number' && Number.isFinite(v) ? String(v) : null;
}

export function toGpx(
	name: string,
	coordinates: [number, number][],
	elevations: number[]
): string {
	const now = new Date().toISOString();

	const trackpoints = coordinates
		.flatMap(([lng, lat], i) => {
			const latText = xmlNumber(lat);
			const lngText = xmlNumber(lng);
			if (latText === null || lngText === null) return [];
			const ele = xmlNumber(elevations[i]) ?? '0';
			return [`      <trkpt lat="${latText}" lon="${lngText}"><ele>${ele}</ele></trkpt>`];
		})
		.join('\n');

	return `<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="Threkir"
  xmlns="http://www.topografix.com/GPX/1/1"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">
  <metadata>
    <name>${xmlText(name)}</name>
    <time>${now}</time>
  </metadata>
  <trk>
    <name>${xmlText(name)}</name>
    <trkseg>
${trackpoints}
    </trkseg>
  </trk>
</gpx>`;
}

/**
 * Generate a GPX XML from a run — includes per-point `<time>` so the
 * trace round-trips into Strava / Garmin / Komoot as a real activity
 * (not just a route). Leaves a `<trkpt>` without `<ele>` when the
 * point didn't carry elevation; mirrors what GPX 1.1 allows.
 */
export function toRunGpx(
	name: string,
	startedAtIso: string,
	track: Array<{ lat: number; lng: number; ele?: number | null; ts?: string | null }>,
): string {
	const trackpoints = track
		.flatMap((p) => {
			const latText = xmlNumber(p.lat);
			const lngText = xmlNumber(p.lng);
			if (latText === null || lngText === null) return [];
			const parts: string[] = [`<trkpt lat="${latText}" lon="${lngText}">`];
			const ele = xmlNumber(p.ele);
			if (ele !== null) parts.push(`<ele>${ele}</ele>`);
			if (p.ts) parts.push(`<time>${xmlText(String(p.ts))}</time>`);
			parts.push('</trkpt>');
			return ['      ' + parts.join('')];
		})
		.join('\n');

	return `<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="Threkir"
  xmlns="http://www.topografix.com/GPX/1/1"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">
  <metadata>
    <name>${xmlText(name)}</name>
    <time>${xmlText(startedAtIso)}</time>
  </metadata>
  <trk>
    <name>${xmlText(name)}</name>
    <trkseg>
${trackpoints}
    </trkseg>
  </trk>
</gpx>`;
}

/**
 * Trigger a file download in the browser.
 */
export function downloadFile(content: string, filename: string, mimeType: string) {
	const blob = new Blob([content], { type: mimeType });
	const url = URL.createObjectURL(blob);
	const a = document.createElement('a');
	a.href = url;
	a.download = filename;
	a.click();
	URL.revokeObjectURL(url);
}

/**
 * Generate a KML XML string from route coordinates and metadata.
 */
export function toKml(
	name: string,
	coordinates: [number, number][],
	elevations: number[]
): string {
	const coordString = coordinates
		.flatMap(([lng, lat], i) => {
			const latText = xmlNumber(lat);
			const lngText = xmlNumber(lng);
			if (latText === null || lngText === null) return [];
			return [`${lngText},${latText},${xmlNumber(elevations[i]) ?? '0'}`];
		})
		.join('\n          ');

	return `<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>${xmlText(name)}</name>
    <Placemark>
      <name>${xmlText(name)}</name>
      <Style>
        <LineStyle>
          <color>ffff0000</color>
          <width>3</width>
        </LineStyle>
      </Style>
      <LineString>
        <tessellate>1</tessellate>
        <coordinates>
          ${coordString}
        </coordinates>
      </LineString>
    </Placemark>
  </Document>
</kml>`;
}
