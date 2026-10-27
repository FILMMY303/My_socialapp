import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/models.dart';
import '../../data/repositories/social_repository.dart';
import '../../data/repository_scope.dart';
import '../widgets/common_widgets.dart';

/// Writes a post with optional image or short video, on the home timeline
/// or inside a group ([groupId]).
class ComposerScreen extends StatefulWidget {
  const ComposerScreen({
    super.key,
    required this.onBack,
    this.groupId,
    this.groupName,
  });

  final VoidCallback onBack;
  final String? groupId;
  final String? groupName;

  @override
  State<ComposerScreen> createState() => _ComposerScreenState();
}

class _ComposerScreenState extends State<ComposerScreen> {
  final _contentController = TextEditingController();
  XFile? _file;
  MediaType? _fileType;
  Uint8List? _imageBytes;
  bool _isSubmitting = false;
  String _status = '';
  String? _errorMessage;

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _pick(MediaType type) async {
    setState(() => _errorMessage = null);
    try {
      final file = await RepositoryScope.servicesOf(context).media.pick(type);
      if (file == null) return;
      final bytes = type == MediaType.image ? await file.readAsBytes() : null;
      setState(() {
        _file = file;
        _fileType = type;
        _imageBytes = bytes;
      });
    } catch (error) {
      if (mounted) setState(() => _errorMessage = errorMessage(error));
    }
  }

  Future<void> _submitPost() async {
    final services = RepositoryScope.servicesOf(context);
    final text = _contentController.text;
    if (text.trim().isEmpty && _file == null) {
      setState(() => _errorMessage = 'Write something or add a photo/video.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    MediaRef? media;
    try {
      if (_file != null) {
        // Uploads need a connection; the post itself is saved offline-first.
        setState(() => _status = 'Uploading ${_fileType!.name}…');
        media = await services.media.uploadPostMedia(_file!, _fileType!);
      }
      setState(() => _status = 'Posting…');
      await services.repository.createPost(
        text,
        groupId: widget.groupId,
        media: media,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Post published.')));
      widget.onBack();
    } catch (error) {
      if (media != null) {
        await services.media.deletePublicFile('post-media', media.url);
      }
      if (mounted) setState(() => _errorMessage = errorMessage(error));
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _status = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCream,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                    onPressed: _isSubmitting ? null : widget.onBack,
                    icon: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: kMainText,
                    ),
                  ),
                  Expanded(
                    child: widget.groupName == null
                        ? const BrandHeader()
                        : Text(
                            'Post in ${widget.groupName}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                  TextButton(
                    onPressed: _isSubmitting ? null : _submitPost,
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: kGreen,
                            ),
                          )
                        : const Text(
                            'Post',
                            style: TextStyle(
                              color: kGreen,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  decoration: BoxDecoration(
                    color: kCardWhite,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _contentController,
                          enabled: !_isSubmitting,
                          maxLines: null,
                          expands: true,
                          maxLength: SocialRepository.maxPostLength,
                          textAlignVertical: TextAlignVertical.top,
                          decoration: InputDecoration(
                            hintText: 'Post something… use #tags',
                            hintStyle: TextStyle(color: kMuted, fontSize: 16),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                      if (_file != null) _buildAttachment(),
                      if (_status.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(_status, style: TextStyle(color: kSecondaryText)),
                      ],
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _errorMessage!,
                          style: const TextStyle(color: kRed, fontSize: 13),
                        ),
                      ],
                      const Divider(),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: _isSubmitting
                                ? null
                                : () => _pick(MediaType.image),
                            icon: const Icon(Icons.image_outlined),
                            label: const Text('Photo'),
                          ),
                          TextButton.icon(
                            onPressed: _isSubmitting
                                ? null
                                : () => _pick(MediaType.video),
                            icon: const Icon(Icons.videocam_outlined),
                            label: const Text('Short video'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAttachment() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: _imageBytes != null
                ? Image.memory(_imageBytes!, height: 160, fit: BoxFit.cover)
                : Container(
                    height: 80,
                    width: double.infinity,
                    color: const Color(0xFFEDEFF3),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.movie_outlined, color: kSecondaryText),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _file!.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: 'Remove',
                iconSize: 18,
                onPressed: _isSubmitting
                    ? null
                    : () => setState(() {
                        _file = null;
                        _fileType = null;
                        _imageBytes = null;
                      }),
                icon: const Icon(Icons.close_rounded, color: kWhite),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
