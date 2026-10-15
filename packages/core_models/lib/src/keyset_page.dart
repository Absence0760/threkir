// Keyset ("cursor") pagination for the load-more lists.
//
// Pure Dart — mirrors apps/web/src/lib/core/keyset_page.ts (registered in
// docs/architecture/parity_pairs.md); keep the two in lockstep.
//
// An OFFSET names a position, and a position moves whenever the list changes
// between two reads: delete a row from page 1 and offset 50 now starts at what
// was row 51, so row 50 is never shown; insert one above the boundary and the
// last row of page 1 comes back on page 2. A keyset names the last ROW shown —
// its sort values, ending on a unique column so the order is total — and asks
// for the rows strictly after it, which no insert or delete elsewhere in the
// list can move.

/// One column of a total order, spelled exactly as the `.order()` call that
/// sorts by it. `nullsFirst` is required rather than defaulted because the two
/// clients default it differently (postgrest-dart always sends nullslast;
/// postgrest-js omits it and Postgres puts nulls first on a descending key),
/// so a key spec that left it out would mean two different orders.
class KeysetKey {
  const KeysetKey(
    this.column, {
    required this.ascending,
    required this.nullsFirst,
  });

  final String column;
  final bool ascending;
  final bool nullsFirst;
}

/// One load-more page: the rows to show, and the cursor for the next read —
/// null when the server returned a short page, i.e. the list is exhausted.
/// `next` comes from the last row the SERVER returned, not the last row
/// rendered, so a row the caller drops after the read (a follower whose
/// profile is gone) neither ends the list early nor shifts the next page.
class KeysetPage<T> {
  const KeysetPage(this.rows, this.next);

  final List<T> rows;

  /// The last row's value for each key of the order, in key order.
  final List<Object?>? next;
}

final RegExp _column = RegExp(r'^[a-z_][a-z0-9_]*$');

String _checkColumn(String column) {
  if (!_column.hasMatch(column)) {
    throw ArgumentError('keyset: not a plain column name: $column');
  }
  return column;
}

/// A PostgREST literal, always double-quoted: a timestamp carries `:` and `.`,
/// both reserved inside a logic tree, and quoting every value is simpler than
/// deciding which need it. A whole double prints without `.0`, as JS's
/// `String(5)` does.
String _literal(Object value) {
  String text;
  if (value is num) {
    if (!value.isFinite)
      throw ArgumentError('keyset: not a finite number: $value');
    text = value is double && value == value.truncateToDouble()
        ? value.toInt().toString()
        : value.toString();
  } else if (value is String || value is bool) {
    text = value.toString();
  } else {
    throw ArgumentError('keyset: not a scalar: $value');
  }
  return '"${text.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
}

String _equalTerm(KeysetKey key, Object? value) {
  final col = _checkColumn(key.column);
  return value == null ? '$col.is.null' : '$col.eq.${_literal(value)}';
}

/// Rows whose `key` sorts strictly after `value`, or null when none can.
String? _afterTerm(KeysetKey key, Object? value) {
  final col = _checkColumn(key.column);
  if (value == null) return key.nullsFirst ? '$col.not.is.null' : null;
  final strict = '$col.${key.ascending ? 'gt' : 'lt'}.${_literal(value)}';
  return key.nullsFirst ? strict : 'or($strict,$col.is.null)';
}

