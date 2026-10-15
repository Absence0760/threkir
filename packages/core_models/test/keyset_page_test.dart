import 'package:core_models/core_models.dart';
import 'package:test/test.dart';

// Mirror of apps/web/src/lib/core/keyset_page.test.ts — keep in lockstep.

// ── A tiny evaluator for the filter grammar keysetAfter emits ──────────────
// Enough of PostgREST's logic tree to run a filter against in-memory rows, so
// the suite asserts what the filter SELECTS rather than only how it is spelt.

typedef Row = Map<String, dynamic>;

List<String> _splitTop(String s) {
  final parts = <String>[];
  var depth = 0;
  var quoted = false;
  var start = 0;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (quoted) {
      if (c == r'\') {
        i++;
      } else if (c == '"') {
        quoted = false;
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == '(') {
      depth++;
    } else if (c == ')') {
      depth--;
    } else if (c == ',' && depth == 0) {
      parts.add(s.substring(start, i));
      start = i + 1;
    }
  }
  parts.add(s.substring(start));
  return parts;
}

String _unquote(String v) {
  expect(
    v.startsWith('"') && v.endsWith('"'),
    isTrue,
    reason: 'unquoted literal $v',
  );
  return v
      .substring(1, v.length - 1)
      .replaceAllMapped(RegExp(r'\\(.)'), (m) => m.group(1)!);
}

int _compareValues(Object a, String b) {
  if (a is num) return (a - num.parse(b)).sign.toInt();
  return a.toString().compareTo(b).sign;
}

bool _matches(String term, Row row) {
  for (final op in ['and', 'or']) {
    if (term.startsWith('$op(')) {
      final inner = _splitTop(term.substring(op.length + 1, term.length - 1));
      return op == 'and'
          ? inner.every((t) => _matches(t, row))
          : inner.any((t) => _matches(t, row));
    }
  }
  final dot = term.indexOf('.');
  final col = term.substring(0, dot);
  final tail = term.substring(dot + 1);
  final v = row[col];
  if (tail == 'is.null') return v == null;
  if (tail == 'not.is.null') return v != null;
  final op = tail.substring(0, 2);
  final lit = _unquote(tail.substring(3));
  if (v == null) return false;
  final cmp = _compareValues(v as Object, lit);
  if (op == 'eq') return cmp == 0;
  if (op == 'gt') return cmp > 0;
  if (op == 'lt') return cmp < 0;
  throw StateError('unknown op in $term');
}

bool _selects(String? filter, Row row) =>
    filter != null && _splitTop(filter).any((t) => _matches(t, row));

/// Postgres's ORDER BY for `keys`, null placement included.
List<Row> _sortRows(List<KeysetKey> keys, List<Row> rows) {
  final out = [...rows];
  out.sort((a, b) {
    for (final k in keys) {
      final x = a[k.column];
      final y = b[k.column];
      if (x == null && y == null) continue;
      if (x == null) return k.nullsFirst ? -1 : 1;
      if (y == null) return k.nullsFirst ? 1 : -1;
      final c = _compareValues(x as Object, y.toString());
      if (c != 0) return k.ascending ? c : -c;
    }
    return 0;
  });
  return out;
}

/// One keyset read: the first `limit` rows after `cursor` in the order.
List<Row> _readPage(
  List<KeysetKey> keys,
  List<Row> rows,
  List<Object?>? cursor,
  int limit,
) {
  final filter = cursor == null ? null : keysetAfter(keys, cursor);
  if (cursor != null && filter == null) return [];
  return _sortRows(
    keys,
    rows.where((r) => cursor == null || _selects(filter, r)).toList(),
  ).take(limit).toList();
}

// Ties on the leading key and nulls in it, so every arm of the expansion runs.
final List<Row> _data = [
  {'at': '2026-01-03T00:00:00.000001+00:00', 'id': 'a'},
  {'at': '2026-01-02T00:00:00+00:00', 'id': 'b'},
  {'at': '2026-01-02T00:00:00+00:00', 'id': 'c'},
  {'at': null, 'id': 'd'},
  {'at': '2026-01-01T00:00:00+00:00', 'id': 'e'},
  {'at': null, 'id': 'f'},
  {'at': '2026-01-02T00:00:00+00:00', 'id': 'g'},
];

