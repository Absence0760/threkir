import 'package:flutter/material.dart';

/// The page for a conversation: a direct-message thread, a group thread, the
/// Coach chat.
///
/// A conversation is the one pushed page whose name stays in the bar: its
/// body is the messages, so there is no heading to scroll away, and the name
/// sits beside an avatar as a `ThreadTitle`, whose tooltip holds the whole
/// name when the bar cuts it (TO-12). The toolbar grows with that title
/// ([toolbarHeight], `ThreadTitle.toolbarHeight`) rather than clipping it at
/// large text (TO-8).
///
/// Top to bottom the body is an optional [header] strip, the messages
/// ([body]) taking the rest, and the [footer]: the composer, or the bar that
/// stands in for it (blocked, left the group, a message request). The footer
/// sits in the body's column, so the scaffold lifts it with the soft
/// keyboard, and the page clears the system navigation bar under it, so no
/// footer reads an inset itself. With no footer the body clears it.
///
/// The header is capped at [headerMaxFraction] of the body's height and
/// scrolls inside that cap: at large text a plan-change card or the Coach's
/// context strip would otherwise outgrow a phone and push the composer off
/// the bottom. The cap is a share of the space the body has, not of the
/// screen, so it shrinks with the keyboard up.
///
/// A [drawer] (the Coach's chat history) opens from the start edge. The bar
/// still shows Back on a pushed route, which a drawer's implied menu button
/// would otherwise replace; open the drawer from an action with
/// `Scaffold.of(context).openDrawer()` under a `Builder`.
///
/// Strings come from the caller; ui_kit has no catalogue.
class ConversationPage extends StatelessWidget {
  const ConversationPage({
    super.key,
    required this.title,
    required this.body,
    this.toolbarHeight,
    this.titleSpacing,
    this.actions = const [],
    this.drawer,
    this.header,
    this.headerMaxFraction = 0.4,
    this.footer,
  }) : assert(headerMaxFraction > 0 && headerMaxFraction < 1);

  /// The conversation's name in the bar, usually a `ThreadTitle`.
  final Widget title;

  /// The bar's height; null is Material's. A `ThreadTitle` asks for
  /// `ThreadTitle.toolbarHeight`.
  final double? toolbarHeight;

  /// Space before the title; 0 puts a `ThreadTitle`'s avatar beside Back.
  final double? titleSpacing;

  final List<Widget> actions;

  final Widget? drawer;

  /// A strip above the messages (a pending plan change, the Coach's context
  /// and limit banners), capped at [headerMaxFraction] of the body.
  final Widget? header;

  final double headerMaxFraction;

  /// The messages, or the state that stands in for them (loading, a failed
  /// read, nothing yet). Takes the height the header and footer leave.
  final Widget body;

  /// The composer or the bar in its place, pinned under the messages, above
  /// the keyboard and the system navigation bar.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final header = this.header;
    final footer = this.footer;
    final route = ModalRoute.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: drawer != null && (route?.impliesAppBarDismissal ?? false)
            ? const BackButton()
            : null,
        titleSpacing: titleSpacing,
        toolbarHeight: toolbarHeight,
        title: title,
        actions: actions,
      ),
      drawer: drawer,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SafeArea(
                top: false,
                left: false,
                right: false,
                bottom: footer == null,
                child: header == null
                    ? body
                    : LayoutBuilder(
                        builder: (context, constraints) => Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight:
                                    constraints.maxHeight * headerMaxFraction,
                              ),
                              child: SingleChildScrollView(child: header),
                            ),
                            Expanded(child: body),
                          ],
                        ),
                      ),
              ),
            ),
            if (footer != null)
              SafeArea(
                top: false,
                left: false,
                right: false,
                child: footer,
              ),
          ],
        ),
      ),
    );
  }
}
