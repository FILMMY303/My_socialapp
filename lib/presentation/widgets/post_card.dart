import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/time_ago.dart';
import '../../data/models/models.dart';
import '../../data/repositories/social_repository.dart';
import '../../data/repository_scope.dart';
import '../../data/services/report_service.dart';
import '../navigation.dart';
import '../screens/comments_sheet.dart';
import 'common_widgets.dart';
import 'media_view.dart';

class PostCard extends StatelessWidget {
  const PostCard({super.key, required this.item, this.isGroupAdmin = false});

  final FeedPost item;

  /// Group owners/admins may delete other members' posts.
  final bool isGroupAdmin;

  Future<void> _react(BuildContext context, ReactionType? type) async {
    try {
      await RepositoryScope.of(context).setReaction(item.post.id, type);
    } catch (error) {
      if (context.mounted) showErrorSnackBar(context, error);
    }
  }

  /// Shows the emoji bar just above the Like button ([anchor]).
  Future<void> _pickEmoji(BuildContext context, BuildContext anchor) async {
    final box = anchor.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final buttonTopLeft = box.localToGlobal(Offset.zero);

    final picked = await showGeneralDialog<ReactionType>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close reactions',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (dialogContext, _, _) {
        final screen = MediaQuery.sizeOf(dialogContext);
        final left = buttonTopLeft.dx
            .clamp(
              8.0,
              (screen.width - _ReactionBar.width - 8).clamp(
                8.0,
                double.infinity,
              ),
            )
            .toDouble();
        final top = (buttonTopLeft.dy - _ReactionBar.height - 8)
            .clamp(8.0, double.infinity)
            .toDouble();
        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: _ReactionBar(
                selected: item.myReaction,
                onPick: (type) => Navigator.of(dialogContext).pop(type),
              ),
            ),
          ],
        );
      },
      transitionBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
        );
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween(begin: 0.6, end: 1.0).animate(curved),
            alignment: Alignment.bottomLeft,
            child: child,
          ),
        );
      },
    );
    if (picked != null && context.mounted) {
      await _react(context, picked == item.myReaction ? null : picked);
    }
  }

  Future<void> _share(BuildContext context) async {
    final post = item.post;
    if (post.isShare && post.shared == null) {
      showErrorSnackBar(
        context,
        const AppException('The original post is no longer available.'),
      );
      return;
    }
    final repository = RepositoryScope.of(context);
    final shared = await showDialog<bool>(
      context: context,
      builder: (_) => _ShareDialog(
        target: post.shareTarget,
        onShare: (caption) => repository.createPost(caption, share: post),
      ),
    );
    if (shared == true && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Shared to your timeline.')));
    }
  }

  Future<void> _toggleSaved(BuildContext context) async {
    final saved = RepositoryScope.servicesOf(context).saved;
    final save = !saved.isSaved(item.post.id);
    try {
      await saved.setSaved(item.post.id, save);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              save ? 'Saved. Find it on your profile.' : 'Removed from saved.',
            ),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) showErrorSnackBar(context, error);
    }
  }

  Future<void> _edit(BuildContext context) async {
    final repository = RepositoryScope.of(context);
    await showEditTextDialog(
      context,
      title: 'Edit post',
      initialText: item.post.content,
      maxLength: SocialRepository.maxPostLength,
      onSave: (text) => repository.updatePost(item.post.id, text),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final repository = RepositoryScope.of(context);
    if (!await confirmDelete(context, 'post')) return;
    try {
      await repository.deletePost(item.post.id, asGroupAdmin: !item.isMine);
    } catch (error) {
      if (context.mounted) showErrorSnackBar(context, error);
    }
  }

  Future<void> _report(BuildContext context) async {
    final services = RepositoryScope.servicesOf(context);
    final reported = await showDialog<bool>(
      context: context,
      builder: (_) => _ReportDialog(
        onSubmit: (reason, details) =>
            services.reports.reportPost(item.post.id, reason, details: details),
      ),
    );
    if (reported == true && context.mounted) {
      await services.repository.hidePost(item.post.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Thanks. The post was reported and hidden for you.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = item.post;
    final mine = item.myReaction;
    final emojiReaction = mine != null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kCardWhite,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => openProfile(context, post.userId),
                child: UserAvatar(name: post.username, url: post.avatarUrl),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () => openProfile(context, post.userId),
                      child: Text(
                        post.username,
                        style: TextStyle(
                          color: kMainText,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          timeAgo(post.createdAt) +
                              (post.isEdited ? ' · Edited' : ''),
                          style: TextStyle(fontSize: 11, color: kMuted),
                        ),
                        if (post.syncStatus == SyncStatus.pending) ...[
                          const SizedBox(width: 6),
                          Tooltip(
                            message: 'Waiting to sync',
                            child: Icon(
                              Icons.cloud_upload_outlined,
                              size: 14,
                              color: kMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_horiz_rounded, color: kSecondaryText),
                onSelected: (value) => switch (value) {
                  'edit' => _edit(context),
                  'delete' => _delete(context),
                  'save' => _toggleSaved(context),
                  _ => _report(context),
                },
                itemBuilder: (menuContext) => [
                  PopupMenuItem(
                    value: 'save',
                    child: Text(
                      RepositoryScope.servicesOf(context).saved.isSaved(post.id)
                          ? 'Unsave post'
                          : 'Save post',
                    ),
                  ),
                  if (item.isMine)
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  if (item.isMine || isGroupAdmin)
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete', style: TextStyle(color: kRed)),
                    ),
                  if (!item.isMine)
                    const PopupMenuItem(
                      value: 'report',
                      child: Text('Report post'),
                    ),
                ],
              ),
            ],
          ),
          if (post.content.isNotEmpty) ...[
            const SizedBox(height: 12),
            LinkedText(post.content),
          ],
          if (post.media != null) ...[
            const SizedBox(height: 12),
            MediaView(url: post.media!.url, type: post.media!.type),
          ],
          if (post.isShare) ...[
            const SizedBox(height: 12),
            SharedPostPreview(post: post.shared),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              if (item.emojiTotal > 0) ...[
                Text(
                  item.topEmoji.take(3).map((t) => t.emoji).join(),
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(width: 4),
                Text(
                  '${item.emojiTotal}',
                  style: TextStyle(fontSize: 11, color: kSecondaryText),
                ),
                const SizedBox(width: 10),
              ],
              const Spacer(),
              GestureDetector(
                onTap: () => showCommentsSheet(context, post),
                child: Text(
                  '${item.comments} Comments',
                  style: TextStyle(fontSize: 11, color: kSecondaryText),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: 'Hold for more reactions',
                  // The builder context is the button, so the picker can
                  // open right above it.
                  child: Builder(
                    builder: (button) => _ReactionButton(
                      icon: Icons.thumb_up_alt_outlined,
                      emoji: emojiReaction ? mine.emoji : null,
                      label: emojiReaction ? mine.label : 'Like',
                      selected: emojiReaction,
                      onTap: () => _react(
                        context,
                        emojiReaction ? null : ReactionType.like,
                      ),
                      onLongPress: () => _pickEmoji(context, button),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _ReactionButton(
                  icon: Icons.comment_outlined,
                  label: 'Comment',
                  onTap: () => showCommentsSheet(context, post),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _ReactionButton(
                  icon: Icons.share_outlined,
                  label: 'Share',
                  onTap: () => _share(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Row of emoji that pops up above the Like button.
class _ReactionBar extends StatelessWidget {
  const _ReactionBar({required this.selected, required this.onPick});

  static const double size = 40;
  static const double width =
      size * 7 + 12 * 2; // seven emoji (incl. dislike) + horizontal padding
  static const double height = size + 12;

  final ReactionType? selected;
  final ValueChanged<ReactionType> onPick;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kCardWhite,
      elevation: 6,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(height / 2),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final type in ReactionType.emojiReactions)
              _EmojiButton(
                type: type,
                selected: type == selected,
                onTap: () => onPick(type),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmojiButton extends StatefulWidget {
  const _EmojiButton({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  final ReactionType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_EmojiButton> createState() => _EmojiButtonState();
}

class _EmojiButtonState extends State<_EmojiButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.type.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _hover ? 1.3 : 1,
            duration: const Duration(milliseconds: 120),
            child: Container(
              width: _ReactionBar.size,
              height: _ReactionBar.size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.selected ? kPaleGreen : Colors.transparent,
              ),
              child: Text(
                widget.type.emoji,
                style: const TextStyle(fontSize: 28),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Text in which #hashtags open the tag feed.
class LinkedText extends StatefulWidget {
  const LinkedText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  State<LinkedText> createState() => _LinkedTextState();
}

class _LinkedTextState extends State<LinkedText> {
  static final _tag = RegExp(r'#[^\s\p{P}]+', unicode: true);
  final _recognizers = <TapGestureRecognizer>[];

  void _clear() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _clear();
    final text = widget.text;
    final spans = <InlineSpan>[];
    var last = 0;
    for (final match in _tag.allMatches(text)) {
      if (match.start > last) {
        spans.add(TextSpan(text: text.substring(last, match.start)));
      }
      final tag = match.group(0)!;
      final recognizer = TapGestureRecognizer()
        ..onTap = () => openTag(context, tag);
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: tag,
          recognizer: recognizer,
          style: const TextStyle(color: kGreen, fontWeight: FontWeight.w600),
        ),
      );
      last = match.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));

    return Text.rich(
      TextSpan(children: spans),
      style: widget.style ?? TextStyle(fontSize: 14, color: kMainText),
    );
  }
}

class _ReactionButton extends StatelessWidget {
  const _ReactionButton({
    required this.icon,
    required this.label,
    this.emoji,
    this.selected = false,
    required this.onTap,
    this.onLongPress,
  });

  final IconData icon;
  final String label;
  final String? emoji;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      onSecondaryTap: onLongPress,
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: selected ? kPaleGreen : const Color(0xFFF6F7FB),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (emoji != null)
              Text(emoji!, style: const TextStyle(fontSize: 15))
            else
              Icon(icon, size: 16, color: selected ? kGreen : kSecondaryText),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: selected ? kGreen : kSecondaryText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog({required this.onSubmit});

  final Future<void> Function(ReportReason reason, String details) onSubmit;

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final _details = TextEditingController();
  ReportReason? _reason;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reason;
    if (reason == null) {
      setState(() => _error = 'Choose a reason.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.onSubmit(reason, _details.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = errorMessage(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Report post'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: RadioGroup<ReportReason>(
            groupValue: _reason,
            onChanged: (value) {
              if (!_sending) setState(() => _reason = value);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Why are you reporting this post?',
                  style: TextStyle(color: kSecondaryText),
                ),
                for (final reason in ReportReason.values)
                  RadioListTile<ReportReason>(
                    value: reason,
                    title: Text(reason.label),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                TextField(
                  controller: _details,
                  enabled: !_sending,
                  maxLength: ReportService.maxDetailsLength,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'More details (optional)',
                    errorText: _error,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _sending ? null : _submit,
          style: TextButton.styleFrom(foregroundColor: kRed),
          child: const Text('Report'),
        ),
      ],
    );
  }
}

/// The original post inside a share. [post] is null when it was deleted or
/// is hidden from the viewer.
class SharedPostPreview extends StatelessWidget {
  const SharedPostPreview({super.key, required this.post});

  final Post? post;

  @override
  Widget build(BuildContext context) {
    final post = this.post;
    final border = BoxDecoration(
      border: Border.all(color: const Color(0xFFE3E6EC)),
      borderRadius: BorderRadius.circular(18),
    );
    if (post == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: border,
        child: Text(
          'This post is no longer available.',
          style: TextStyle(color: kSecondaryText),
        ),
      );
    }
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => openPost(context, post.id),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: border,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                UserAvatar(
                  name: post.username,
                  url: post.avatarUrl,
                  radius: 14,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    post.username,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  timeAgo(post.createdAt),
                  style: TextStyle(fontSize: 11, color: kMuted),
                ),
              ],
            ),
            if (post.content.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(post.content, maxLines: 6, overflow: TextOverflow.ellipsis),
            ],
            if (post.media != null) ...[
              const SizedBox(height: 8),
              MediaView(
                url: post.media!.url,
                type: post.media!.type,
                maxHeight: 260,
                borderRadius: 12,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ShareDialog extends StatefulWidget {
  const _ShareDialog({required this.target, required this.onShare});

  final Post target;
  final Future<void> Function(String caption) onShare;

  @override
  State<_ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends State<_ShareDialog> {
  final _caption = TextEditingController();
  bool _sharing = false;
  String? _error;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    setState(() {
      _sharing = true;
      _error = null;
    });
    try {
      await widget.onShare(_caption.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _sharing = false;
          _error = errorMessage(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Share post'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _caption,
                enabled: !_sharing,
                autofocus: true,
                minLines: 1,
                maxLines: 4,
                maxLength: SocialRepository.maxPostLength,
                decoration: InputDecoration(
                  hintText: 'Say something about this…',
                  errorText: _error,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              IgnorePointer(child: SharedPostPreview(post: widget.target)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sharing ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _sharing ? null : _share,
          style: FilledButton.styleFrom(backgroundColor: kGreen),
          child: const Text('Share now'),
        ),
      ],
    );
  }
}