/// The filter for "strictly after `cursor` in the order `keys`", as the body
/// of a PostgREST `.or(...)`: the row-value comparison
/// `(k1, k2, …) > (c1, c2, …)` expanded into "k1 after c1, or k1 equal and k2
/// after c2, or …", with each key's direction and null placement honoured.
/// Null when no row can follow the cursor, which the caller answers with an
/// empty page rather than an unfiltered read.
String? keysetAfter(List<KeysetKey> keys, List<Object?> cursor) {
  if (keys.isEmpty)
    throw ArgumentError('keyset: an order needs at least one key');
  if (cursor.length != keys.length) {
    throw ArgumentError(
      'keyset: cursor has ${cursor.length} values for ${keys.length} keys',
    );
  }
  final alternatives = <String>[];
  for (var i = 0; i < keys.length; i++) {
    final after = _afterTerm(keys[i], cursor[i]);
    if (after == null) continue;
    final terms = [
      for (var j = 0; j < i; j++) _equalTerm(keys[j], cursor[j]),
      after,
    ];
    alternatives.add(
      terms.length == 1 ? terms.first : 'and(${terms.join(',')})',
    );
  }
  return alternatives.isEmpty ? null : alternatives.join(',');
}

/// The cursor for `row`: its value for each key, read as the server sent it.
/// A timestamp must stay the server's string — re-serialising it through
/// `DateTime` drops the microseconds' formatting and the zone, and the
/// equality arm then matches nothing.
List<Object?> keysetCursor(List<KeysetKey> keys, Map<String, dynamic> row) {
  return [
    for (final k in keys)
      () {
        if (!row.containsKey(k.column)) {
          throw ArgumentError('keyset: row has no ${k.column}');
        }
        final value = row[k.column];
        if (value != null &&
            value is! String &&
            value is! num &&
            value is! bool) {
          throw ArgumentError('keyset: ${k.column} is not a scalar');
        }
        return value;
      }(),
  ];
}

/// The next cursor after a raw server page of `limit` rows: the last row's
/// cursor when the page was full, null when it was short.
List<Object?>? nextCursor(
  List<KeysetKey> keys,
  List<Map<String, dynamic>> page,
  int limit,
) {
  if (page.length < limit || page.isEmpty) return null;
  return keysetCursor(keys, page.last);
}

/// `shown` followed by the rows of `page` not already in it, compared on
/// `keyOf`; the row already on screen keeps its place.
///
/// Keyset paging makes the boundary overlap of an offset impossible, so this
/// is no longer what stops a repeat on an ordinary insert. It stays because a
/// row can still MOVE past the cursor between two reads when its own sort
/// value changes: a public route whose `run_count` drops re-sorts below the
/// cursor of a "popular" list. Appended blindly, that row renders twice. (A
/// follow undone and redone between reads cannot: the new edge sorts to the
/// TOP of a newest-first list, before the cursor.)
List<T> appendPage<T>(
  List<T> shown,
  List<T> page,
  String Function(T row) keyOf,
) {
  final seen = shown.map(keyOf).toSet();
  final out = [...shown];
  for (final row in page) {
    if (seen.add(keyOf(row))) out.add(row);
  }
  return out;
}

/// A pattern for PostgREST's `imatch` operator (Postgres `~*`, read through
/// postgrest-dart `imatchRegex`) that matches `text` as a case-insensitive
/// substring, every character literally.
///
/// Not `ilike`: PostgREST rewrites EVERY `*` in a like/ilike value to `%`
/// before Postgres sees it (`star` in PostgREST's `pgFmtFilter`), with no
/// escape, so a literal asterisk cannot be expressed in a like pattern at all —
/// and `%`, `_` and `\` are LIKE's own metacharacters on top. `imatch` takes
/// its value verbatim, and in a Postgres advanced regex a backslash before a
/// non-alphanumeric character means that character, so escaping the regex
/// metacharacters is the whole job. `%`, `_`, `,`, quotes and the rest are
/// ordinary in a regex and pass through. A substring regex needs no anchors,
/// and `routes_name_trgm` (gin_trgm_ops) serves `~*` as it served `ilike`.
///
/// For a TOP-LEVEL filter only: inside an `or=`/`and=` tree the value would
/// also need quoting, because `,` `(` `)` are the tree's own delimiters.
String literalSubstringPattern(String text) => text.replaceAllMapped(
  RegExp(r'[\\^$.|?*+()[\]{}]'),
  (m) => '\\${m[0]}',
);

