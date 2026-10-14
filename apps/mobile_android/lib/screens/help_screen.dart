import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../help_destination.dart';
import '../help_guides.dart';
import '../help_illustration.dart';
import '../help_loader.dart';
import '../l10n/gen/app_localizations.dart';
import '../widgets/error_state.dart';

// In-app help: the guide list with search and an audience filter, one guide,
// and "the guides about this screen". Mobile renderer of web's help centre
// (`apps/web/src/lib/help/`); the content is the generated per-locale JSON
// that `help_loader.dart` reads, already in the app's language wherever the
// guide has a translation, and the chrome here is localized as usual.

const _pagePadding = EdgeInsets.fromLTRB(16, 12, 16, 32);

/// Opens the guide list.
Future<void> openHelp(BuildContext context) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => const HelpScreen()));

/// Opens one guide.
Future<void> openGuide(BuildContext context, String guideId) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => GuideScreen(guideId: guideId)));

/// Opens the guides whose `routes` include any of [routes] — the guide itself
/// when exactly one matches. [audience] narrows to guides written for that
/// reader.
Future<void> openHelpForRoutes(
  BuildContext context,
  List<String> routes, {
  String? audience,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => HelpForRouteScreen(routes: routes, audience: audience),
  ),
);

String? helpCategoryLabel(AppLocalizations l10n, String category) =>
    switch (category) {
      'races' => l10n.helpCategoryRaces,
      'paid-classes' => l10n.helpCategoryPaidClasses,
      'instructors' => l10n.helpCategoryInstructors,
      'clubs' => l10n.helpCategoryClubs,
      'running' => l10n.helpCategoryRunning,
      'account' => l10n.helpCategoryAccount,
      _ => null,
    };

String? helpAudienceLabel(AppLocalizations l10n, String audience) =>
    switch (audience) {
      'runner' => l10n.helpAudienceRunner,
      'organiser' => l10n.helpAudienceOrganiser,
      'participant' => l10n.helpAudienceParticipant,
      'spectator' => l10n.helpAudienceSpectator,
      'instructor' => l10n.helpAudienceInstructor,
      'club-admin' => l10n.helpAudienceClubAdmin,
      _ => null,
    };

String? helpRequirementLabel(AppLocalizations l10n, String requirement) =>
    switch (requirement) {
      'pro' => l10n.helpRequiresPro,
      'club-admin' => l10n.helpRequiresClubAdmin,
      'race-director' => l10n.helpRequiresRaceDirector,
      'stripe-connected' => l10n.helpRequiresStripeConnected,
      'paid-rail-live' => l10n.helpRequiresPaidRailLive,
      _ => null,
    };

String? helpPlatformLabel(AppLocalizations l10n, String platform) =>
    switch (platform) {
      'web' => l10n.helpPlatformWeb,
      'android' => l10n.helpPlatformAndroid,
      'ios' => l10n.helpPlatformIos,
      'wear' => l10n.helpPlatformWear,
      'apple-watch' => l10n.helpPlatformAppleWatch,
      _ => null,
    };

/// Loads the guides and hands them to [builder]; owns the loading and the
/// unavailable states so every Help screen degrades the same way. An empty
/// library is unavailable too — a Help screen with nothing in it is a failure,
/// not a state to design for.
class HelpLibraryBuilder extends StatefulWidget {
  const HelpLibraryBuilder({
    super.key,
    required this.title,
    required this.builder,
  });

  /// The AppBar title while loading or unavailable.
  final String title;
  final Widget Function(BuildContext context, HelpLibrary library) builder;

  @override
  State<HelpLibraryBuilder> createState() => _HelpLibraryBuilderState();
}

class _HelpLibraryBuilderState extends State<HelpLibraryBuilder> {
  String? _localeTag;
  late Future<HelpLibrary?> _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tag = helpLocaleTag(Localizations.localeOf(context));
    if (tag != _localeTag) {
      _localeTag = tag;
      _future = helpLibraryLoader(tag);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<HelpLibrary?>(
      future: _future,
      builder: (context, snap) {
        final library = snap.data;
        if (library != null && library.guides.isNotEmpty) {
          return widget.builder(context, library);
        }
        final loading = snap.connectionState != ConnectionState.done;
        return Scaffold(
          appBar: AppBar(title: Text(widget.title)),
          body: loading
              ? ListSkeleton(label: l10n.helpLoading)
              : ErrorState(
                  icon: Icons.menu_book_outlined,
                  message: l10n.helpUnavailable,
                  onRetry: () => setState(() {
                    _future = helpLibraryLoader(_localeTag!);
                  }),
                ),
        );
      },
    );
  }
}

/// The guide list: search, audience filter, guides by category.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return HelpLibraryBuilder(
      title: l10n.helpTitle,
      builder: (context, library) => Scaffold(
        appBar: AppBar(title: Text(l10n.helpTitle)),
        body: HelpBrowser(library: library),
      ),
    );
  }
}

/// The searchable, filterable guide list. Search results replace the
/// category listing while there is a query.
class HelpBrowser extends StatefulWidget {
  const HelpBrowser({super.key, required this.library});

