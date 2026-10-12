/**
 * Generate a GPX XML string from route coordinates and metadata.
 */

import { escapeXml, xmlNumber } from '../util/html_escape';

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
    <name>${escapeXml(name)}</name>
    <time>${now}</time>
  </metadata>
  <trk>
    <name>${escapeXml(name)}</name>
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
			if (p.ts) parts.push(`<time>${escapeXml(String(p.ts))}</time>`);
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
    <name>${escapeXml(name)}</name>
    <time>${escapeXml(startedAtIso)}</time>
  </metadata>
  <trk>
    <name>${escapeXml(name)}</name>
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
    <name>${escapeXml(name)}</name>
    <Placemark>
      <name>${escapeXml(name)}</name>
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
