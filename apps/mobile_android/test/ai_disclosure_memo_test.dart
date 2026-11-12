import 'package:flutter_test/flutter_test.dart';
import '../lib/ai_disclosure.dart';
import '../lib/ai_disclosure_memo.dart';

void main() {
  const granted = AiDisclosureRecord(
    version: 4,
    acceptedAt: '2026-01-01T00:00:00Z',
  );

  setUp(AiDisclosureMemo.forget);

  test('a remembered record is handed back for the same user', () {
    AiDisclosureMemo.remember('u1', granted);
    expect(AiDisclosureMemo.peek('u1'), same(granted));
  });

  test('another user, or no user, gets nothing', () {
    AiDisclosureMemo.remember('u1', granted);
    expect(AiDisclosureMemo.peek('u2'), isNull);
    expect(AiDisclosureMemo.peek(null), isNull);
  });

  test('the latest write wins, including a switch of user', () {
    const older = AiDisclosureRecord(version: 1, acceptedAt: '2025-01-01T00:00:00Z');
    AiDisclosureMemo.remember('u1', older);
    AiDisclosureMemo.remember('u1', granted);
    expect(AiDisclosureMemo.peek('u1'), same(granted));
    AiDisclosureMemo.remember('u2', older);
    expect(AiDisclosureMemo.peek('u1'), isNull);
    expect(AiDisclosureMemo.peek('u2'), same(older));
  });

  test('forget clears it', () {
    AiDisclosureMemo.remember('u1', granted);
    AiDisclosureMemo.forget();
    expect(AiDisclosureMemo.peek('u1'), isNull);
  });
}
