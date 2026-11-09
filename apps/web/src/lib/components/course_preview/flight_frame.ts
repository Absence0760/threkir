import { cameraAt, maxDotOffsetM, pointAtDistance, type FlyoverPath } from '#lib/routes/flyover_path.ts';

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

/// `speedMps` is the speed the flight covers the course at; the camera's
/// heading and centre smoothing follow it (`cameraAt`). The centre is held
/// within `MAX_DOT_OFFSET_PX` of the dot at the view's zoom.
export function flightCamera(path: FlyoverPath, dM: number, view: FlightView, speedMps: number): FlightCamera {
	return flightPose(path, dM, view, speedMps).camera;
}

/// The camera and the dot's spot for one flight frame.
export function flightPose(
	path: FlyoverPath,
	dM: number,
	view: FlightView,
	speedMps: number,
): { camera: FlightCamera; dot: [number, number] } {
	const lat = pointAtDistance(path, dM).lat;
	const pose = cameraAt(path, dM, { speedMps, maxDotOffsetM: maxDotOffsetM(view.zoom, lat) });
	return {
		camera: { center: pose.center, bearing: pose.bearing, pitch: view.pitch, zoom: view.zoom },
		dot: pose.position,
	};
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
	speedMps: number,
	inAnimationFrame: boolean,
): void {
	const { camera, dot: at } = flightPose(path, dM, view, speedMps);
	target.jumpTo(camera);
	dot.setLngLat(at);
	if (inAnimationFrame) target.redraw();
}
