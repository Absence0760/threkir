import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:ui_kit/ui_kit.dart' show ListSkeleton;

import '../audience_level.dart';
import '../auth_error.dart';
import '../l10n/gen/app_localizations.dart';
import 'confirm_destructive.dart';

/// The in-app web link to a run or route: `/runs/{id}` or `/routes/{id}`.
/// Unlike `/share/...`, which serves public rows only, it opens for whoever
/// the owner's audience admits, so it is the link a narrower level hands
/// out. Host from `WEB_BASE_URL`, falling back to the prod site.
String audienceLinkUrl(ShareableKind kind, String id, {String? webBase}) {
  final base = (webBase ??
          (dotenv.isInitialized ? dotenv.maybeGet('WEB_BASE_URL') : null) ??
          'https://threkir.com')
      .trim()
      .replaceAll(RegExp(r'/+$'), '');
  return kind == ShareableKind.run ? '$base/runs/$id' : '$base/routes/$id';
}

/// One person the owner may name on a share.
class AudiencePerson {
  final String id;
  final String? displayName;

  const AudiencePerson({required this.id, this.displayName});
}

/// What the sheet reads and writes, for one run or one route. The production
/// half is [ApiAudienceBackend]; tests hand in a fake.
abstract class AudienceBackend {
  /// The stored columns, or null when the row is not the caller's.
  Future<AudienceColumns?> fetchColumns();
  Future<List<AudiencePerson>> fetchShares();
  Future<List<AudiencePerson>> fetchCandidates();

  /// Store [level]. Only me revokes every grant first ([levelRevokesGrants]).
  Future<void> setLevel(AudienceLevel level);
  Future<void> addShare(String recipientId);
  Future<void> revokeShare(String recipientId);
}

class ApiAudienceBackend implements AudienceBackend {
  final ApiClient api;
  final ShareableKind kind;
  final String id;

  const ApiAudienceBackend(this.api, this.kind, this.id);

  @override
  Future<AudienceColumns?> fetchColumns() async {
    final c = await api.fetchAudienceColumns(kind, id);
    if (c == null) return null;
    return AudienceColumns(
      isPublic: c.isPublic,
      followersOnly: c.followersOnly,
    );
  }

  @override
  Future<List<AudiencePerson>> fetchShares() async => [
    for (final s in await api.fetchShares(kind, id))
      AudiencePerson(id: s.recipientId, displayName: s.displayName),
  ];

  @override
  Future<List<AudiencePerson>> fetchCandidates() async => [
    for (final p in await api.fetchShareCandidates())
      AudiencePerson(id: p.id, displayName: p.displayName),
  ];

  @override
  Future<void> setLevel(AudienceLevel level) {
    final c = audienceColumns(level);
    return api.setAudienceColumns(
      kind,
      id,
      isPublic: c.isPublic,
      followersOnly: c.followersOnly,
      revokeGrants: levelRevokesGrants(level),
    );
  }

  @override
  Future<void> addShare(String recipientId) =>
      api.addShare(kind, id, recipientId);

  @override
  Future<void> revokeShare(String recipientId) =>
      api.revokeShare(kind, id, recipientId);
}

/// How the sheet closed when the owner asked for something the caller does.
enum AudienceSheetResult {
  /// Public was chosen. Making something public goes through the caller's own
  /// privacy-zone confirm, so the sheet hands it back instead of writing it.
  requestPublic,

  /// "Share link" was tapped at a narrower level: hand the in-app link, which
  /// opens only for that audience, to the OS share sheet.
  shareLink,
}

/// "Who can see this" for a run or route the caller owns (decisions
/// § 1874). Four levels, the people a Specific-people share names, and
/// a revoke per person that ends access on their next read.
Future<AudienceSheetResult?> showAudienceSheet(
  BuildContext context, {
  required AudienceBackend backend,
}) {
  return showModalBottomSheet<AudienceSheetResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => AudienceSheet(backend: backend),
  );
}

class AudienceSheet extends StatefulWidget {
  final AudienceBackend backend;

  const AudienceSheet({super.key, required this.backend});

  @override
  State<AudienceSheet> createState() => _AudienceSheetState();
}

class _AudienceSheetState extends State<AudienceSheet> {
  AudienceColumns? _columns;
  bool _columnsLoading = true;
  bool _columnsFailed = false;

  List<AudiencePerson> _shares = const [];
  bool _sharesLoading = true;
  bool _sharesFailed = false;

  List<AudiencePerson> _people = const [];
  bool _peopleLoading = true;
  bool _peopleFailed = false;

  String _query = '';
  bool _busy = false;
  String? _pendingPerson;
  String? _status;

  /// Specific people with nobody added yet stores the same columns as Only
  /// me, so the choice is held here until the first person is added.
  bool _specificPicked = false;

