import 'package:flutter_test/flutter_test.dart';
import '../lib/mentions.dart';

void main() {
  test('parseMentionHandles: lowercases, de-duplicates and keeps first-seen order', () {
    expect(parseMentionHandles('hi @Alice and @bob_1, then @ALICE again'), ['alice', 'bob_1']);
  });

  test('parseMentionHandles: an email address mentions nobody', () {
    expect(parseMentionHandles('mail me@example.com'), isEmpty);
  });

  test('parseMentionHandles: too short, doubled @ and glued handles are not mentions', () {
    expect(parseMentionHandles('@al @@dave @abc@def'), ['abc']);
  });

  test('parseMentionHandles: a 31-character run is not truncated to a handle', () {
    expect(parseMentionHandles('@${'x' * 31} @${'y' * 30}'), ['y' * 30]);
  });

  test('parseMentionHandles: punctuation around a handle is fine', () {
    expect(parseMentionHandles('(@carol), @dan! @erin.'), ['carol', 'dan', 'erin']);
  });

  test('parseMentionHandles: caps at ten handles, matching the server', () {
    final body = List.generate(12, (i) => '@user$i').join(' ');
    expect(parseMentionHandles(body).length, maxMentionsPerComment);
    expect(maxMentionsPerComment, 10);
  });

  test('splitMentions: cuts text and mentions in order and keeps the typed spelling', () {
    expect(splitMentions('go @Ana, go'), const [
      MentionSegment.text('go '),
      MentionSegment.mention('@Ana', 'ana'),
      MentionSegment.text(', go'),
    ]);
  });

  test('splitMentions: a body with no mention is one text segment, an empty body none', () {
    expect(splitMentions('no one here'), const [MentionSegment.text('no one here')]);
    expect(splitMentions(''), isEmpty);
  });

  test('activeMentionQuery: the token under the caret, including a bare @', () {
    expect(activeMentionQuery('hey @Ca', 7), (start: 4, query: 'ca'));
    expect(activeMentionQuery('hey @', 5), (start: 4, query: ''));
  });

  test('activeMentionQuery: none after a space, inside an email, or past the caret', () {
    expect(activeMentionQuery('hey @ca ', 8), isNull);
    expect(activeMentionQuery('me@exa', 6), isNull);
    expect(activeMentionQuery('hey @ca', 3), isNull);
  });

  test('insertMention: replaces the typed prefix and leaves one space after', () {
    expect(insertMention('hey @ca', 4, 7, 'carol'), (text: 'hey @carol ', caret: 11));
    expect(insertMention('hey @ca there', 4, 7, 'carol'), (text: 'hey @carol there', caret: 11));
  });

  test('insertMention: swallows the rest of a half-typed handle after the caret', () {
    expect(insertMention('@caxx', 0, 3, 'carol'), (text: '@carol ', caret: 7));
  });
}
