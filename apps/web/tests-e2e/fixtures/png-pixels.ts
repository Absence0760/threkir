import type { Download, Page } from '@playwright/test';
import { readFile } from 'node:fs/promises';

/// What a downloaded PNG holds, decoded by the browser: its size, the
/// fraction of its pixels with an alpha of at least 250, and the colour of
/// its top-left pixel. A PNG that is only its header passes a size check; the
/// map card that came out fully transparent did exactly that.
export async function pngPixels(
	page: Page,
	download: Download,
): Promise<{ width: number; height: number; opaque: number; corner: [number, number, number, number] }> {
	const bytes = await readFile(await download.path());
	return page.evaluate(async (b64) => {
		const blob = await (await fetch(`data:image/png;base64,${b64}`)).blob();
		const bmp = await createImageBitmap(blob);
		const c = document.createElement('canvas');
		c.width = bmp.width;
		c.height = bmp.height;
		const ctx = c.getContext('2d')!;
		ctx.drawImage(bmp, 0, 0);
		const { data } = ctx.getImageData(0, 0, c.width, c.height);
		let opaque = 0;
		for (let i = 3; i < data.length; i += 4) if (data[i] >= 250) opaque++;
		return {
			width: c.width,
			height: c.height,
			opaque: opaque / (c.width * c.height),
			corner: [data[0], data[1], data[2], data[3]] as [number, number, number, number],
		};
	}, bytes.toString('base64'));
}
