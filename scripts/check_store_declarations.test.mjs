import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
	ANDROID_SOURCES,
	IOS_HEALTH_REQUEST,
	REGISTRY,
	derive,
	emptyDerived,
	evaluate,
	iosHealthPluginTypes,
	lockedPackageNames,
	main,
	note,
	parseHealthPermissions,
	parseInfoPlist,
	parseManifest,
	parsePrivacyManifest,
	swiftHealthKitTypes,
	trackedFiles,
} from './check_store_declarations.mjs';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
/** @param {string} p */
const read = (p) => readFileSync(join(root, p), 'utf8');

/** @returns {import('./check_store_declarations.mjs').Registry} */
const registry = () => JSON.parse(read(REGISTRY));

/** @returns {import('./check_store_declarations.mjs').Registry} */
function minimal() {
	return {
		play: {
			record: 'com.threkir.app',
			form_factors: ['phone', 'wear_os'],
			android_permissions: [],
			foreground_service_types: [],
			health_connect: [],
			data_safety: [],
			console_only: [],
		},
		app_store: {
			record: 'com.threkir.app',
			targets: ['ios', 'watchos'],
			usage_descriptions: [],
			background_modes: [],
			healthkit_types: [],
			required_reason_apis: [],
			app_privacy_label: [],
		},
	};
}

const FGS = 'Play Console → App content → Foreground service permissions';
const none = { lockedPackages: new Set() };

test('a manifest yields its shipped permissions and service types, ignoring comments and removed entries', () => {
	const xml = `<manifest>
		<!-- <uses-permission android:name="android.permission.COMMENTED" /> foregroundServiceType="dataSync" -->
		<uses-permission android:name="android.permission.CAMERA" />
		<uses-permission android:name="android.permission.USE_BIOMETRIC"
		                 tools:node="remove" />
		<uses-permission android:name="android.permission.BLUETOOTH_SCAN"
		                 android:usesPermissionFlags="neverForLocation" />
		<application>
			<service android:name=".Rec" android:exported="false"
			         android:foregroundServiceType="location|health" />
			<service android:name=".Tile" android:exported="true" />
		</application>
	</manifest>`;
	const { permissions, services } = parseManifest(xml);
	assert.deepEqual(permissions, ['android.permission.CAMERA', 'android.permission.BLUETOOTH_SCAN']);
	assert.deepEqual(services, [{ name: '.Rec', types: ['location', 'health'] }]);
});

test('health_permissions.xml, Info.plist and PrivacyInfo.xcprivacy are read for what the consoles care about', () => {
	assert.deepEqual(
		parseHealthPermissions('<resources><!-- <permission name="x" /> --><permission name="android.permission.health.READ_STEPS" /></resources>'),
		['android.permission.health.READ_STEPS'],
	);
	const info = `<plist><dict>
		<key>NSCameraUsageDescription</key><string>scan</string>
		<key>NSLocationTemporaryUsageDescriptionDictionary</key><dict><key>A</key><string>b</string></dict>
		<key>UIBackgroundModes</key><array><string>location</string></array>
		<key>WKBackgroundModes</key><array><string>workout-processing</string></array>
		<key>CFBundleName</key><string>x</string>
	</dict></plist>`;
	assert.deepEqual(parseInfoPlist(info), {
		usage: ['NSCameraUsageDescription', 'NSLocationTemporaryUsageDescriptionDictionary'],
		modes: ['location', 'workout-processing'],
	});
	const priv = `<plist><dict>
		<key>NSPrivacyTracking</key><false/>
		<key>NSPrivacyCollectedDataTypes</key><array><dict>
			<key>NSPrivacyCollectedDataType</key><string>NSPrivacyCollectedDataTypeHealth</string>
			<key>NSPrivacyCollectedDataTypeTracking</key><true/>
		</dict></array>
		<key>NSPrivacyAccessedAPITypes</key><array><dict>
			<key>NSPrivacyAccessedAPIType</key><string>NSPrivacyAccessedAPICategoryUserDefaults</string>
			<key>NSPrivacyAccessedAPITypeReasons</key><array><string>CA92.1</string><string>1C8F.1</string></array>
		</dict></array>
	</dict></plist>`;
	assert.deepEqual(parsePrivacyManifest(priv), { apis: ['UserDefaults:CA92.1', 'UserDefaults:1C8F.1'], collected: ['Health'], tracking: true });
});

