import 'package:api_client/api_client.dart'
    show
        UltraSignUpCandidate,
        UltraSignUpPersonLink,
        linkFromCandidate,
        safeErrorLabel,
        ultraSignUpNameMaxLen,
        ultraSignUpNameReady;
import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../race_service.dart';
import '../undo_queue.dart';
import 'full_screen_form.dart';
import 'top_banner.dart';
import 'undo_bar.dart';

/// The runner's UltraSignup person, as the Settings tile, the finder and the
/// race import sheet all read it (decisions § 1841). Mirrors web's
/// `UltraSignUpLinkPanel.svelte`.
///
/// One shared value rather than a read per surface because an unlink is
/// DEFERRED: the row is still on the server for the whole undo window, so a
/// surface that re-read it on return would show the runner linked again, and
/// Undo has to put the link back on whichever surface is showing.
class UltraSignUpLinkModel extends ChangeNotifier {
  bool _loaded = false;
  UltraSignUpPersonLink? _link;
  bool _disposed = false;

  /// False until the stored link has been read, so no surface offers the
  /// finder to a runner who is already linked.
  bool get loaded => _loaded;
  UltraSignUpPersonLink? get link => _link;

  /// False once the surface that owns it has gone. An undo can land after a
  /// pop, so a deferred restore checks this before writing.
  bool get mounted => !_disposed;

  void set(UltraSignUpPersonLink? link) {
    _loaded = true;
    _link = link;
    if (!_disposed) notifyListeners();
  }

  /// A failed read is "not linked", as on web: the finder is the way forward,
  /// and a re-pick replaces whatever row is there.
  Future<void> load(RaceService service) async {
    UltraSignUpPersonLink? link;
    try {
      link = await service.fetchUltraSignUpLink();
    } catch (e) {
      debugPrint('UltraSignUp link read failed: ${safeErrorLabel(e)}');
    }
    set(link);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Open the finder: type the name you race under, pick yourself from the
/// people UltraSignup returns, or unlink the person already picked. A
/// full-screen form rather than a sheet because it holds text fields
/// (`full_screen_form.dart`).
Future<void> showUltraSignUpLink(
  BuildContext context, {
  required RaceService service,
  required UltraSignUpLinkModel model,
}) {
  return showFullScreenForm<void>(
    context,
    title: AppLocalizations.of(context).integrationsUltrasignup,
    builder: (_) => UltraSignUpLinkPanel(service: service, model: model),
  );
}

/// Settings → Integrations, under the UltraSignup tile: who the runner is on
/// UltraSignup, and the way to change it.
class UltraSignUpLinkTile extends StatefulWidget {
  final RaceService service;

  const UltraSignUpLinkTile({super.key, required this.service});

  @override
  State<UltraSignUpLinkTile> createState() => _UltraSignUpLinkTileState();
}

class _UltraSignUpLinkTileState extends State<UltraSignUpLinkTile> {
  final _model = UltraSignUpLinkModel();

  @override
  void initState() {
    super.initState();
    _model.load(widget.service);
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: _model,
      builder: (context, _) {
        final link = _model.link;
        return ListTile(
          key: const Key('ultrasignup-link-tile'),
          leading: const Icon(Icons.person_search),
          title: Text(link == null
              ? l.integrationsUltrasignupFindLabel
              : l.integrationsUltrasignupLinkedAs(
                  '${link.firstName} ${link.lastName}', link.personId)),
          subtitle: link == null ? Text(l.integrationsUltrasignupNameHint) : null,
          trailing: const Icon(Icons.chevron_right),
          onTap: _model.loaded
              ? () => showUltraSignUpLink(context,
                  service: widget.service, model: _model)
              : null,
        );
      },
    );
  }
}

/// The finder itself, over a shared [UltraSignUpLinkModel].
class UltraSignUpLinkPanel extends StatefulWidget {
  final RaceService service;
  final UltraSignUpLinkModel model;

  const UltraSignUpLinkPanel({
    super.key,
    required this.service,
    required this.model,
  });

  @override
  State<UltraSignUpLinkPanel> createState() => _UltraSignUpLinkPanelState();
}

class _UltraSignUpLinkPanelState extends State<UltraSignUpLinkPanel> {
  final _first = TextEditingController();
  final _last = TextEditingController();
  bool _searching = false;
  bool _saving = false;

  /// Null = no search run yet; empty = searched and nobody answered.
  List<UltraSignUpCandidate>? _candidates;

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    super.dispose();
  }

  bool get _canSearch =>
      !_searching && ultraSignUpNameReady(_first.text, _last.text);

