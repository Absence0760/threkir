import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/disclosure_state.dart';
import '../lib/screens/plan_detail_screen.dart';

/// Plan detail opens with every named section shut (decisions § 2375). A test
/// about what sits inside one seeds the state a runner who had opened them
/// would have remembered, so it reads the section rather than the default.
/// Added to the store, not replacing it, so other seeded keys survive. Call it
/// before the screen is pumped: the screen reads the state once, on mount.
Future<void> rememberPlanSectionsOpen(
    WidgetTester tester, String? viewerId) async {
  await tester.runAsync(() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      disclosureStorageKey(kPlanDetailDisclosureScope, viewerId),
      jsonEncode({for (final k in kPlanDetailDisclosureDefaults.keys) k: true}),
    );
  });
}
