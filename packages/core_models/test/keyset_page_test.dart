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

/// A fake PostgREST over `table()` — read on every call, so a test can change
/// the table mid-walk — that runs the walk's filter through the evaluator,
/// sorts by `keys`, and answers at most `cap` rows however many were asked
/// for. `beforeRead(n)` runs before the n-th read (0-based).
class _WalkServer {
  _WalkServer(this.keys, this.table, {this.cap, this.beforeRead});

  final List<KeysetKey> keys;
  final List<Row> Function() table;
  final int? cap;
  final void Function(int n)? beforeRead;
  final List<({String? after, int limit})> calls = [];

  Future<List<Row>> fetchPage(String? after, int limit) async {
    beforeRead?.call(calls.length);
    calls.add((after: after, limit: limit));
    final admitted =
        table().where((r) => after == null || _selects(after, r)).toList();
    final take = cap == null || cap! > limit ? limit : cap!;
    return _sortRows(keys, admitted).take(take).toList();
  }
}

/// The OFFSET walk `walkKeyset` replaced, for contrast: `mutate(n)` runs
/// before the n-th read.
List<Row> _offsetWalk(
  List<KeysetKey> keys,
  List<Row> Function() table,
  void Function(int n) mutate,
) {
  final out = <Row>[];
  for (var from = 0, n = 0;; from += 2, n++) {
    mutate(n);
    final page = _sortRows(keys, table()).skip(from).take(2).toList();
    out.addAll(page);
    if (page.length < 2) return out;
  }
}

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

  // ── walkKeyset ───────────────────────────────────────────────────────────

  final walkKeys = orders['at desc nulls last']!;

  test('walkKeyset: every row once, in order, across pages', () async {
    for (final keys in orders.values) {
      final server = _WalkServer(keys, () => _data);
      final rows = await walkKeyset(keys, server.fetchPage, pageSize: 2);
      expect(_ids(rows), _ids(_sortRows(keys, _data)));
    }
  });

  test(
      'walkKeyset: a row deleted mid-walk does not make the walk skip another, '
      'as an offset walk does', () async {
    // The data-loss bug: a backup pages runs by OFFSET, the runner deletes a
    // run the walk already passed, every later run moves up one position, and
    // the next OFFSET starts a row late — one run is never archived.
    final sorted = _sortRows(walkKeys, _data);
    var table = _data;
    void deleteFirst(int n) {
      if (n == 1) table = table.where((r) => r['id'] != sorted[0]['id']).toList();
    }

    final server = _WalkServer(walkKeys, () => table, beforeRead: deleteFirst);
    final rows = await walkKeyset(walkKeys, server.fetchPage, pageSize: 2);
    expect(_ids(rows), _ids(sorted));

    table = _data;
    final offsetRows = _offsetWalk(walkKeys, () => table, deleteFirst);
    expect(_ids(offsetRows), isNot(contains(sorted[2]['id'])));
  });

  test(
      'walkKeyset: a row inserted mid-walk behind the cursor repeats nothing, '
      'as an offset walk does', () async {
    final sorted = _sortRows(walkKeys, _data);
    var table = _data;
    void insert(int n) {
      if (n == 1) {
        table = <Row>[
          {'at': '2026-02-01T00:00:00+00:00', 'id': 'z'},
          ..._data,
        ];
      }
    }

    final server = _WalkServer(walkKeys, () => table, beforeRead: insert);
    final rows = await walkKeyset(walkKeys, server.fetchPage, pageSize: 2);
    expect(_ids(rows), _ids(sorted));

    table = _data;
    final offsetRows = _offsetWalk(walkKeys, () => table, insert);
    expect(_ids(offsetRows).where((id) => id == sorted[1]['id']).length, 2);
  });

  test('walkKeyset: a server capping below the page size is not read as '
      'exhausted', () async {
    final server = _WalkServer(walkKeys, () => _data, cap: 2);
    final rows = await walkKeyset(walkKeys, server.fetchPage, pageSize: 5);
    expect(_ids(rows), _ids(_sortRows(walkKeys, _data)));
  });

  test('walkKeyset: a short first page costs one confirming read; a full last '
      'page one empty read', () async {
    final short = _WalkServer(walkKeys, () => _data);
    expect(
        (await walkKeyset(walkKeys, short.fetchPage, pageSize: 10)).length, 7);
    expect(short.calls.length, 2);
    expect(short.calls[0].after, isNull, reason: 'the first page is unfiltered');

    final exact = _WalkServer(walkKeys, () => _data.sublist(0, 6));
    expect(
        (await walkKeyset(walkKeys, exact.fetchPage, pageSize: 3)).length, 6);
    expect(exact.calls.length, 3);

    final empty = _WalkServer(walkKeys, () => <Row>[]);
    expect(await walkKeyset(walkKeys, empty.fetchPage), isEmpty);
    expect(empty.calls[0].limit, 1000);
  });

  test('walkKeyset: a page error propagates — a partial archive must never '
      'read as complete', () async {
    final server = _WalkServer(walkKeys, () => _data);
    var n = 0;
    Future<List<Row>> failSecond(String? after, int limit) {
      if (n++ == 0) return server.fetchPage(after, limit);
      throw StateError('reset');
    }

    await expectLater(
      walkKeyset(walkKeys, failSecond, pageSize: 2),
      throwsA(isA<StateError>()),
    );
  });

  test('walkKeyset: a server that ignores the filter stops instead of looping',
      () async {
    final first = _sortRows(walkKeys, _data).take(2).toList();
    await expectLater(
      walkKeyset(walkKeys, (after, limit) async => first, pageSize: 2),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('stopped advancing'),
        ),
      ),
    );
  });

  test('walkKeyset: a start cursor walks only the rows after it', () async {
    final sorted = _sortRows(walkKeys, _data);
    final server = _WalkServer(walkKeys, () => _data);
    final rows = await walkKeyset(
      walkKeys,
      server.fetchPage,
      pageSize: 2,
      start: keysetCursor(walkKeys, sorted[2]),
    );
    expect(_ids(rows), _ids(sorted.sublist(3)));
  });

  test('walkKeyset: a non-positive page size is refused', () async {
    final server = _WalkServer(walkKeys, () => _data);
    await expectLater(
      walkKeyset(walkKeys, server.fetchPage, pageSize: 0),
      throwsArgumentError,
    );
  });

  // ── literalSubstringPattern ──────────────────────────────────────────────
  // The pattern goes to Postgres `~*`. For the metacharacters escaped here a
  // Dart RegExp reads `\<char>` exactly as a Postgres advanced regex does
  // (that character, literally), so a case-insensitive RegExp stands in for
  // the server below.

  const tricky = [
    '5*5',
    '100%',
    'a_b',
    r'c:\dir',
    'x,y',
    'f(1)',
    'a.b',
    '"q"',
    "it's",
    '[a]',
    '{2}',
    'a|b',
    r'^$',
    'a+?',
    '***',
  ];

  RegExp literal(String text) =>
      RegExp(literalSubstringPattern(text), caseSensitive: false);

  test('every character of the query matches literally, anywhere in the name', () {
    for (final text in tricky) {
      expect(
        literal(text).hasMatch('Route ${text.toUpperCase()} loop'),
        isTrue,
        reason: '$text must match itself',
      );
    }
  });

  test('a wildcard-looking character matches only itself', () {
    const miss = [
      ['5*5', '5555'],
      ['5*5', '55'],
      ['a_b', 'axb'],
      ['a.b', 'axb'],
      ['100%', '1000'],
      [r'c:\dir', 'c:dir'],
      ['a|b', 'b'],
      ['a+?', 'aa'],
      ['[a]', 'a'],
      ['{2}', 'x'],
    ];
    for (final [text, name] in miss) {
      expect(literal(text).hasMatch(name), isFalse,
          reason: '$text must not match $name');
    }
  });

  test('the regex metacharacters are escaped and nothing else is', () {
    expect(literalSubstringPattern('5*5'), r'5\*5');
    expect(
      literalSubstringPattern(r'\^$.|?*+()[]{}'),
      r'\\\^\$\.\|\?\*\+\(\)\[\]\{\}',
    );
    expect(
      literalSubstringPattern('100% a_b, "q" it\'s -#éß'),
      '100% a_b, "q" it\'s -#éß',
    );
  });

  // ── literalSubstringTerm ─────────────────────────────────────────────────
  // A faithful model of how PostgREST reads the filters of a flat `or=(…)`
  // body: `pLogicSingleVal` (ApiRequest/QueryParams.hs) tries a double-quoted
  // value first — `\` escapes the next character, and the closing quote must
  // be followed by `,` or `)` — and otherwise takes everything up to the next
  // `,` or `)`. A `)` before the end of the body closes the tree, so it is an
  // error here. Returns each filter as [column, operator, value].

  const delimiters = [
    ...tricky,
    ',',
    '(',
    ')',
    '.',
    '"',
    r'\',
    '*',
    '%',
    '_',
    r',()."\*%_',
    'a"),b.eq.(',
    r'\"',
    '{x}',
  ];

  test(
    'a substring term survives every logic-tree delimiter and matches literally',
    () {
      for (final text in delimiters) {
        final body = [
          literalSubstringTerm('name', text),
          literalSubstringTerm('location_label', text),
        ].join(',');
        final filters = _parseOrBody(body);
        expect(
          filters.map((f) => [f[0], f[1]]).toList(),
          [
            ['name', 'imatch'],
            ['location_label', 'imatch'],
          ],
          reason: '$text must stay two filters',
        );
        for (final f in filters) {
          expect(f[2], literalSubstringPattern(text),
              reason: '$text must reach the server unchanged');
          expect(
            RegExp(f[2], caseSensitive: false)
                .hasMatch('Club ${text.toUpperCase()}!'),
            isTrue,
            reason: '$text must match itself',
          );
        }
      }
      expect(
        () => literalSubstringTerm('name,x', 'a'),
        throwsA(isA<ArgumentError>()),
      );
    },
  );

  test('the raw interpolation club search used is not the filter it meant', () {
    // What browseClubs sent before: the term unquoted inside the tree.
    String raw(String t) => 'name.ilike.%$t%,location_label.ilike.%$t%';
    expect(
      () => _parseOrBody(raw('x,y')),
      throwsA(predicate((e) => '$e'.contains('not a filter'))),
    );
    expect(
      () => _parseOrBody(raw('f(1)')),
      throwsA(predicate((e) => '$e'.contains('closes early'))),
    );
    expect(_parseOrBody(raw('5k')), [
      ['name', 'ilike', '%5k%'],
      ['location_label', 'ilike', '%5k%'],
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

List<List<String>> _parseOrBody(String body) {
  final out = <List<String>>[];
  final head = RegExp(r'^([a-z_][a-z0-9_]*)\.([a-z]+)\.');
  var i = 0;
  for (;;) {
    final m = head.firstMatch(body.substring(i));
    if (m == null) throw StateError('not a filter at $i: ${body.substring(i)}');
    i += m[0]!.length;
    var value = '';
    var quoted = false;
    if (i < body.length && body[i] == '"') {
      final buf = StringBuffer();
      var j = i + 1;
      while (j < body.length && body[j] != '"') {
        if (body[j] == r'\') j++;
        if (j < body.length) buf.write(body[j]);
        j++;
      }
      if (j < body.length &&
          (j + 1 == body.length || body[j + 1] == ',' || body[j + 1] == ')')) {
        value = buf.toString();
        i = j + 1;
        quoted = true;
      }
    }
    if (!quoted) {
      var j = i;
      while (j < body.length && body[j] != ',' && body[j] != ')') {
        j++;
      }
      value = body.substring(i, j);
      i = j;
    }
    out.add([m[1]!, m[2]!, value]);
    if (i == body.length) return out;
    if (body[i] != ',') throw StateError('the tree closes early at $i: $body');
    i++;
  }
}
