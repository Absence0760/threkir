import 'dart:async';
import 'dart:typed_data';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ui_kit/ui_kit.dart'
    show EditorPage, EditorSave, ErrorState, IdentityAvatar, ListSkeleton;

import '../auth_change_aware.dart';
import '../auth_error.dart';
import '../exif_strip.dart';
import '../l10n/gen/app_localizations.dart';
import '../profile_handle.dart';
import '../text_limits.dart';
import '../widgets/confirm_destructive.dart';
import '../widgets/confirm_discard.dart';
import '../widgets/top_banner.dart';
import 'avatar_crop_screen.dart';

enum _ProfileLoad { loading, ready, failed }

/// Edit profile: the identity other people see, which is the photo, the
/// display name and the public @username, as web's account page groups them
/// (issue #1374 round 3). Reached from the You identity card, your own
/// profile and Account.
///
/// The photo saves the moment it is picked or removed, as on web; the name
/// and username are fields under one pinned Save. Nothing is editable until
/// the stored values have loaded, because a form seeded from a pending or
/// failed read would save blanks over them.
class EditProfileScreen extends StatefulWidget {
  final ApiClient apiClient;

  /// Replaces the gallery picker so a widget test can drive pick -> crop ->
  /// upload without the image_picker platform channel.
  final Future<XFile?> Function()? pickAvatarOverride;

  const EditProfileScreen({
    super.key,
    required this.apiClient,
    this.pickAvatarOverride,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen>
    with AuthChangeAware {
  final _nameCtl = TextEditingController();
  final _handleCtl = TextEditingController();
  final _picker = ImagePicker();

  _ProfileLoad _load = _ProfileLoad.loading;
  int _loadGeneration = 0;
  String? _avatarUrl;
  bool _avatarBusy = false;
  String _savedName = '';
  String _savedHandle = '';
  bool _saving = false;
  String? _handleError;

  @override
  ApiClient? get authApi => widget.apiClient;

  @override
  void initState() {
    super.initState();
    unawaited(_loadProfile());
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _handleCtl.dispose();
    super.dispose();
  }

  /// A sign-out or account switch under this screen: the values on it are
  /// the departed account's, so the form closes until the next read lands.
  @override
  void onAuthUserChanged(String? userId) {
    setState(() {
      _avatarUrl = null;
      _savedName = '';
      _savedHandle = '';
      _nameCtl.clear();
      _handleCtl.clear();
      _handleError = null;
      _load = _ProfileLoad.loading;
    });
    unawaited(_loadProfile());
  }

  bool get _signedIn => widget.apiClient.userId != null;

  bool get _dirty =>
      _load == _ProfileLoad.ready &&
      (_nameCtl.text.trim() != _savedName ||
          normalizeHandle(_handleCtl.text) != _savedHandle);

  Future<void> _loadProfile() async {
    final generation = ++_loadGeneration;
    if (!_signedIn) return;
    try {
      final profile = await widget.apiClient.fetchMyProfile();
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _avatarUrl = profile?.avatarUrl;
        _savedName = profile?.displayName?.trim() ?? '';
        _savedHandle = profile?.handle ?? '';
        _nameCtl.text = _savedName;
        _handleCtl.text = _savedHandle;
        _load = _ProfileLoad.ready;
      });
    } catch (e) {
      debugPrint('edit profile: load failed: $e');
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _load = _ProfileLoad.failed);
    }
  }

