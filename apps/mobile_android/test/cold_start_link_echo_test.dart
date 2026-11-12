// ColdStartLinkEcho drops only app_links' one cold-start echo, in either
// delivery order, and never a later repeat of the same link.

import 'package:flutter_test/flutter_test.dart';

import '../lib/cold_start_link_echo.dart';

void main() {
  final a = Uri.parse('https://threkir.com/runs/a');
  final b = Uri.parse('https://threkir.com/runs/b');

  test('initial first: the stream echo is dropped once', () {
    final echo = ColdStartLinkEcho();
    expect(echo.acceptInitial(a), isTrue);
    expect(echo.acceptStream(a), isFalse);
    expect(echo.acceptStream(a), isTrue);
  });

  test('stream first: the initial echo is dropped once', () {
    final echo = ColdStartLinkEcho();
    expect(echo.acceptStream(a), isTrue);
    expect(echo.acceptInitial(a), isFalse);
    expect(echo.acceptStream(a), isTrue);
  });

  test('a different first stream link is not an echo', () {
    final echo = ColdStartLinkEcho();
    expect(echo.acceptInitial(a), isTrue);
    expect(echo.acceptStream(b), isTrue);
    expect(echo.acceptStream(a), isTrue);
  });

  test('no initial link: every stream link is handled', () {
    final echo = ColdStartLinkEcho();
    expect(echo.acceptStream(a), isTrue);
    expect(echo.acceptStream(a), isTrue);
  });
}
