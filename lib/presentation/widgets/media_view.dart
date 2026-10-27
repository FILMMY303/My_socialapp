import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/time_ago.dart';
import '../../data/models/models.dart';

/// Round avatar showing the profile picture or the first letter of [name].
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.name, this.url, this.radius = 22});

  final String name;
  final String? url;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final fallback = Text(
      initialOf(name),
      style: TextStyle(
        color: kGreen,
        fontWeight: FontWeight.w700,
        fontSize: radius * 0.8,
      ),
    );
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFB6E5D8),
      child: url == null
          ? fallback
          : ClipOval(
              child: Image.network(
                url!,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
            ),
    );
  }
}

/// Rounded-square picture of a page/group, or a flag icon when it has none.
class PageAvatar extends StatelessWidget {
  const PageAvatar({super.key, required this.name, this.url, this.radius = 22});

  final String name;
  final String? url;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    final fallback = Container(
      width: size,
      height: size,
      color: const Color(0xFFE8EEFF),
      child: Icon(
        Icons.flag_rounded,
        color: const Color(0xFF3B5BDB),
        size: radius,
      ),
    );
    return Tooltip(
      message: name,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size / 3),
        child: url == null
            ? fallback
            : Image.network(
                url!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

/// Shows an image or a playable video from [url].
class MediaView extends StatelessWidget {
  const MediaView({
    super.key,
    required this.url,
    required this.type,
    this.maxHeight = 360,
    this.borderRadius = 18,
  });

  final String url;
  final MediaType type;
  final double maxHeight;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: type == MediaType.image
            ? GestureDetector(
                onTap: () => _openFullScreen(context),
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  loadingBuilder: (context, child, progress) =>
                      progress == null ? child : const _MediaPlaceholder(),
                  errorBuilder: (_, _, _) => const _MediaError(),
                ),
              )
            : VideoView(url: url),
      ),
    );
  }

  void _openFullScreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.network(
                url,
                errorBuilder: (_, _, _) => const _MediaError(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Video with tap-to-play/pause and a progress bar.
class VideoView extends StatefulWidget {
  const VideoView({super.key, required this.url});

  final String url;

  @override
  State<VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends State<VideoView> {
  late final VideoPlayerController _controller =
      VideoPlayerController.networkUrl(Uri.parse(widget.url));
  late final Future<void> _initialized = _controller.initialize();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initialized,
      builder: (context, snapshot) {
        if (snapshot.hasError) return const _MediaError(video: true);
        if (snapshot.connectionState != ConnectionState.done) {
          return const _MediaPlaceholder();
        }
        return AspectRatio(
          aspectRatio: _controller.value.aspectRatio,
          child: Stack(
            alignment: Alignment.center,
            children: [
              GestureDetector(
                onTap: () => setState(() {
                  _controller.value.isPlaying
                      ? _controller.pause()
                      : _controller.play();
                }),
                child: VideoPlayer(_controller),
              ),
              ValueListenableBuilder(
                valueListenable: _controller,
                builder: (context, value, _) => value.isPlaying
                    ? const SizedBox.shrink()
                    : IgnorePointer(
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: const BoxDecoration(
                            color: Colors.black45,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 40,
                          ),
                        ),
                      ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: VideoProgressIndicator(
                  _controller,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(playedColor: kGreen),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MediaPlaceholder extends StatelessWidget {
  const _MediaPlaceholder();

  @override
  Widget build(BuildContext context) => Container(
    height: 200,
    color: const Color(0xFFEDEFF3),
    alignment: Alignment.center,
    child: const CircularProgressIndicator(color: kGreen, strokeWidth: 2),
  );
}

class _MediaError extends StatelessWidget {
  const _MediaError({this.video = false});

  final bool video;

  @override
  Widget build(BuildContext context) => Container(
    height: 160,
    color: const Color(0xFFEDEFF3),
    alignment: Alignment.center,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          video ? Icons.videocam_off_rounded : Icons.broken_image_rounded,
          color: kMuted,
        ),
        const SizedBox(height: 6),
        Text(
          video ? 'Could not play this video' : 'Could not load this image',
          style: TextStyle(color: kMuted, fontSize: 12),
        ),
      ],
    ),
  );
}
