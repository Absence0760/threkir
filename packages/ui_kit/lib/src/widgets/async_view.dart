import 'package:flutter/material.dart';

import 'list_skeleton.dart';

/// The loading frame for a surface that is still reading: skeleton rows where
/// the rows will stand, never a bare centred spinner, so the arriving content
/// fills the space instead of jumping into it.
///
/// [label] is the screen-reader announcement, passed in translated because
/// ui_kit has no catalogue.
class LoadingState extends StatelessWidget {
  final String label;
  final int rows;
  final bool hasLeading;
  final EdgeInsetsGeometry padding;
  final bool _section;

  /// Fills a bounded surface, the usual case for a whole tab or page.
  const LoadingState.list({
    super.key,
    required this.label,
    this.rows = 6,
    this.hasLeading = true,
    this.padding = const EdgeInsets.all(16),
  }) : _section = false;

  /// Takes only the height its rows need, for one section of a page that
  /// already scrolls.
  const LoadingState.section({
    super.key,
    required this.label,
    this.rows = 3,
    this.hasLeading = true,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
  }) : _section = true;

  @override
  Widget build(BuildContext context) => _section
      ? ListSkeleton.section(
          label: label, rows: rows, hasLeading: hasLeading, padding: padding)
      : ListSkeleton(
          label: label, rows: rows, hasLeading: hasLeading, padding: padding);
}

/// One read's four states, decided in one place so every surface answers them
/// the same way:
///
/// 1. data with something in it: [builder], even while a refresh runs or after
///    one failed (the caller says so with a banner; the rows stay);
/// 2. still loading: [loading];
/// 3. failed with nothing to show: [errorBuilder] — a failed read is never
///    drawn as empty;
/// 4. loaded and empty: [empty], which should offer a way forward.
///
/// Before the first read starts ([data] null, not loading, no error) it shows
/// [loading], since a read is about to begin.
///
/// With [onRefresh], every settled state can be pulled to refresh: the empty
/// and error states as well as the rows, so a list that came back empty or
/// failed is never a dead end (issue #1374 FS-3). [builder] must then return
/// something scrollable. The `RefreshIndicator` is always in the tree and only
/// switched off while loading, because adding and removing it would remount
/// the body. Leave it null inside `HubTabBody`, which owns the tab's pull.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.loading,
    required this.data,
    required this.isEmpty,
    required this.builder,
    required this.empty,
    required this.errorBuilder,
    required this.loadingState,
    this.error,
    this.onRefresh,
  });

  final bool loading;
  final Object? error;
  final T? data;
  final bool Function(T data) isEmpty;
  final Widget Function(BuildContext context, T data) builder;
  final Widget empty;
  final Widget Function(BuildContext context, Object error) errorBuilder;

  /// Usually a [LoadingState].
  final Widget loadingState;

  final RefreshCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final onRefresh = this.onRefresh;
    final (child, settled) = _state(context);
    if (onRefresh == null) return child;
    return RefreshIndicator(
      onRefresh: onRefresh,
      notificationPredicate: settled ? defaultScrollNotificationPredicate : (_) => false,
      child: child,
    );
  }

  (Widget, bool) _state(BuildContext context) {
    final data = this.data;
    if (data != null && !isEmpty(data)) return (builder(context, data), true);
    if (loading) return (loadingState, false);
    if (error case final error?) return (errorBuilder(context, error), true);
    if (data == null) return (loadingState, false);
    return (empty, true);
  }
}
