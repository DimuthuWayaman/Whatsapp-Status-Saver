import 'dart:io';

import 'package:flutter/material.dart';

import '../models/status_item.dart';
import '../screens/preview_screen.dart';
import '../services/status_service.dart';

class StatusGrid extends StatelessWidget {
  const StatusGrid({
    super.key,
    required this.service,
    required this.items,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyText,
    this.savedMode = false,
  });

  final StatusService service;
  final List<StatusItem> items;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyText;
  final bool savedMode;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: service.refresh,
      child: items.isEmpty
          ? _EmptyState(icon: emptyIcon, title: emptyTitle, text: emptyText)
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
              physics: const AlwaysScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.72,
              ),
              itemCount: items.length,
              itemBuilder: (context, i) => StatusTile(
                service: service,
                item: items[i],
                savedMode: savedMode,
                onTap: () => Navigator.of(context).push(
                  PageRouteBuilder(
                    opaque: false,
                    transitionDuration: const Duration(milliseconds: 300),
                    reverseTransitionDuration: const Duration(milliseconds: 250),
                    pageBuilder: (_, _, _) => PreviewScreen(
                      service: service,
                      items: items,
                      initialIndex: i,
                      savedMode: savedMode,
                    ),
                    transitionsBuilder: (_, anim, _, child) =>
                        FadeTransition(opacity: anim, child: child),
                  ),
                ),
              ),
            ),
    );
  }
}

class StatusTile extends StatelessWidget {
  const StatusTile({
    super.key,
    required this.service,
    required this.item,
    required this.onTap,
    this.savedMode = false,
  });

  final StatusService service;
  final StatusItem item;
  final VoidCallback onTap;
  final bool savedMode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Material(
        color: scheme.surfaceContainerHighest,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Hero(
                tag: item.heroTag,
                child: StatusThumbnail(service: service, item: item),
              ),
              // Bottom gradient for legibility
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 48,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black54],
                    ),
                  ),
                ),
              ),
              if (item.isVideo)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white70, width: 1.5),
                    ),
                    child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 26),
                  ),
                ),
              Positioned(
                left: 8,
                bottom: 6,
                child: Text(
                  timeAgo(item.lastModified),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (!savedMode)
                Positioned(
                  right: 4,
                  bottom: 2,
                  child: ListenableBuilder(
                    listenable: service,
                    builder: (context, _) {
                      final saved = service.isSaved(item);
                      return IconButton(
                        visualDensity: VisualDensity.compact,
                        style: IconButton.styleFrom(
                          backgroundColor: saved ? scheme.primary : Colors.black38,
                          minimumSize: const Size(30, 30),
                          padding: EdgeInsets.zero,
                        ),
                        icon: Icon(
                          saved ? Icons.check_rounded : Icons.download_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                        onPressed: saved ? null : () => saveWithFeedback(context, service, item),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Image for an item: the image itself, or a generated frame for videos.
class StatusThumbnail extends StatelessWidget {
  const StatusThumbnail({
    super.key,
    required this.service,
    required this.item,
    this.fit = BoxFit.cover,
    this.cacheWidth = 360,
  });

  final StatusService service;
  final StatusItem item;
  final BoxFit fit;
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: item.isVideo ? service.thumbnail(item) : service.localPath(item),
      builder: (context, snap) {
        final path = snap.data;
        if (path == null) {
          return snap.connectionState == ConnectionState.done
              ? const _Placeholder(broken: true)
              : const _Placeholder();
        }
        return Image.file(
          File(path),
          fit: fit,
          cacheWidth: cacheWidth,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, sync) => AnimatedOpacity(
            opacity: sync || frame != null ? 1 : 0,
            duration: const Duration(milliseconds: 250),
            child: child,
          ),
          errorBuilder: (_, _, _) => const _Placeholder(broken: true),
        );
      },
    );
  }
}

class _Placeholder extends StatefulWidget {
  const _Placeholder({this.broken = false});
  final bool broken;

  @override
  State<_Placeholder> createState() => _PlaceholderState();
}

class _PlaceholderState extends State<_Placeholder> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (widget.broken) {
      return ColoredBox(
        color: scheme.surfaceContainerHighest,
        child: Icon(Icons.broken_image_outlined, color: scheme.outline),
      );
    }
    return FadeTransition(
      opacity: Tween(begin: 0.45, end: 1.0).animate(_c),
      child: ColoredBox(color: scheme.surfaceContainerHigh),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, required this.text});

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(32, 96, 32, 32),
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.all(26),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 48, color: theme.colorScheme.onPrimaryContainer),
          ),
        ),
        const SizedBox(height: 22),
        Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text(
          text,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

Future<void> saveWithFeedback(BuildContext context, StatusService service, StatusItem item) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await service.save(item);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle_rounded, color: Colors.white),
          const SizedBox(width: 10),
          Text('${item.isVideo ? 'Video' : 'Image'} saved to gallery'),
        ]),
      ));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not save: $e')));
  }
}

String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'Just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}