  final HelpLibrary library;

  @override
  State<HelpBrowser> createState() => _HelpBrowserState();
}

class _HelpBrowserState extends State<HelpBrowser> {
  final _query = TextEditingController();
  String? _audience;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final library = widget.library;
    final query = _query.text.trim();
    final children = <Widget>[];
    if (query.isNotEmpty) {
      final results = library.search(query, audience: _audience);
      children.add(SectionHeader(label: l10n.helpResultsHeader));
      if (results.isEmpty) {
        children.add(
          EmptyState(
            icon: Icons.search_off,
            title: l10n.helpNoResultsTitle,
            body: l10n.helpNoResultsBody,
          ),
        );
      } else {
        children.addAll(results.map((g) => GuideTile(guide: g)));
      }
    } else {
      final known = guideCategoryOrder.toSet();
      final sections = <(String, List<Guide>)>[
        for (final c in guideCategoryOrder)
          (
            helpCategoryLabel(l10n, c)!,
            library.inCategory(c, audience: _audience),
          ),
        (
          l10n.helpCategoryOther,
          [
            for (final g in library.guides)
              if (!known.contains(g.category) && matchesAudience(g, _audience))
                g,
          ],
        ),
      ];
      for (final (label, guides) in sections) {
        if (guides.isEmpty) continue;
        children
          ..add(SectionHeader(label: label))
          ..addAll(guides.map((g) => GuideTile(guide: g)));
      }
      if (children.isEmpty) {
        children.add(
          EmptyState(
            icon: Icons.search_off,
            title: l10n.helpNoResultsTitle,
            body: l10n.helpNoResultsBody,
          ),
        );
      }
    }
    return ListView(
      padding: _pagePadding,
      children: [
        TextField(
          key: const Key('help-search'),
          controller: _query,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: l10n.helpSearchHint,
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: l10n.helpSearchClear,
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(_query.clear),
                  ),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        Text(l10n.helpAudienceLabel, style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        ChoiceChipRow<String?>(
          options: [
            ChoiceChipOption<String?>(value: null, label: l10n.helpAudienceAll),
            for (final a in guideAudiences)
              if (helpAudienceLabel(l10n, a) case final label?)
                ChoiceChipOption<String?>(value: a, label: label),
          ],
          selected: _audience,
          onChanged: (a) => setState(() => _audience = a),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }
}

/// One guide in a list.
class GuideTile extends StatelessWidget {
  const GuideTile({super.key, required this.guide});

  final Guide guide;

  @override
  Widget build(BuildContext context) => ListTile(
    key: ValueKey('help-guide-${guide.id}'),
    contentPadding: EdgeInsets.zero,
    title: Text(guide.title),
    subtitle: guide.summary.isEmpty ? null : Text(guide.summary),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => openGuide(context, guide.id),
  );
}

/// One guide, by id.
class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key, required this.guideId});

  final String guideId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return HelpLibraryBuilder(
      title: l10n.helpTitle,
      builder: (context, library) {
        final guide = library.byId(guideId);
        return Scaffold(
          appBar: AppBar(title: Text(l10n.helpTitle)),
          body: guide == null
              ? EmptyState(
                  icon: Icons.menu_book_outlined,
                  title: l10n.helpGuideMissing,
                  ctaLabel: l10n.helpBrowseAll,
                  ctaIcon: Icons.chevron_right,
                  onCta: () => openHelp(context),
                )
              : GuideView(guide: guide, library: library),
        );
      },
    );
  }
}

/// The guides about the screen Help was opened from. One match opens that
/// guide; several list them; none falls back to the whole list, so the
/// "How this works" button always leads somewhere.
class HelpForRouteScreen extends StatelessWidget {
  const HelpForRouteScreen({super.key, required this.routes, this.audience});