  Future<void> _search() async {
    if (!_canSearch) return;
    setState(() => _searching = true);
    final l = AppLocalizations.of(context);
    try {
      final found =
          await widget.service.lookupUltraSignUpPeople(_first.text, _last.text);
      if (!mounted) return;
      setState(() => _candidates = found);
    } catch (e) {
      debugPrint('UltraSignup lookup failed: ${safeErrorLabel(e)}');
      if (!mounted) return;
      setState(() => _candidates = null);
      showTopBanner(context, l.integrationsUltrasignupLookupFailed);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _pick(UltraSignUpCandidate c) async {
    if (_saving) return;
    setState(() => _saving = true);
    final l = AppLocalizations.of(context);
    final next = linkFromCandidate(c);
    try {
      await widget.service.linkUltraSignUpPerson(next);
      widget.model.set(next);
      if (!mounted) return;
      setState(() => _candidates = null);
      showTopBanner(context, l.integrationsUltrasignupLinked);
    } catch (e) {
      debugPrint('UltraSignup link failed: ${safeErrorLabel(e)}');
      if (mounted) showTopBanner(context, l.integrationsUltrasignupLinkFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Honestly reversible — the same person is one search away, and runs
  /// already imported are not touched — so it gets the undo bar, not a dialog
  /// (conventions.md § Destructive actions).
  void _unlink() {
    final l = AppLocalizations.of(context);
    final model = widget.model;
    final before = model.link;
    model.set(null);
    deferDestructive(
      context,
      DeferredDestruction(
        message: l.integrationsUltrasignupUnlinked,
        commit: widget.service.unlinkUltraSignUpPerson,
        restore: () {
          if (model.mounted) model.set(before);
        },
        onCommitError: (e) {
          debugPrint('UltraSignup unlink failed: ${safeErrorLabel(e)}');
          if (!mounted) return;
          showTopBanner(context, l.integrationsUltrasignupUnlinkFailed);
        },
      ),
    );
  }

  String _meta(AppLocalizations l, UltraSignUpCandidate c) {
    final results = l.integrationsUltrasignupCandidateResults(c.resultCount);
    final age = c.age;
    return age == null
        ? results
        : '${l.integrationsUltrasignupCandidateAge(age)} · $results';
  }

  String _events(UltraSignUpCandidate c) => c.recentEvents
      .map((e) => e.date == null ? e.name : '${e.name} (${e.date!.substring(0, 4)})')
      .join(' · ');

  Widget _candidate(AppLocalizations l, ThemeData theme, UltraSignUpCandidate c) {
    return Card(
      key: Key('ultrasignup-candidate-${c.id}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${c.firstName} ${c.lastName}', style: theme.textTheme.titleSmall),
            Text(_meta(l, c), style: theme.textTheme.bodySmall),
            if (c.recentEvents.isNotEmpty)
              Text(_events(c), style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: OutlinedButton(
                onPressed: _saving ? null : () => _pick(c),
                child: Text(l.integrationsUltrasignupThisIsMe),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: widget.model,
      builder: (context, _) {
        final link = widget.model.link;
        final candidates = _candidates;
        return FullScreenFormBody(
          children: [
            if (link != null) ...[
              Text(
                l.integrationsUltrasignupLinkedAs(
                    '${link.firstName} ${link.lastName}', link.personId),
                key: const Key('ultrasignup-linked-as'),
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton(
                  onPressed: _unlink,
                  child: Text(l.integrationsUltrasignupUnlink),
                ),
              ),
            ] else if (widget.model.loaded) ...[
              Text(l.integrationsUltrasignupFindLabel,
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(l.integrationsUltrasignupNameHint,
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 12),
              TextField(
                controller: _first,
                maxLength: ultraSignUpNameMaxLen,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.givenName],
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                    labelText: l.integrationsUltrasignupFirstName),
                onChanged: (_) => setState(() {}),
              ),
              TextField(
                controller: _last,
                maxLength: ultraSignUpNameMaxLen,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.familyName],
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                    labelText: l.integrationsUltrasignupLastName),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _search(),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _canSearch ? _search : null,
                child: Text(_searching
                    ? l.integrationsUltrasignupSearching
                    : l.integrationsUltrasignupFind),
              ),
              const SizedBox(height: 16),
              // Always mounted so the first answer is announced, as web's
              // `aria-live` region is (decisions § 736).
              Semantics(
                liveRegion: true,
                container: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (candidates != null && candidates.isEmpty)
                      Text(l.integrationsUltrasignupNoMatches,
                          key: const Key('ultrasignup-no-matches'),
                          style: theme.textTheme.bodyMedium),
                    if (candidates != null && candidates.isNotEmpty) ...[
                      Text(l.integrationsUltrasignupPickPrompt,
                          style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 8),
                      for (final c in candidates) _candidate(l, theme, c),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
