import 'package:flutter_test/flutter_test.dart';

import '../lib/loggable_message.dart';

void main() {
  test('a quoted value is blanked', () {
    expect(
      loggableMessage('invalid input syntax for type uuid: "a-runner-typed-this"'),
      'invalid input syntax for type uuid: "…"',
    );
    expect(loggableMessage("submit_report: target 'run' x not found"),
        "submit_report: target '…' x not found");
  });

  test('a key detail is blanked', () {
    expect(
      loggableMessage('Key (email)=(runner@example.com) already exists.'),
      'Key (…)=(…) already exists.',
    );
  });

  test('an email address is blanked', () {
    expect(loggableMessage('no account for runner@example.com'),
        'no account for <email>');
  });

  test('a long message is cut to the cap and says so', () {
    final long = loggableMessage('x' * 500);
    expect(long.length, loggedMessageMaxChars);
    expect(long.endsWith('…'), isTrue);
    expect(loggableMessage('x' * loggedMessageMaxChars),
        'x' * loggedMessageMaxChars);
  });

  test('text with nothing to blank passes through', () {
    expect(loggableMessage('Failed to fetch'), 'Failed to fetch');
  });
}