  final List<String> routes;
  final String? audience;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return HelpLibraryBuilder(
      title: l10n.helpHowThisWorks,
      builder: (context, library) {
        final matches = library.guidesForRoutes(routes, audience: audience);
        if (matches.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: Text(l10n.helpTitle)),
            body: HelpBrowser(library: library),
          );
        }
        return Scaffold(
          appBar: AppBar(title: Text(l10n.helpHowThisWorks)),
          body: matches.length == 1
              ? GuideView(guide: matches.single, library: library)
              : ListView(
                  padding: _pagePadding,
                  children: [
                    SectionHeader(label: l10n.helpForThisScreen),
                    ...matches.map((g) => GuideTile(guide: g)),
                    ListTile(
                      key: const Key('help-browse-all'),
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.menu_book_outlined),
                      title: Text(l10n.helpBrowseAll),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => openHelp(context),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

/// A guide's body: title, summary, requirement and platform chips, sections,
/// related guides.
class GuideView extends StatelessWidget {
  const GuideView({super.key, required this.guide, required this.library});

  final Guide guide;
  final HelpLibrary library;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final requirements = [
      for (final r in guide.requires) ?helpRequirementLabel(l10n, r),
    ];
    final platforms = [
      for (final p in guide.platforms) ?helpPlatformLabel(l10n, p),
    ];
    final related = [for (final id in guide.related) ?library.byId(id)];
    return ListView(
      padding: _pagePadding,
      children: [
        Semantics(
          header: true,
          child: Text(guide.title, style: theme.textTheme.headlineSmall),
        ),
        if (guide.summary.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            guide.summary,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        if (guide.lang != helpLocaleTag(Localizations.localeOf(context))) ...[
          const SizedBox(height: 8),
          Text(
            l10n.helpGuideInEnglish,
            key: const Key('help-guide-in-english'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        if (requirements.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final label in requirements)
                StatusPill(
                  label: label,
                  icon: Icons.lock_outline,
                  foreground: scheme.onSurfaceVariant,
                  outline: scheme.outlineVariant,
                  size: StatusPillSize.compact,
                ),
            ],
          ),
        ],
        if (platforms.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(l10n.helpPlatformsLabel, style: theme.textTheme.labelMedium),
              for (final label in platforms)
                StatusPill(
                  label: label,
                  foreground: scheme.onSurfaceVariant,
                  outline: scheme.outlineVariant,
                  size: StatusPillSize.compact,
                ),
            ],
          ),
        ],
        for (final section in guide.sections) ...[
          const SizedBox(height: 24),
          Semantics(
            header: true,
            child: Text(section.heading, style: theme.textTheme.titleMedium),
          ),
          for (final block in section.blocks) ...[
            const SizedBox(height: 8),
            _GuideBlockView(block: block),
          ],
        ],
        if (related.isNotEmpty) ...[
          const SizedBox(height: 24),
          SectionHeader(label: l10n.helpRelated),
          ...related.map((g) => GuideTile(guide: g)),
        ],
      ],
    );
  }
}

class _GuideBlockView extends StatelessWidget {
  const _GuideBlockView({required this.block});

  final GuideBlock block;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final body = theme.textTheme.bodyMedium;
    switch (block) {
      case GuideParagraph(:final text):
        return HelpRichText(text, style: body);
      case GuideIllustration(:final id, :final alt):
        return HelpIllustration(id: id, alt: alt);
      case GuideSteps(:final items):
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < items.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      container: true,
                      label: l10n.helpStepLabel(i + 1),
                      excludeSemantics: true,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${i + 1}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: HelpRichText(items[i], style: body)),
                  ],
                ),
              ),
          ],
        );
      case GuideList(:final items):
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ExcludeSemantics(child: Text('•', style: body)),
                    const SizedBox(width: 8),
                    Expanded(child: HelpRichText(item, style: body)),
                  ],
                ),
              ),
          ],
        );
      case GuideNote(:final tone, :final text):
        final caution = tone == GuideNoteTone.caution;
        final fill = caution
            ? scheme.errorContainer
            : scheme.secondaryContainer;
        final ink = caution
            ? scheme.onErrorContainer
            : scheme.onSecondaryContainer;
        return Container(
          key: ValueKey('help-note-${tone.name}'),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                caution ? Icons.warning_amber_rounded : Icons.lightbulb_outline,
                size: AppIconSize.leading,
                color: ink,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      caution ? l10n.helpNoteCaution : l10n.helpNoteTip,
                      style: theme.textTheme.labelLarge?.copyWith(color: ink),
                    ),
                    const SizedBox(height: 4),
                    HelpRichText(
                      text,
                      style: body?.copyWith(color: ink),
                      linkColor: ink,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
    }
  }
}

/// Guide markup rendered as styled text. A guide link opens that guide; a
/// route link opens the mapped mobile surface through the shell
/// ([openHelpDestination]); a route with no mobile mapping is plain text.
class HelpRichText extends StatefulWidget {
  const HelpRichText(this.source, {super.key, this.style, this.linkColor});

  final String source;
  final TextStyle? style;

  /// Defaults to the theme's primary. A note passes its own ink so a link
  /// keeps the contrast its container was chosen for.
  final Color? linkColor;

  @override
  State<HelpRichText> createState() => _HelpRichTextState();
}

class _HelpRichTextState extends State<HelpRichText> {
  final _recognizers = <TapGestureRecognizer>[];

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final linkColor = widget.linkColor ?? Theme.of(context).colorScheme.primary;
    final spans = <InlineSpan>[];
    for (final s in tokenizeHelpMarkup(widget.source)) {
      var style = TextStyle(
        fontWeight: s.strong ? FontWeight.w600 : null,
        fontStyle: s.emphasis ? FontStyle.italic : null,
      );
      VoidCallback? onTap;
      if (s.guideId case final id?) {
        onTap = () => openGuide(context, id);
      } else if (helpRouteToScreen[s.route] case final destination?) {
        onTap = () => openHelpDestination(destination);
      }
      if (onTap != null) {
        style = style.copyWith(
          color: linkColor,
          decoration: TextDecoration.underline,
          decorationColor: linkColor,
        );
        final recognizer = TapGestureRecognizer()..onTap = onTap;
        _recognizers.add(recognizer);
        spans.add(TextSpan(text: s.text, style: style, recognizer: recognizer));
      } else {
        spans.add(TextSpan(text: s.text, style: style));
      }
    }
    return Text.rich(TextSpan(children: spans), style: widget.style);
  }
}