test("the iPhone's HealthKit types drop the Android-only entries; the watch's are read from Swift in the same vocabulary", () => {
	const dart = `
	static Future<bool> requestPermission() async {
		final types = [
			HealthDataType.WORKOUT,
			// HealthDataType.COMMENTED,
			if (Platform.isAndroid) HealthDataType.WORKOUT_ROUTE,
			if (Platform.isAndroid)
				HealthDataType.STEPS,
			HealthDataType.HEART_RATE,
		];
	}`;
	assert.deepEqual(iosHealthPluginTypes(dart), ['WORKOUT', 'HEART_RATE']);
	assert.equal(iosHealthPluginTypes('class X {}'), null);
	const swift = 'let a = HKQuantityType(.heartRate); let b = HKQuantityTypeIdentifier.distanceWalkingRunning; let s: Set<HKSampleType> = [HKObjectType.workoutType()]';
	assert.deepEqual(swiftHealthKitTypes(swift).sort(), ['DISTANCE_WALKING_RUNNING', 'HEART_RATE', 'WORKOUT']);
});

test('a foreground service type the registry lacks fails, naming the source, the form factor and the console form', () => {
	const reg = minimal();
	reg.play.foreground_service_types.push({ key: 'location', in: ['phone', 'wear_os'], form: FGS, status: 'declared', evidence: 'x' });
	const d = emptyDerived();
	const wear = 'apps/watch_wear/android/app/src/main/AndroidManifest.xml';
	note(d, 'foreground_service_types', 'location', 'phone', 'phone.xml');
	note(d, 'foreground_service_types', 'location', 'wear_os', wear);
	note(d, 'foreground_service_types', 'health', 'wear_os', wear);
	const { errors } = evaluate(reg, d, none);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /foreground_service_types "health" is requested by apps\/watch_wear\/.*AndroidManifest\.xml \(wear_os\)/);
	assert.match(errors[0], /Foreground service permissions/);
	assert.match(errors[0], /Declare it there first/);
});

test('an entry nothing requests any more fails as stale, and names the form to undeclare it from', () => {
	const reg = minimal();
	reg.app_store.background_modes.push({ key: 'audio', in: ['ios'], form: 'App Review notes', status: 'declared', evidence: 'x' });
	const { errors } = evaluate(reg, emptyDerived(), none);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /background_modes "audio" is listed for ios .* no shipped ios source requests it any more/);
	assert.match(errors[0], /App Review notes/);
});

test('statuses, verified_on and form are held to their vocabulary', () => {
	const reg = minimal();
	reg.play.data_safety.push(
		{ key: 'a', in: ['phone'], form: 'DS', status: 'maybe', evidence: 'x' },
		{ key: 'b', in: ['phone'], form: null, status: 'declared' },
		{ key: 'c', in: ['phone'], form: 'DS', status: 'unknown', verified_on: '2026-11-15', evidence: 'x' },
		{ key: 'd', in: ['phone'], form: 'DS', status: 'declared', verified_on: '15/11/2026', evidence: 'x' },
		{ key: 'e', in: /** @type {any} */ (['tablet']), form: 'DS', status: 'declared' },
		{ key: 'e', in: ['phone'], form: 'DS', status: 'declared', evidence: 'x' },
	);
	const text = evaluate(reg, emptyDerived(), none).errors.join('\n');
	assert.match(text, /"a": status "maybe"/);
	assert.match(text, /"b": form is null, so status must be not_required/);
	assert.match(text, /"c": only a declared entry carries verified_on/);
	assert.match(text, /"d": verified_on must be YYYY-MM-DD/);
	assert.match(text, /"e": "tablet" is not one of phone, wear_os/);
	assert.match(text, /"e": an entry with a console form needs evidence/);
	assert.match(text, /"e" is listed twice/);
});