  AudienceLevel get _level {
    final stored = audienceOf(
      isPublic: _columns?.isPublic,
      followersOnly: _columns?.followersOnly,
      shareCount: _shares.length,
    );
    return stored == AudienceLevel.private && _specificPicked
        ? AudienceLevel.specific
        : stored;
  }

  @override
  void initState() {
    super.initState();
    _loadColumns();
    _loadShares();
    _loadPeople();
  }

  Future<void> _loadColumns() async {
    setState(() {
      _columnsLoading = true;
      _columnsFailed = false;
    });
    try {
      final c = await widget.backend.fetchColumns();
      if (!mounted) return;
      setState(() {
        _columns = c;
        _columnsFailed = c == null;
        _columnsLoading = false;
      });
    } catch (e) {
      debugPrint('audience columns failed: $e');
      if (!mounted) return;
      setState(() {
        _columnsFailed = true;
        _columnsLoading = false;
      });
    }
  }

  Future<void> _loadShares() async {
    setState(() {
      _sharesLoading = true;
      _sharesFailed = false;
    });
    try {
      final s = await widget.backend.fetchShares();
      if (!mounted) return;
      setState(() {
        _shares = s;
        _sharesLoading = false;
      });
    } catch (e) {
      debugPrint('audience shares failed: $e');
      if (!mounted) return;
      setState(() {
        _sharesFailed = true;
        _sharesLoading = false;
      });
    }
  }

  Future<void> _loadPeople() async {
    setState(() {
      _peopleLoading = true;
      _peopleFailed = false;
    });
    try {
      final p = await widget.backend.fetchCandidates();
      if (!mounted) return;
      setState(() {
        _people = p;
        _peopleLoading = false;
      });
    } catch (e) {
      debugPrint('audience candidates failed: $e');
      if (!mounted) return;
      setState(() {
        _peopleFailed = true;
        _peopleLoading = false;
      });
    }
  }

  String _nameOf(AppLocalizations l10n, AudiencePerson p) =>
      (p.displayName == null || p.displayName!.trim().isEmpty)
      ? l10n.peopleFallbackDisplayName
      : p.displayName!;

