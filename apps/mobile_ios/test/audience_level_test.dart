import 'package:flutter_test/flutter_test.dart';
import '../lib/audience_level.dart';

const _private = AudienceColumns(isPublic: false, followersOnly: false);

void main() {
  test('privacyDefaultToAudience — "public" writes a public row', () {
    expect(privacyDefaultToAudience('public'),
        const AudienceColumns(isPublic: true, followersOnly: false));
  });

  test('privacyDefaultToAudience — "followers" writes followers_only, not owner-only', () {
    expect(privacyDefaultToAudience('followers'),
        const AudienceColumns(isPublic: false, followersOnly: true));
  });

  test('privacyDefaultToAudience — "private" stays owner-only', () {
    expect(privacyDefaultToAudience('private'), _private);
  });

  test('privacyDefaultToAudience — missing / unknown pref is fail-closed (owner-only)', () {
    for (final pref in <String?>[null, '', 'everyone', 'PUBLIC']) {
      expect(privacyDefaultToAudience(pref), _private, reason: '$pref');
    }
  });

  test('audienceColumns — specific people is a private row; grants carry the audience', () {
    expect(audienceColumns(AudienceLevel.specific), _private);
    expect(audienceColumns(AudienceLevel.private),
        audienceColumns(AudienceLevel.specific));
  });

  test('audienceColumns never sets both columns', () {
    for (final level in audienceLevels) {
      final c = audienceColumns(level);
      expect(c.isPublic && c.followersOnly, isFalse, reason: '$level');
    }
  });

  test('audienceOf — is_public wins over followers_only and grants', () {
    expect(audienceOf(isPublic: true, followersOnly: true, shareCount: 3),
        AudienceLevel.public);
  });

  test('audienceOf — followers_only reads as followers whatever the grants', () {
    expect(audienceOf(isPublic: false, followersOnly: true, shareCount: 0),
        AudienceLevel.followers);
    expect(audienceOf(isPublic: false, followersOnly: true, shareCount: 2),
        AudienceLevel.followers);
  });

  test('audienceOf — a private row is specific people exactly when a grant is live', () {
    expect(audienceOf(isPublic: false, followersOnly: false, shareCount: 1),
        AudienceLevel.specific);
    expect(audienceOf(isPublic: false, followersOnly: false, shareCount: 0),
        AudienceLevel.private);
    expect(audienceOf(isPublic: null, shareCount: 0), AudienceLevel.private);
  });

  test('audienceOf round-trips every level through audienceColumns', () {
    for (final level in audienceLevels) {
      final c = audienceColumns(level);
      expect(
        audienceOf(
          isPublic: c.isPublic,
          followersOnly: c.followersOnly,
          shareCount: level == AudienceLevel.specific ? 1 : 0,
        ),
        level,
      );
    }
  });

  test('levelRevokesGrants — only "only me" revokes', () {
    expect(audienceLevels.where(levelRevokesGrants).toList(),
        [AudienceLevel.private]);
  });
}
