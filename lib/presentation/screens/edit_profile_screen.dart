import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/models.dart';
import '../../data/repository_scope.dart';
import '../widgets/common_widgets.dart';
import '../widgets/media_view.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, required this.profile});

  final Profile profile;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final _username = TextEditingController(text: widget.profile.username);
  late final _displayName = TextEditingController(
    text: widget.profile.displayName ?? '',
  );
  late final _bio = TextEditingController(text: widget.profile.bio ?? '');
  late bool _isPrivate = widget.profile.isPrivate;
  late bool _savedPublic = widget.profile.savedPublic;
  XFile? _avatar;
  Uint8List? _avatarBytes;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _displayName.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    try {
      final file = await RepositoryScope.servicesOf(context).media
          .pick(MediaType.image);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      setState(() {
        _avatar = file;
        _avatarBytes = bytes;
      });
    } catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    }
  }

  Future<void> _save() async {
    final services = RepositoryScope.servicesOf(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      String? avatarUrl;
      if (_avatar != null) {
        avatarUrl = await services.media.uploadAvatar(_avatar!);
      }
      final updated = await services.profiles.updateMyProfile(
        username: _username.text,
        displayName: _displayName.text,
        bio: _bio.text,
        isPrivate: _isPrivate,
        savedPublic: _savedPublic,
        avatarUrl: avatarUrl,
      );
      services.repository.username = updated.username;
      await services.repository.setMyAvatar(updated.avatarUrl);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Profile saved.')));
      Navigator.of(context).pop(updated);
    } catch (error) {
      if (mounted) setState(() => _error = errorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCream,
      appBar: AppBar(
        backgroundColor: kCream,
        title: const Text('Edit profile'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Save',
                    style: TextStyle(
                      color: kGreen,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Center(
            child: Stack(
              children: [
                _avatarBytes != null
                    ? CircleAvatar(
                        radius: 48,
                        backgroundImage: MemoryImage(_avatarBytes!),
                      )
                    : UserAvatar(
                        name: widget.profile.name,
                        url: widget.profile.avatarUrl,
                        radius: 48,
                      ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Material(
                    color: kGreen,
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: 'Change photo',
                      onPressed: _saving ? null : _pickAvatar,
                      icon: const Icon(
                        Icons.camera_alt_rounded,
                        color: kWhite,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const FormLabel(text: 'Username'),
          const SizedBox(height: 6),
          _Field(
            controller: _username,
            enabled: !_saving,
            hint: 'letters, numbers, _ or .',
            maxLength: 30,
          ),
          const SizedBox(height: 12),
          const FormLabel(text: 'Display name'),
          const SizedBox(height: 6),
          _Field(
            controller: _displayName,
            enabled: !_saving,
            hint: 'Shown instead of your username',
            maxLength: 50,
          ),
          const SizedBox(height: 12),
          const FormLabel(text: 'Bio'),
          const SizedBox(height: 6),
          _Field(
            controller: _bio,
            enabled: !_saving,
            hint: 'Tell people about yourself',
            maxLength: 300,
            maxLines: 4,
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            value: _isPrivate,
            onChanged: _saving ? null : (v) => setState(() => _isPrivate = v),
            activeThumbColor: kGreen,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Private account',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: const Text(
              'Only followers you approve can see your posts. '
              'Turning this off approves all waiting requests.',
            ),
          ),
          SwitchListTile(
            value: _savedPublic,
            onChanged: _saving ? null : (v) => setState(() => _savedPublic = v),
            activeThumbColor: kGreen,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Show my saved posts',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: const Text(
              'Let other people see the Saved tab on your profile.',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: kRed)),
          ],
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.enabled,
    required this.hint,
    required this.maxLength,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final bool enabled;
  final String hint;
  final int maxLength;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      maxLength: maxLength,
      maxLines: maxLines,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: kCardWhite,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
