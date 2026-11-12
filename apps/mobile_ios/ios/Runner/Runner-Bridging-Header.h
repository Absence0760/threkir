// `<firebase_messaging/...>` is the CocoaPods header layout. Swift Package
// Manager does not reproduce it; there the plugin's public headers are only
// reachable through its generated Clang module, so both spellings are tried.
#if __has_include(<firebase_messaging/FLTFirebaseMessagingPlugin.h>)
#import <firebase_messaging/FLTFirebaseMessagingPlugin.h>
#else
@import firebase_messaging;
#endif
#import "GeneratedPluginRegistrant.h"
