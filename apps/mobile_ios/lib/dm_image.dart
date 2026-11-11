/// Photos in a direct message (issue #1216, migration 20271213121604).
///
/// The client re-encodes a picked photo to a JPEG no larger than
/// [kDmImageMaxEdge] on its long edge before upload, which drops the
/// camera's metadata; the server re-encodes it again and shows only its own
/// copy. These limits mirror the bucket and the worker, and
/// dm_image_test.dart reads them out of the migration. Web twin:
/// `apps/web/src/lib/social/dm_image.ts`.
library;

/// Every `direct_message_images.status` the CHECK admits.
const List<String> kDmImageStatuses = ['pending', 'ready', 'rejected'];

/// The long edge the client scales to; the worker and the size CHECK use it.
const int kDmImageMaxEdge = 2048;

/// The dm-images bucket's file_size_limit.
const int kDmImageMaxBytes = 5 * 1024 * 1024;

/// The only type the bucket accepts.
const String kDmImageContentType = 'image/jpeg';

/// JPEG quality for the client re-encode, on the 0-100 scale.
const int kDmImageQuality = 85;

/// How long a signed URL for a photo lives.
const int kDmImageSignedUrlSeconds = 600;

/// A photo the server is still preparing is checked this often at first...
const Duration kDmImageFastRecheck = Duration(seconds: 4);

/// ...for this many checks (about three minutes)...
const int kDmImageFastChecks = 45;

/// ...and then this often for as long as it is on screen.
const Duration kDmImageSlowRecheck = Duration(seconds: 30);

/// When to check a pending (or unreadable) photo again, [checks] reads in. A
/// slow re-encode still turns into the photo instead of leaving "Preparing
/// photo" up until the conversation is reopened.
Duration dmImageRecheckDelay(int checks) =>
    checks < kDmImageFastChecks ? kDmImageFastRecheck : kDmImageSlowRecheck;

String parseDmImageStatus(Object? raw) =>
    raw == 'ready' || raw == 'rejected' ? raw as String : 'pending';

/// [width] x [height] scaled down to fit [max] on the long edge; never
/// scaled up.
({int width, int height}) dmImageFit(
  num width,
  num height, {
  int max = kDmImageMaxEdge,
}) {
  if (!(width > 0) || !(height > 0)) return (width: 0, height: 0);
  final long = width > height ? width : height;
  if (long <= max) return (width: width.round(), height: height.round());
  final scale = max / long;
  int atLeastOne(num v) => v.round() < 1 ? 1 : v.round();
  return (width: atLeastOne(width * scale), height: atLeastOne(height * scale));
}
