import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;

/// Whether this build offers Google sign-in at all.
///
/// Not on iOS. The iOS flow needs an iOS OAuth client id handed to
/// `GoogleSignIn.initialize(clientId:)` and its reversed form registered as a
/// URL scheme in `Info.plist`, and the app carries neither — so a Google
/// button there could only fail on tap, which App Review rejects as a feature
/// that does not work (Guideline 2.1). Sign in with Apple and email cover
/// sign-in on iOS (decisions § 1700). Android keeps the button behind its own
/// `GOOGLE_WEB_CLIENT_ID` coming-soon gate.
///
/// Reads [defaultTargetPlatform] so a widget test can drive the iOS branch.
bool googleSignInOffered() => defaultTargetPlatform != TargetPlatform.iOS;
