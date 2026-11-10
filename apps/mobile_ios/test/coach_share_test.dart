// ignore_for_file: avoid_relative_lib_imports
// Mirrors apps/web/src/lib/social/coach_share.test.ts case-for-case.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/coach_share.dart';

String _migration() {
  final file = Directory('../backend/supabase/migrations')
      .listSync()
      .whereType<File>()
      .firstWhere((f) => f.path.endsWith('_dm_coach_share.sql'));
  return file.readAsStringSync();
}

const _p = SharedSpanStyle.plain;

void main() {
  test('the cap is the one share_coach_message enforces', () {
    final m = RegExp(r'char_length\(v_body\) > (\d+)').firstMatch(_migration());
    expect(m, isNotNull, reason: 'the excerpt cap was not found in the migration — re-anchor');
    expect(kCoachShareMaxChars, int.parse(m!.group(1)!));
  });

  test('the split is the one private.coach_answer_paragraphs uses', () {
    final sql = _migration();
    expect(sql.contains(r"E'\n[ \t]*\n'"), isTrue, reason: 'the split pattern moved — re-anchor');
    expect(sql.contains(r"E' \t\n\r'"), isTrue, reason: 'the trimmed characters moved — re-anchor');
  });

  test('splits on blank lines, trims, drops empty paragraphs (shared with coach_share_test.sql)', () {
    expect(
      coachAnswerParagraphs('First para.\n\n\n  Second\nline  \n \t\nThird\r\n\r\nFourth\n\n'),
      ['First para.', 'Second\nline', 'Third', 'Fourth'],
    );
    expect(coachAnswerParagraphs(''), isEmpty);
    expect(coachAnswerParagraphs('   \n\n  '), isEmpty);
    expect(coachAnswerParagraphs('One'), ['One']);
  });

  test('the excerpt keeps answer order, drops repeats and out-of-range picks', () {
    const p = ['a', 'b', 'c'];
    expect(coachShareExcerpt(p, [2, 0, 2]), 'a\n\nc');
    expect(coachShareExcerpt(p, [-1, 3]), '');
    expect(coachShareExcerpt(p, [1]), 'b');
  });

  test('an unknown kind is drawn as text', () {
    expect(parseDmKind('coach_share'), 'coach_share');
    expect(parseDmKind('text'), 'text');
    expect(parseDmKind('ai_assisted'), 'ai_assisted');
    expect(parseDmKind('ai_reply'), 'text');
    expect(parseDmKind(null), 'text');
  });

  test('inline marks become styled spans and a link keeps only its text', () {
    expect(parseSharedInline('Run **easy**, *slow* and `5x1k` — see [plan](/plans/x)'), const [
      SharedSpan('Run ', _p),
      SharedSpan('easy', SharedSpanStyle.bold),
      SharedSpan(', ', _p),
      SharedSpan('slow', SharedSpanStyle.italic),
      SharedSpan(' and ', _p),
      SharedSpan('5x1k', SharedSpanStyle.code),
      SharedSpan(' — see plan', _p),
    ]);
  });

  test('unclosed marks and markup stay literal text', () {
    expect(parseSharedInline('**open and * star'), const [SharedSpan('**open and * star', _p)]);
    expect(parseSharedInline('<img src=x onerror=alert(1)>'),
        const [SharedSpan('<img src=x onerror=alert(1)>', _p)]);
    expect(parseSharedInline('[js](javascript:alert(1))'), const [SharedSpan('js)', _p)]);
  });

  test('blocks: headings, bullets, numbered items and paragraphs with their line breaks', () {
    expect(
      parseSharedMarkdown('## This week\nKeep it easy\nand short.\n\n- Mon: rest\n* Tue: 5 km\n2) Long run\n> quoted'),
      const [
        SharedBlock(SharedBlockType.heading, [SharedSpan('This week', _p)]),
        SharedBlock(SharedBlockType.paragraph, [SharedSpan('Keep it easy\nand short.', _p)]),
        SharedBlock(SharedBlockType.bullet, [SharedSpan('Mon: rest', _p)]),
        SharedBlock(SharedBlockType.bullet, [SharedSpan('Tue: 5 km', _p)]),
        SharedBlock(SharedBlockType.ordered, [SharedSpan('Long run', _p)], marker: '2.'),
        SharedBlock(SharedBlockType.paragraph, [SharedSpan('quoted', _p)]),
      ],
    );
    expect(parseSharedMarkdown(''), isEmpty);
  });
}