  Future<void> _retry() async {
    setState(() => _load = _ProfileLoad.loading);
    await _loadProfile();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final name = _nameCtl.text.trim();
    final handle = normalizeHandle(_handleCtl.text);
    if (!isValidHandle(handle)) {
      setState(() => _handleError = l10n.editProfileUsernameInvalid);
      return;
    }
    setState(() {
      _saving = true;
      _handleError = null;
    });
    try {
      // The handle first: it is the write that can be refused for a reason
      // the person must fix, and the name then saves with it or not at all.
      if (handle != _savedHandle) {
        final stored = await widget.apiClient.setMyHandle(handle);
        _savedHandle = stored ?? '';
      }
      if (name != _savedName) {
        await widget.apiClient.updateDisplayName(name);
        _savedName = name;
      }
      if (!mounted) return;
      setState(() => _handleCtl.text = _savedHandle);
      showTopBanner(context, l10n.editProfileSaved);
      Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('edit profile: save failed: $e');
      if (!mounted) return;
      switch (handleRefusalOf(e)) {
        case HandleRefusal.taken:
          setState(() => _handleError = l10n.editProfileUsernameTaken);
        case HandleRefusal.invalid:
          setState(() => _handleError = l10n.editProfileUsernameInvalid);
        case null:
          showTopBanner(context, l10n.editProfileSaveFailed);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickAvatar() async {
    final l10n = AppLocalizations.of(context);
    if (_load != _ProfileLoad.ready) return;
    XFile? f;
    try {
      f = await (widget.pickAvatarOverride ??
          () => _picker.pickImage(
                source: ImageSource.gallery,
                imageQuality: 90,
                maxWidth: 1024,
                maxHeight: 1024,
              ))();
    } catch (e) {
      debugPrint('edit profile: avatar pick failed: $e');
      if (!mounted) return;
      showTopBanner(
          context, l10n.settingsAccountAvatarFailed(friendlyError(l10n, e)));
      return;
    }
    if (f == null) return;
    final Uint8List picked;
    try {
      picked = Uint8List.fromList(await f.readAsBytes());
    } catch (e) {
      debugPrint('edit profile: avatar read failed: $e');
      if (!mounted) return;
      showTopBanner(
          context, l10n.settingsAccountAvatarFailed(friendlyError(l10n, e)));
      return;
    }
    // The format comes from the bytes, not the picked filename: a HEIC named
    // `.jpg` is refused here rather than handed to a decoder that can't read it.
    if (detectImageMime(picked) == null) {
      if (!mounted) return;
      showTopBanner(context, l10n.settingsAccountAvatarUnsupported);
      return;
    }
    if (!mounted) return;
    final cropped = await showAvatarCropScreen(context, picked);
    if (cropped == null || !mounted) return;
    setState(() => _avatarBusy = true);
    try {
      // The crop step re-encodes from decoded pixels, so no EXIF survives it;
      // the strip stays because the avatars bucket is public with no
      // server-side strip worker, and this is the last rail before it.
      final clean = stripImageExif(cropped, 'image/jpeg');
      final url = await widget.apiClient
          .uploadAvatar(bytes: clean, contentType: 'image/jpeg');
      if (!mounted) return;
      setState(() => _avatarUrl = url);
      showTopBanner(context, l10n.settingsAccountAvatarSaved);
    } catch (e) {
      debugPrint('edit profile: avatar upload failed: $e');
      if (!mounted) return;
      showTopBanner(
          context, l10n.settingsAccountAvatarFailed(friendlyError(l10n, e)));
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  Future<void> _removeAvatar() async {
    final l10n = AppLocalizations.of(context);
    if (_load != _ProfileLoad.ready) return;
    final ok = await confirmDestructive(
      context,
      title: l10n.settingsAccountAvatarRemoveTitle,
      body: l10n.settingsAccountAvatarRemoveConfirm,
      confirmLabel: l10n.settingsAccountAvatarRemove,
      cancelLabel: l10n.settingsAccountCancel,
    );
    if (!ok || !mounted) return;
    setState(() => _avatarBusy = true);
    try {
      await widget.apiClient.removeAvatar();
      if (!mounted) return;
      setState(() => _avatarUrl = null);
      showTopBanner(context, l10n.settingsAccountAvatarRemoved);
    } catch (e) {
      debugPrint('edit profile: avatar remove failed: $e');
      if (!mounted) return;
      showTopBanner(
          context, l10n.settingsAccountAvatarFailed(friendlyError(l10n, e)));
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  Widget _photoTile(AppLocalizations l10n) {
    final hasPhoto = _avatarUrl != null && _avatarUrl!.isNotEmpty;
    return ListTile(
      key: const ValueKey('edit-profile-photo'),
      contentPadding: EdgeInsets.zero,
      leading: IdentityAvatar(
        seed: widget.apiClient.userId ?? '',
        name: _nameCtl.text.isEmpty
            ? widget.apiClient.userEmail
            : _nameCtl.text,
        size: 48,
        imageUrl: _avatarUrl,
      ),
      title: Text(l10n.settingsAccountAvatar),
      subtitle: Text(l10n.settingsAccountAvatarHint),
      trailing: _avatarBusy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : hasPhoto
              ? IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: l10n.settingsAccountAvatarRemove,
                  onPressed: _removeAvatar,
                )
              : const Icon(Icons.photo_camera),
      onTap: _avatarBusy ? null : _pickAvatar,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final Widget? placeholder = switch (_load) {
      _ when !_signedIn => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(l10n.settingsAccountSignInToSync,
                textAlign: TextAlign.center),
          ),
        ),
      _ProfileLoad.loading =>
        ListSkeleton.section(label: l10n.commonLoading, rows: 3),
      _ProfileLoad.failed => ErrorState(
          key: const ValueKey('edit-profile-load-error'),
          message: l10n.settingsAccountProfileLoadFailed,
          retryLabel: l10n.errorStateRetry,
          onRetry: _retry,
        ),
      _ProfileLoad.ready => null,
    };
    return DiscardGuard(
      isDirty: () => _dirty,
      isBusy: () => _saving,
      child: EditorPage(
        title: l10n.youEditProfile,
        placeholder: placeholder,
        save: EditorSave(
          key: const ValueKey('edit-profile-save'),
          label: _saving ? l10n.editProfileSaving : l10n.settingsAccountSave,
          busy: _saving,
          onPressed: _save,
        ),
        fields: [
          _photoTile(l10n),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('edit-profile-name'),
            controller: _nameCtl,
            maxLength: kDisplayNameMaxLength,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: l10n.settingsAccountDisplayName,
              helperText: l10n.settingsAccountDisplayNameHint,
              helperMaxLines: 3,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('edit-profile-username'),
            controller: _handleCtl,
            autocorrect: false,
            enableSuggestions: false,
            maxLength: 30,
            onChanged: (_) => setState(() => _handleError = null),
            decoration: InputDecoration(
              labelText: l10n.editProfileUsername,
              prefixText: '@',
              helperText: l10n.editProfileUsernameHelp,
              helperMaxLines: 4,
              errorText: _handleError,
              errorMaxLines: 3,
            ),
          ),
        ],
      ),
    );
  }
}