test('a plugin-contributed permission holds while its plugin is locked, and fails once it is not', () => {
	const reg = minimal();
	reg.play.android_permissions.push({ key: 'android.permission.BLUETOOTH', in: [], form: null, status: 'not_required', plugins: ['reactive_ble_mobile'] });
	assert.deepEqual(evaluate(reg, emptyDerived(), { lockedPackages: new Set(['reactive_ble_mobile']) }).errors, []);
	const { errors } = evaluate(reg, emptyDerived(), none);
	assert.match(errors.join('\n'), /names plugin reactive_ble_mobile, which pubspec\.lock no longer resolves/);
	assert.deepEqual(lockedPackageNames('packages:\n  reactive_ble_mobile:\n    dependency: transitive\n'), new Set(['reactive_ble_mobile']));
});

test('an App Privacy type with no Data safety counterpart fails, and pending or unknown states are reported for the owner', () => {
	const reg = minimal();
	reg.app_store.app_privacy_label.push({ key: 'Health', in: ['ios'], form: 'App Privacy', status: 'declared', evidence: 'x' });
	reg.play.foreground_service_types.push({ key: 'health', in: ['wear_os'], form: FGS, status: 'pending', evidence: 'x' });
	reg.play.console_only.push({ category: 'foreground_service_types', key: 'dataSync', status: 'unknown', evidence: 'x' });
	const d = emptyDerived();
	note(d, 'app_privacy_label', 'Health', 'ios', 'p');
	note(d, 'foreground_service_types', 'health', 'wear_os', 'w');
	const { errors, notices } = evaluate(reg, d, none);
	assert.match(errors.join('\n'), /app_privacy_label "Health" has no data_safety entry/);
	assert.match(notices.join('\n'), /foreground_service_types health \[wear_os\] is pending/);
	assert.match(notices.join('\n'), /console_only foreground_service_types dataSync is unknown/);
	note(d, 'foreground_service_types', 'dataSync', 'phone', 'p');
	assert.match(evaluate(reg, d, none).errors.join('\n'), /console_only "dataSync" is requested by the code again/);
});

test('a new shipped manifest or bundle the guard does not read fails rather than passing unread', () => {
	const files = [...trackedFiles(root), 'apps/watch_wear/android/tile/src/main/AndroidManifest.xml', 'apps/watch_ios/NewExtension/Info.plist'];
	const { problems } = derive({ read, files });
	const text = problems.join('\n');
	assert.match(text, /apps\/watch_wear\/android\/tile\/src\/main\/AndroidManifest\.xml is a manifest this guard does not read/);
	assert.match(text, /apps\/watch_ios\/NewExtension\/Info\.plist belongs to a bundle this guard does not read/);
});

test('the committed tree reads the watch FGS health type and the Health Connect XML that caused the 1.1.0 refusal', () => {
	const { derived, problems } = derive({ read, files: trackedFiles(root) });
	assert.deepEqual(problems, []);
	assert.ok(derived.get('foreground_service_types')?.get('health')?.has('wear_os'));
	assert.ok(derived.get('health_connect')?.get('READ_EXERCISE')?.has('phone'));
	assert.ok(derived.get('healthkit_types')?.get('HEART_RATE')?.has('watchos'));
	assert.ok(iosHealthPluginTypes(read(IOS_HEALTH_REQUEST))?.includes('WORKOUT'));
	assert.equal(ANDROID_SOURCES.length, 2);
	const health = registry().play.foreground_service_types.find((e) => e.key === 'health');
	assert.ok(health && health.status !== 'not_required', 'the FGS health type must carry a console status');
});

test('the committed registry matches the committed tree', () => {
	assert.equal(main(root), 0);
});
