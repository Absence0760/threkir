import { cameraAt, type FlyoverPath } from '#lib/routes/flyover_path.ts';

export interface FlightView {
	pitch: number;
	zoom: number;
}

export interface FlightCamera {
	center: [number, number];
	bearing: number;
	pitch: number;
	zoom: number;
}

export interface FlightTarget {
	jumpTo(camera: FlightCamera): unknown;
	redraw(): unknown;
}

export interface FlightDot {
	setLngLat(at: [number, number]): unknown;
}

export function flightCamera(path: FlyoverPath, dM: number, view: FlightView): FlightCamera {
	const pose = cameraAt(path, dM);
	return { center: pose.center, bearing: pose.bearing, pitch: view.pitch, zoom: view.zoom };
}

/// A camera move made inside an animation frame renders one frame late while
/// the DOM dot paints now, so the dot shakes against the line unless the map
/// redraws synchronously.
export function drawFlightFrame(
	target: FlightTarget,
	dot: FlightDot,
	path: FlyoverPath,
	dM: number,
	view: FlightView,
	inAnimationFrame: boolean,
): void {
	const camera = flightCamera(path, dM, view);
	target.jumpTo(camera);
	dot.setLngLat(camera.center);
	if (inAnimationFrame) target.redraw();
}
