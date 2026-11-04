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

/// Moves the camera, then puts the dot on the camera's centre, so the dot is
/// projected through the transform the canvas draws.
///
/// `inAnimationFrame`: a camera move asks MapLibre for a render on the next
/// requestAnimationFrame, and one requested from inside an animation frame
/// lands in the FOLLOWING frame. The DOM dot paints now, so without a
/// synchronous redraw the canvas shows the previous frame's camera under it
/// and the dot sits one frame of travel ahead of its own spot on the course,
/// by a distance that changes with every frame time — the dot shakes against
/// the line (decisions § 2274). Outside an animation frame the scheduled
/// render lands before the next paint, so a redraw would only add a render.
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