/// The total order of each public-route search sort (`newest` / `popular` /
/// `featured`). The first keys are the dropped `search_public_routes` RPC's
/// (migration 20270326_001), null placement included, so the partial indexes
/// that migration built still serve the prefix; `id` is appended because none
/// of the three was total — two routes created in the same instant could swap
/// between reads.
List<KeysetKey> publicRouteOrder(String sort) {
  const id = KeysetKey('id', ascending: false, nullsFirst: false);
  const createdAt = KeysetKey('created_at', ascending: false, nullsFirst: true);
  switch (sort) {
    case 'popular':
      return const [
        KeysetKey('run_count', ascending: false, nullsFirst: false),
        createdAt,
        id,
      ];
    case 'featured':
      return const [
        KeysetKey('featured_at', ascending: false, nullsFirst: false),
        createdAt,
        id,
      ];
    case 'newest':
      return const [
        KeysetKey('created_at', ascending: false, nullsFirst: false),
        id,
      ];
    default:
      throw ArgumentError('keyset: unknown public-route sort: $sort');
  }
}

/// The size a walk ASKS for: PostgREST's `db.max-rows`. Deliberately not
/// assumed to be the size it gets — see [walkKeyset].
const int kKeysetWalkPageSize = 1000;

bool _sameCursor(List<Object?> a, List<Object?> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Every row [fetchPage] can produce, one keyset page at a time — the walk a
/// backup, an export or a complete list needs, where "every row" is the
/// contract.
///
/// `fetchPage(after, limit)` must apply `after` (a PostgREST `or` body, null
/// on the first page) and sort by exactly [keys], then ask for `limit` rows.
/// Each page starts strictly after the last row the previous one returned, so
/// a row inserted or deleted while the walk runs moves no other row across a
/// page boundary: it is read once or (if it arrived behind the walk) not at
/// all, and every row present for the whole walk is read exactly once. An
/// OFFSET walk names positions instead, so the same delete skips a row and the
/// same insert repeats one.
///
/// **A short page is not proof of exhaustion.** A server whose `db.max-rows`
/// is below [pageSize] answers every page short with a 200, so the walk stops
/// only on an empty page, or on one both short of the ask AND shorter than the
/// page before it — the shape a genuinely exhausted result set has and a
/// consistently-capping one does not. A short first page therefore costs one
/// confirming read.
///
/// Errors propagate: a caller archiving a history would rather fail loudly
/// than write a file that is partial but reads as complete. There is no row
/// ceiling — a ceiling would silently truncate. A server that ignores the
/// window and answers the same page forever is caught by the cursor instead:
/// a page whose last row is the cursor it was asked to pass has not advanced,
/// and the walk throws a [StateError] rather than looping. Mirrors `walkKeyset`
/// in apps/web/src/lib/core/keyset_page.ts, which returns `complete: false`
/// where this throws, per each side's error contract.
Future<List<Map<String, dynamic>>> walkKeyset(
  List<KeysetKey> keys,
  Future<List<Map<String, dynamic>>> Function(String? after, int limit)
      fetchPage, {
  int pageSize = kKeysetWalkPageSize,
  List<Object?>? start,
}) async {
  if (pageSize <= 0) {
    throw ArgumentError.value(
      pageSize,
      'pageSize',
      'keyset: page size must be a positive integer',
    );
  }
  final rows = <Map<String, dynamic>>[];
  var cursor = start;
  int? previous;
  while (true) {
    String? after;
    if (cursor != null) {
      after = keysetAfter(keys, cursor);
      if (after == null) return rows;
    }
    final page = await fetchPage(after, pageSize);
    if (page.isEmpty) return rows;
    final next = keysetCursor(keys, page.last);
    if (cursor != null && _sameCursor(next, cursor)) {
      throw StateError('keyset: the walk stopped advancing');
    }
    rows.addAll(page);
    if (page.length < pageSize && previous != null && page.length < previous) {
      return rows;
    }
    previous = page.length;
    cursor = next;
  }
}