  Future<void> _choose(AudienceLevel next) async {
    if (_busy || _columns == null) return;
    final l10n = AppLocalizations.of(context);
    if (next == AudienceLevel.public) {
      Navigator.of(context).pop(AudienceSheetResult.requestPublic);
      return;
    }
    if (next == _level) return;
    if (next == AudienceLevel.private && _shares.isNotEmpty) {
      final ok = await confirmDestructive(
        context,
        title: l10n.audienceRevokeAllTitle,
        body: l10n.audienceRevokeAllBody,
        confirmLabel: l10n.audienceRevokeAllConfirm,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      await widget.backend.setLevel(next);
      if (!mounted) return;
      setState(() {
        _columns = audienceColumns(next);
        _specificPicked = next == AudienceLevel.specific;
        if (levelRevokesGrants(next)) _shares = const [];
        _status = l10n.audienceUpdated;
      });
    } catch (e) {
      debugPrint('audience setLevel failed: $e');
      if (!mounted) return;
      setState(
        () => _status = l10n.audienceUpdateFailed(friendlyError(l10n, e)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share(AudiencePerson p) async {
    if (_pendingPerson != null) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _pendingPerson = p.id);
    try {
      await widget.backend.addShare(p.id);
      if (!mounted) return;
      setState(() {
        _shares = [..._shares, p];
        _status = l10n.audienceShared(_nameOf(l10n, p));
      });
    } catch (e) {
      debugPrint('audience addShare failed: $e');
      if (!mounted) return;
      setState(
        () => _status = l10n.audienceShareFailed(friendlyError(l10n, e)),
      );
    } finally {
      if (mounted) setState(() => _pendingPerson = null);
    }
  }

  Future<void> _revoke(AudiencePerson p) async {
    if (_pendingPerson != null) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _pendingPerson = p.id);
    try {
      await widget.backend.revokeShare(p.id);
      if (!mounted) return;
      setState(() {
        _shares = _shares.where((s) => s.id != p.id).toList();
        _status = l10n.audienceRevoked(_nameOf(l10n, p));
      });
    } catch (e) {
      debugPrint('audience revokeShare failed: $e');
      if (!mounted) return;
      setState(
        () => _status = l10n.audienceRevokeFailed(friendlyError(l10n, e)),
      );
    } finally {
      if (mounted) setState(() => _pendingPerson = null);
    }
  }

  String _label(AppLocalizations l10n, AudienceLevel level) => switch (level) {
    AudienceLevel.private => l10n.audienceLevelPrivate,
    AudienceLevel.followers => l10n.audienceLevelFollowers,
    AudienceLevel.specific => l10n.audienceLevelSpecific,
    AudienceLevel.public => l10n.audienceLevelPublic,
  };

  String _hint(AppLocalizations l10n, AudienceLevel level) => switch (level) {
    AudienceLevel.private => l10n.audienceLevelPrivateHint,
    AudienceLevel.followers => l10n.audienceLevelFollowersHint,
    AudienceLevel.specific => l10n.audienceLevelSpecificHint,
    AudienceLevel.public => l10n.audienceLevelPublicHint,
  };

  IconData _icon(AudienceLevel level) => switch (level) {
    AudienceLevel.private => Icons.lock_outline,
    AudienceLevel.followers => Icons.group,
    AudienceLevel.specific => Icons.person_add_alt,
    AudienceLevel.public => Icons.public,
  };

  Widget _retry(
    AppLocalizations l10n,
    String message,
    VoidCallback onRetry,
    Key key,
  ) => Row(
    key: key,
    children: [
      Expanded(child: Text(message)),
      TextButton(onPressed: onRetry, child: Text(l10n.audienceRetry)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sharedIds = {for (final s in _shares) s.id};
    final q = _query.trim().toLowerCase();
    final matches = _people
        .where((p) => q.isEmpty || _nameOf(l10n, p).toLowerCase().contains(q))
        .toList();
    final level = _level;
    final narrow =
        level == AudienceLevel.followers || level == AudienceLevel.specific;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          key: const ValueKey('audience-sheet'),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                child: Text(
                  l10n.audienceTitle,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 8),
              if (_columnsLoading)
                ListSkeleton.section(label: l10n.commonLoading, rows: 3)
              else if (_columnsFailed)
                _retry(
                  l10n,
                  l10n.audienceLoadFailed,
                  _loadColumns,
                  const ValueKey('audience-columns-error'),
                )
              else
                for (final option in audienceLevels)
                  ListTile(
                    key: ValueKey('audience-level-${option.name}'),
                    enabled: !_busy,
                    leading: Icon(_icon(option)),
                    title: Text(_label(l10n, option)),
                    subtitle: Text(_hint(l10n, option)),
                    selected: option == level,
                    trailing: option == level ? const Icon(Icons.check) : null,
                    onTap: () => _choose(option),
                  ),
              Text(l10n.audienceClipNote, style: theme.textTheme.bodySmall),
              if (_status != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _status!,
                      key: const ValueKey('audience-status'),
                    ),
                  ),
                ),
              if (narrow && !_columnsFailed)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton.icon(
                    key: const ValueKey('audience-share-link'),
                    icon: const Icon(Icons.link),
                    label: Text(l10n.audienceShareLink),
                    onPressed: () => Navigator.of(
                      context,
                    ).pop(AudienceSheetResult.shareLink),
                  ),
                ),
              const Divider(height: 24),
              Semantics(
                header: true,
                child: Text(
                  l10n.audienceSharedWith,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              if (_sharesLoading)
                ListSkeleton.section(label: l10n.commonLoading, rows: 2)
              else if (_sharesFailed)
                _retry(
                  l10n,
                  l10n.audienceLoadFailed,
                  _loadShares,
                  const ValueKey('audience-shares-error'),
                )
              else if (_shares.isEmpty)
                Text(l10n.audienceSharedWithNobody)
              else
                for (final s in _shares)
                  ListTile(
                    key: ValueKey('audience-shared-${s.id}'),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_outline),
                    title: Text(_nameOf(l10n, s)),
                    trailing: IconButton(
                      icon: const Icon(Icons.person_remove_outlined),
                      tooltip: l10n.audienceRevokeTooltip(_nameOf(l10n, s)),
                      onPressed: _pendingPerson == null
                          ? () => _revoke(s)
                          : null,
                    ),
                  ),
              const Divider(height: 24),
              Semantics(
                header: true,
                child: Text(
                  l10n.audienceAddPeople,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              if (_peopleLoading)
                ListSkeleton.section(label: l10n.commonLoading, rows: 3)
              else if (_peopleFailed)
                _retry(
                  l10n,
                  l10n.audiencePeopleLoadFailed,
                  _loadPeople,
                  const ValueKey('audience-people-error'),
                )
              else if (_people.isEmpty)
                Text(l10n.audienceNoPeople)
              else ...[
                TextField(
                  key: const ValueKey('audience-search'),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: l10n.audienceSearchHint,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
                if (matches.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(l10n.audienceNoMatches),
                  )
                else
                  for (final p in matches)
                    ListTile(
                      key: ValueKey('audience-person-${p.id}'),
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.person_outline),
                      title: Text(_nameOf(l10n, p)),
                      trailing: sharedIds.contains(p.id)
                          ? Text(l10n.audienceAlreadyShared)
                          : TextButton(
                              onPressed:
                                  _pendingPerson == null && !_columnsFailed
                                  ? () => _share(p)
                                  : null,
                              child: Text(l10n.audienceShareAction),
                            ),
                    ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
