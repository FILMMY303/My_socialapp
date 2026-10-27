import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/time_ago.dart';
import '../../data/models/models.dart';
import '../../data/repositories/social_repository.dart';
import '../../data/repository_scope.dart';
import '../navigation.dart';
import '../widgets/common_widgets.dart';
import '../widgets/media_view.dart';

/// Opens the comments of [post] in a bottom sheet.
Future<void> showCommentsSheet(BuildContext context, Post post) {
  // Sheets are built above RepositoryScope, so pass the services along.
  final services = RepositoryScope.servicesOf(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: kCream,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) => RepositoryScope(
      services: services,
      child: CommentsSheet(post: post),
    ),
  );
}

/// Comments with photos/videos and one level of replies (like Facebook):
/// replying to a reply adds to the same thread with an @mention.
class CommentsSheet extends StatefulWidget {
  const CommentsSheet({super.key, required this.post});

  final Post post;

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  AppServices? _services;
  late Stream<List<Comment>> _comments;
  bool _sending = false;
  String _status = '';
  String? _error;

  /// The comment being replied to (thread root) and who is mentioned.
  Comment? _replyTo;

  XFile? _file;
  MediaType? _fileType;
  Uint8List? _imageBytes;

  SocialRepository get _repository => _services!.repository;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = RepositoryScope.servicesOf(context);
    if (services != _services) {
      _services = services;
      _comments = services.repository.watchComments(widget.post.id);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startReply(Comment comment, List<Comment> all) {
    // Replies stay one level deep: a reply to a reply joins the same thread.
    final root = comment.parentId == null
        ? comment
        : all.firstWhere(
            (c) => c.id == comment.parentId,
            orElse: () => comment,
          );
    setState(() => _replyTo = root);
    if (comment.userId != _repository.userId) {
      final mention = '@${comment.username} ';
      if (!_controller.text.startsWith(mention)) {
        _controller.text = mention + _controller.text;
      }
    }
    _focus.requestFocus();
  }

  Future<void> _pick(MediaType type) async {
    try {
      final file = await _services!.media.pick(type);
      if (file == null) return;
      final bytes = type == MediaType.image ? await file.readAsBytes() : null;
      setState(() {
        _file = file;
        _fileType = type;
        _imageBytes = bytes;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = errorMessage(error));
    }
  }

  void _clearAttachment() => setState(() {
    _file = null;
    _fileType = null;
    _imageBytes = null;
  });

  Future<void> _send() async {
    final services = _services!;
    if (_controller.text.trim().isEmpty && _file == null) {
      setState(() => _error = 'Write something or add a photo/video.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    MediaRef? media;
    try {
      if (_file != null) {
        setState(() => _status = 'Uploading ${_fileType!.name}…');
        media = await services.media.uploadPostMedia(_file!, _fileType!);
      }
      await services.repository.addComment(
        widget.post.id,
        _controller.text,
        parentId: _replyTo?.id,
        media: media,
      );
      _controller.clear();
      _clearAttachment();
      setState(() => _replyTo = null);
    } catch (error) {
      if (media != null) {
        await services.media.deletePublicFile('post-media', media.url);
      }
      if (mounted) setState(() => _error = errorMessage(error));
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _status = '';
        });
      }
    }
  }

  Future<void> _edit(Comment comment) async {
    final repository = _repository;
    await showEditTextDialog(
      context,
      title: 'Edit comment',
      initialText: comment.content,
      maxLength: SocialRepository.maxCommentLength,
      onSave: (text) => repository.updateComment(comment.id, text),
    );
  }

  Future<void> _delete(Comment comment) async {
    final repository = _repository;
    if (!await confirmDelete(context, 'comment')) return;
    try {
      await repository.deleteComment(comment.id);
      if (_replyTo?.id == comment.id) setState(() => _replyTo = null);
    } catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.8;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: kMuted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                'Comments',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: kMainText,
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<List<Comment>>(
                stream: _comments,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Could not load comments: ${snapshot.error}',
                        style: const TextStyle(color: kRed),
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(color: kGreen),
                    );
                  }
                  final all = snapshot.data!;
                  if (all.isEmpty) {
                    return Center(
                      child: Text(
                        'No comments yet. Be the first!',
                        style: TextStyle(color: kSecondaryText),
                      ),
                    );
                  }
                  final rows = _threaded(all);
                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final comment = rows[index];
                      final isReply = comment.parentId != null;
                      return Padding(
                        padding: EdgeInsets.only(left: isReply ? 42 : 0),
                        child: _CommentTile(
                          key: ValueKey(comment.id),
                          comment: comment,
                          isReply: isReply,
                          isMine: comment.userId == _repository.userId,
                          onReply: () => _startReply(comment, all),
                          onEdit: () => _edit(comment),
                          onDelete: () => _delete(comment),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            _buildComposer(),
          ],
        ),
      ),
    );
  }

  /// Top-level comments, each followed by its replies, oldest first.
  List<Comment> _threaded(List<Comment> all) {
    final replies = <String, List<Comment>>{};
    for (final c in all.where((c) => c.parentId != null)) {
      replies.putIfAbsent(c.parentId!, () => []).add(c);
    }
    return [
      for (final root in all.where((c) => c.parentId == null)) ...[
        root,
        ...?replies[root.id],
      ],
    ];
  }

  Widget _buildComposer() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_replyTo != null)
              Padding(
                padding: const EdgeInsets.only(left: 6, bottom: 4),
                child: Row(
                  children: [
                    Icon(Icons.reply_rounded, size: 16, color: kSecondaryText),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Replying to ${_replyTo!.username}',
                        style: TextStyle(fontSize: 12, color: kSecondaryText),
                      ),
                    ),
                    InkWell(
                      onTap: _sending
                          ? null
                          : () => setState(() => _replyTo = null),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.close_rounded, size: 16),
                      ),
                    ),
                  ],
                ),
              ),
            if (_file != null) _buildAttachment(),
            if (_status.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 6, bottom: 4),
                child: Text(
                  _status,
                  style: TextStyle(fontSize: 12, color: kSecondaryText),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Add photo',
                  onPressed: _sending ? null : () => _pick(MediaType.image),
                  icon: const Icon(Icons.image_outlined, color: kGreen),
                ),
                IconButton(
                  tooltip: 'Add video',
                  onPressed: _sending ? null : () => _pick(MediaType.video),
                  icon: const Icon(Icons.videocam_outlined, color: kGreen),
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    enabled: !_sending,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: SocialRepository.maxCommentLength,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: _replyTo == null
                          ? 'Write a comment…'
                          : 'Write a reply…',
                      errorText: _error,
                      counterText: '',
                      filled: true,
                      fillColor: kCardWhite,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Send',
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded, color: kGreen),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachment() {
    return Padding(
      padding: const EdgeInsets.only(left: 6, bottom: 6),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: _imageBytes != null
                ? Image.memory(
                    _imageBytes!,
                    height: 80,
                    width: 80,
                    fit: BoxFit.cover,
                  )
                : Container(
                    height: 56,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    color: const Color(0xFFEDEFF3),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.movie_outlined),
                        const SizedBox(width: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 160),
                          child: Text(
                            _file!.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 28),
                      ],
                    ),
                  ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: InkWell(
              onTap: _sending ? null : _clearAttachment,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close_rounded, size: 16, color: kWhite),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    super.key,
    required this.comment,
    required this.isReply,
    required this.isMine,
    required this.onReply,
    required this.onEdit,
    required this.onDelete,
  });

  final Comment comment;
  final bool isReply;
  final bool isMine;
  final VoidCallback onReply;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => openProfile(context, comment.userId),
          child: UserAvatar(
            name: comment.username,
            url: comment.avatarUrl,
            radius: isReply ? 13 : 16,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                decoration: BoxDecoration(
                  color: kCardWhite,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => openProfile(context, comment.userId),
                            child: Text(
                              comment.username,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: kMainText,
                              ),
                            ),
                          ),
                        ),
                        if (comment.syncStatus == SyncStatus.pending)
                          Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Icon(
                              Icons.cloud_upload_outlined,
                              size: 14,
                              color: kMuted,
                            ),
                          ),
                        if (isMine)
                          SizedBox(
                            width: 28,
                            height: 24,
                            child: PopupMenuButton<String>(
                              padding: EdgeInsets.zero,
                              iconSize: 18,
                              icon: Icon(
                                Icons.more_vert_rounded,
                                color: kSecondaryText,
                              ),
                              onSelected: (value) =>
                                  value == 'edit' ? onEdit() : onDelete(),
                              itemBuilder: (context) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Edit'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text(
                                    'Delete',
                                    style: TextStyle(color: kRed),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    if (comment.content.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        comment.content,
                        style: TextStyle(fontSize: 13, color: kMainText),
                      ),
                    ],
                    if (comment.media != null) ...[
                      const SizedBox(height: 6),
                      MediaView(
                        url: comment.media!.url,
                        type: comment.media!.type,
                        maxHeight: 220,
                        borderRadius: 12,
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 2),
                child: Row(
                  children: [
                    Text(
                      timeAgo(comment.createdAt) +
                          (comment.isEdited ? ' · Edited' : ''),
                      style: TextStyle(fontSize: 11, color: kMuted),
                    ),
                    const SizedBox(width: 14),
                    InkWell(
                      onTap: onReply,
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          'Reply',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: kSecondaryText,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
