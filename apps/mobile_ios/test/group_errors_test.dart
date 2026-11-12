import 'dart:io';

import 'package:api_client/api_client.dart'
    show DmImageUnavailable, GroupActionRefused, GroupRefusal;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../lib/group_errors.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/rate_limit_message.dart';

// A refused invitee, a missing one and a block are one server refusal and must
// stay one sentence, so a picker can't be used to learn which it was (#1365).
void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  const throttle = PostgrestException(
      code: 'P0001',
      message: 'rate limit exceeded for send_group_message, retry in 30s');

  group('groupErrorMessage', () {
    test('each named refusal reads its own sentence', () {
      String read(GroupRefusal r) =>
          groupErrorMessage(en, GroupActionRefused(r), fallback: 'fallback');
      expect(read(GroupRefusal.unavailable), en.groupsUnavailable);
      expect(read(GroupRefusal.notFound), en.groupsNotFound);
      expect(read(GroupRefusal.refused), en.groupsActionRefused);
      expect(read(GroupRefusal.capReached), en.groupsCapReached);
      expect(read(GroupRefusal.titleInvalid), en.groupsTitleInvalid);
    });

    test('a refusal takes the action\'s own sentence when one is given', () {
      expect(
          groupErrorMessage(en, const GroupActionRefused(GroupRefusal.refused),
              refused: 'cannot be invited', fallback: 'fallback'),
          'cannot be invited');
    });

    test('the throttle reads its wait, not the fallback', () {
      final wait = rateLimitErrorMessage(en,
          code: throttle.code, message: throttle.message);
      expect(wait, isNotNull);
      expect(groupErrorMessage(en, throttle, fallback: 'fallback'), wait);
    });

    test('a dropped connection reads as offline', () {
      expect(
          groupErrorMessage(en, const SocketException('Network is unreachable'),
              fallback: 'fallback'),
          en.authErrorOffline);
    });

    test('anything unnamed reads the fallback', () {
      expect(groupErrorMessage(en, StateError('boom'), fallback: 'fallback'),
          'fallback');
      expect(
          groupErrorMessage(
              en,
              const PostgrestException(
                  code: '42501', message: 'permission denied'),
              fallback: 'fallback'),
          'fallback');
    });
  });

  group('groupSendErrorMessage', () {
    test('the send gate reads as not allowed, with or without a photo', () {
      const refused = GroupActionRefused(GroupRefusal.refused);
      expect(
          groupSendErrorMessage(en, refused, withPhoto: false, uploaded: false),
          en.groupsSendNotAllowed);
      expect(
          groupSendErrorMessage(en, refused, withPhoto: true, uploaded: true),
          en.messagesPhotoSendNotAllowed);
    });

    test('an unavailable photo reads its own sentence', () {
      expect(
          groupSendErrorMessage(en, const DmImageUnavailable(),
              withPhoto: true, uploaded: true),
          en.messagesPhotoUnavailable);
    });

    test('other refusals fall through to the group sentences', () {
      expect(
          groupSendErrorMessage(
              en, const GroupActionRefused(GroupRefusal.unavailable),
              withPhoto: false, uploaded: false),
          en.groupsUnavailable);
    });

    test('a failure before the photo uploaded says the upload failed', () {
      expect(
          groupSendErrorMessage(en, StateError('boom'),
              withPhoto: true, uploaded: false),
          en.messagesPhotoUploadFailed);
      expect(
          groupSendErrorMessage(en, StateError('boom'),
              withPhoto: true, uploaded: true),
          en.messagesSendFailed);
      expect(
          groupSendErrorMessage(en, StateError('boom'),
              withPhoto: false, uploaded: false),
          en.messagesSendFailed);
    });

    test('the throttle and offline still read their own sentences', () {
      final wait = rateLimitErrorMessage(en,
          code: throttle.code, message: throttle.message);
      expect(
          groupSendErrorMessage(en, throttle, withPhoto: false, uploaded: false),
          wait);
      expect(
          groupSendErrorMessage(en, const SocketException('down'),
              withPhoto: false, uploaded: false),
          en.authErrorOffline);
    });
  });
}
