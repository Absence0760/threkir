/// The text of a failure as it may be logged. `debugPrint` output reaches
/// error reporting as breadcrumbs once a reader has consented to it, and
/// server text can quote the row it refused (`Key (email)=(…)`, `invalid input
/// syntax for type uuid: "…"`). Quoted runs, key/value details and email
/// addresses are blanked and the rest is cut short; the code and the context
/// still say which failure it was.
///
/// Web twin: `apps/web/src/lib/util/loggable_message.ts`.
library;

/// Longest message [loggableMessage] returns.
const int loggedMessageMaxChars = 160;

final RegExp _keyDetail = RegExp(r'\([^()]*\)=\([^()]*\)');
final RegExp _doubleQuoted = RegExp(r'"[^"]*"');
final RegExp _singleQuoted = RegExp(r"'[^']*'");
final RegExp _email = RegExp(r'''[^\s@"'()]+@[^\s@"'()]+''');

String loggableMessage(String message) {
  final cleaned = message
      .replaceAll(_keyDetail, '(…)=(…)')
      .replaceAll(_doubleQuoted, '"…"')
      .replaceAll(_singleQuoted, "'…'")
      .replaceAll(_email, '<email>');
  return cleaned.length > loggedMessageMaxChars
      ? '${cleaned.substring(0, loggedMessageMaxChars - 1)}…'
      : cleaned;
}