Map<String, List<KeysetKey>> _orders() {
  final out = <String, List<KeysetKey>>{};
  for (final ascending in [true, false]) {
    for (final nullsFirst in [true, false]) {
      out['at ${ascending ? 'asc' : 'desc'} nulls ${nullsFirst ? 'first' : 'last'}'] =
          [
            KeysetKey('at', ascending: ascending, nullsFirst: nullsFirst),
            KeysetKey('id', ascending: !ascending, nullsFirst: false),
          ];
    }
  }
  return out;
}

List<Object?> _ids(List<Row> rows) => rows.map((r) => r['id']).toList();

void main() {
  final orders = _orders();

  for (final entry in orders.entries) {
    final name = entry.key;
    final keys = entry.value;

    test('$name: after any row selects exactly the rows behind it', () {
      final sorted = _sortRows(keys, _data);
      for (var i = 0; i < sorted.length; i++) {
        final filter = keysetAfter(keys, keysetCursor(keys, sorted[i]));
        final got = sorted.where((r) => _selects(filter, r)).toList();
        expect(
          _ids(got),
          _ids(sorted.sublist(i + 1)),
          reason: 'after ${sorted[i]['id']}',
        );
      }
    });

    test('$name: walking pages of 2 visits every row once', () {
      final seen = <Object?>[];
      List<Object?>? cursor;
      for (var guard = 0; guard < 10; guard++) {
        final page = _readPage(keys, _data, cursor, 2);
        seen.addAll(_ids(page));
        final next = nextCursor(keys, page, 2);
        if (next == null) break;
        cursor = next;
      }
      expect(seen, _ids(_sortRows(keys, _data)));
    });
  }

  test('a row deleted from page 1 does not make page 2 skip one, as an offset does', () {
    // The bug this module exists for. Newest-first, page size 2: page 1 is
    // a, then the b/c/g tie broken by id. Deleting page 1's first row before
    // "load more" shifts every position down by one, so OFFSET 2 starts a row
    // late and the row that was third is never shown; the cursor still names
    // the last row shown.
    final keys = orders['at desc nulls last']!;
    final sorted = _sortRows(keys, _data);
    final page1 = _readPage(keys, _data, null, 2);
    final after = _data.where((r) => r['id'] != page1[0]['id']).toList();
    final page2 = _readPage(keys, after, keysetCursor(keys, page1[1]), 2);
    expect(_ids(page2), _ids(sorted.sublist(2, 4)));
    final offsetPage2 = _sortRows(keys, after).sublist(2, 4);
    expect(_ids(offsetPage2), isNot(_ids(page2)));
  });

  test('a row inserted above the boundary is not repeated on page 2', () {
    final keys = orders['at desc nulls last']!;
    final page1 = _readPage(keys, _data, null, 2);
    final grown = <Row>[
      {'at': '2026-02-01T00:00:00+00:00', 'id': 'z'},
      ..._data,
    ];
    final page2 = _readPage(keys, grown, keysetCursor(keys, page1[1]), 2);
    expect(page2.any((r) => page1.any((p) => p['id'] == r['id'])), isFalse);
  });

  test(
    'the filter spells a two-key descending order the way the feed cursor does',
    () {
      const keys = [
        KeysetKey('started_at', ascending: false, nullsFirst: true),
        KeysetKey('id', ascending: false, nullsFirst: true),
      ];
      expect(
        keysetAfter(keys, ['2026-01-01T10:00:00.5+00:00', 'r1']),
        'started_at.lt."2026-01-01T10:00:00.5+00:00",'
        'and(started_at.eq."2026-01-01T10:00:00.5+00:00",id.lt."r1")',
      );
    },
  );

  test('a nulls-last key admits the nulls behind a non-null cursor', () {
    const keys = [
      KeysetKey('joined_at', ascending: true, nullsFirst: false),
      KeysetKey('user_id', ascending: true, nullsFirst: false),
    ];
    expect(
      keysetAfter(keys, ['2026-01-01', 'u1']),
      'or(joined_at.gt."2026-01-01",joined_at.is.null),'
      'and(joined_at.eq."2026-01-01",or(user_id.gt."u1",user_id.is.null))',
    );
    expect(
      keysetAfter(keys, [null, 'u1']),
      'and(joined_at.is.null,or(user_id.gt."u1",user_id.is.null))',
    );
  });

  test('a null cursor on a nulls-first key is followed by every non-null', () {
    expect(
      keysetAfter(
        const [KeysetKey('featured_at', ascending: false, nullsFirst: true)],
        [null],
      ),
      'featured_at.not.is.null',
    );
  });

  test('nothing can follow a null on a nulls-last final key', () {
    expect(
      keysetAfter(
        const [KeysetKey('x', ascending: true, nullsFirst: false)],
        [null],
      ),
      isNull,
    );
  });

  test(
    'literals are quoted and escaped; numbers and booleans are stringified',
    () {
      KeysetKey k(String column) =>
          KeysetKey(column, ascending: true, nullsFirst: true);
      expect(keysetAfter([k('name')], [r'a"b\c']), r'name.gt."a\"b\\c"');
      expect(keysetAfter([k('run_count')], [5]), 'run_count.gt."5"');
      expect(keysetAfter([k('flag')], [false]), 'flag.gt."false"');
    },
  );

  test(
    'a malformed order or cursor throws rather than reading the wrong page',
    () {
      const k = KeysetKey('id', ascending: true, nullsFirst: true);
      expect(() => keysetAfter(const [], const []), throwsArgumentError);
      expect(
        () => keysetAfter(const [k], const ['a', 'b']),
        throwsArgumentError,
      );
      expect(
        () => keysetAfter(
          const [KeysetKey('id,x', ascending: true, nullsFirst: true)],
          const ['a'],
        ),
        throwsArgumentError,
      );
      expect(() => keysetAfter(const [k], [double.nan]), throwsArgumentError);
      expect(() => keysetCursor(const [k], {'other': 1}), throwsArgumentError);
      expect(
        () => keysetCursor(
          const [k],
          {
            'id': {'nested': true},
          },
        ),
        throwsArgumentError,
      );
    },
  );

  test('nextCursor ends the list on a short page and continues from the last row of a full one', () {
    const keys = [KeysetKey('id', ascending: true, nullsFirst: true)];
    expect(
      nextCursor(keys, [
        {'id': 'a'},
      ], 2),
      isNull,
    );
    expect(nextCursor(keys, const [], 2), isNull);
    expect(
      nextCursor(keys, [
        {'id': 'a'},
        {'id': 'b'},
      ], 2),
      ['b'],
    );
  });

  test('the public-route orders keep the RPC prefix and end on id', () {
    List<String> spell(String sort) => publicRouteOrder(sort)
        .map(
          (k) =>
              '${k.column} ${k.ascending ? 'asc' : 'desc'} nulls ${k.nullsFirst ? 'first' : 'last'}',
        )
        .toList();
    expect(spell('newest'), [
      'created_at desc nulls last',
      'id desc nulls last',
    ]);
    expect(spell('popular'), [
      'run_count desc nulls last',
      'created_at desc nulls first',
      'id desc nulls last',
    ]);
    expect(spell('featured'), [
      'featured_at desc nulls last',
      'created_at desc nulls first',
      'id desc nulls last',
    ]);
  });

  // ── appendPage ───────────────────────────────────────────────────────────

  String id(Map<String, Object> r) => r['id']! as String;
  List<Map<String, Object>> rows(List<String> ids) =>
      ids.map((i) => <String, Object>{'id': i}).toList();

  test('a row that moved past the cursor between reads is not repeated', () {
    // A public route whose run_count dropped re-sorts below the cursor of a
    // "popular" list, so the keyset page after the cursor returns it again.
    final merged = appendPage(rows(['m1', 'm2']), rows(['m3', 'm1']), id);
    expect(merged.map(id).toList(), ['m1', 'm2', 'm3']);
  });

  test('a page with no overlap appends in order', () {
    expect(
      appendPage(rows(['a', 'b']), rows(['c', 'd']), id).map(id).toList(),
      ['a', 'b', 'c', 'd'],
    );
  });

  test('the row already shown keeps its place and its value', () {
    final shown = [
      <String, Object>{'id': 'a', 'v': 1},
    ];
    final merged = appendPage(shown, [
      <String, Object>{'id': 'a', 'v': 2},
      <String, Object>{'id': 'b', 'v': 3},
    ], id);
    expect(merged, [
      {'id': 'a', 'v': 1},
      {'id': 'b', 'v': 3},
    ]);
  });

  test('duplicates inside one page collapse too', () {
    expect(
      appendPage(
        <Map<String, Object>>[],
        rows(['a', 'a', 'b']),
        id,
      ).map(id).toList(),
      ['a', 'b'],
    );
  });

  test('the shown list is not mutated', () {
    final shown = rows(['a']);
    appendPage(shown, rows(['b']), id);
    expect(shown.map(id).toList(), ['a']);
  });
}
