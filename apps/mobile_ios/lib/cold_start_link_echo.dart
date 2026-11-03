/// The app_links plugin delivers the cold-start link twice, once from
/// `getInitialLink` and once as the stream's first event, in either order.
/// This drops exactly that one echo. Deduplicating every repeat instead would
/// swallow a second tap on the same link, which is a real request to open it
/// again.
class ColdStartLinkEcho {
  bool _streamStarted = false;
  Uri? _firstStreamLink;
  Uri? _initialEcho;

  /// Whether a link from the plugin's stream should be handled.
  bool acceptStream(Uri uri) {
    if (_streamStarted) return true;
    _streamStarted = true;
    if (uri == _initialEcho) {
      _initialEcho = null;
      return false;
    }
    _firstStreamLink = uri;
    return true;
  }

  /// Whether the plugin's initial link should be handled.
  bool acceptInitial(Uri uri) {
    if (_streamStarted) {
      final echo = uri == _firstStreamLink;
      _firstStreamLink = null;
      return !echo;
    }
    _initialEcho = uri;
    return true;
  }
}
