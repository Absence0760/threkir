import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/training_service.dart';

void main() {
  group('planWriteError', () {
    test('the overlap constraint refusal (23P01) becomes ActivePlanExistsError',
        () {
      final raw = PostgrestException(
        message: 'conflicting key value violates exclusion constraint '
            '"training_plans_active_no_overlap"',
        code: '23P01',
      );
      expect(planWriteError(raw), isA<ActivePlanExistsError>());
    });

    test('any other error is returned unchanged', () {
      final check = PostgrestException(message: 'check', code: '23514');
      expect(planWriteError(check), same(check));
      final other = Exception('offline');
      expect(planWriteError(other), same(other));
    });
  });
}
