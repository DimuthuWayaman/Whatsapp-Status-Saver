import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../models/status_item.dart';
import '../services/status_service.dart';
import '../widgets/status_grid.dart';

class PreviewScreen extends StatefulWidget {
  const PreviewScreen({
    super.key,
    required this.service,
    required this.items,
    required this.initialIndex,
    this.savedMode = false,
  });

  final StatusService service;
  final List<StatusItem> items;
  final int initialIndex;
  final bool savedMode;

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  late final PageController _pager = PageController(initialPage: widget.initialIndex);
  late final List<StatusItem> _items = List.of(widget.items);
  late int _index = widget.initialIndex;
  bool _zoomed = false;
  bool _chrome = true;

  StatusItem get _current => _items[_index];

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  void _toggleChrome() => setState(() => _chrome = !_chrome);

  Future<void> _share({String? target}) async {
    try {
      await widget.service.share(_current, targetPkg: target);
    } catch (e) {
      debugPrint('StatusSaver share error: $e');
      if (!mounted) return;
      final msg = e is PlatformException ? e.message : '$e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${target != null ? 'Repost' : 'Share'} failed: $msg')),
      );
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete from saved?'),
        content: const Text('This removes the file from your gallery.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.service.delete(_current);
    if (!mounted) return;
    setState(() {
      _items.removeAt(_index);
      if (_index >= _items.length) _index = _items.length - 1;
    });
    if (_items.isEmpty) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            PageView.builder(
              controller: _pager,
              physics: _zoomed ? const NeverScrollableScrollPhysics() : const BouncingScrollPhysics(),
              itemCount: _items.length,
              onPageChanged: (i) => setState(() {
                _index = i;
                _zoomed = false;
              }),
              itemBuilder: (context, i) {
                final item = _items[i];
                return item.isVideo
                    ? _VideoPage(
                        key: ValueKey(item.uri),
                        service: widget.service,
                        item: item,
                        active: i == _index,
                        onTap: _toggleChrome,
                      )
                    : _ImagePage(
                        key: ValueKey(item.uri),
                        service: widget.service,
                        item: item,
                        onTap: _toggleChrome,
                        onZoomChanged: (z) => setState(() => _zoomed = z),
                      );
              },
            ),
            // Top bar
            AnimatedPositioned(
              duration: const Duration(milliseconds: 220),
              top: _chrome ? 0 : -(padding.top + 80),
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(4, padding.top + 4, 16, 16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _current.isVideo ? 'Video status' : 'Photo status',
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                          Text(
                            timeAgo(_current.lastModified),
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_index + 1} / ${_items.length}',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Bottom actions
            AnimatedPositioned(
              duration: const Duration(milliseconds: 220),
              bottom: _chrome ? padding.bottom + 20 : -120,
              left: 24,
              right: 24,
              child: ListenableBuilder(
                listenable: widget.service,
                builder: (context, _) {
                  final saved = widget.service.isSaved(_current);
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xCC1F2C34),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        if (widget.savedMode)
                          _Action(icon: Icons.delete_outline_rounded, label: 'Delete', onTap: _delete)
                        else
                          _Action(
                            icon: saved ? Icons.check_circle_rounded : Icons.download_rounded,
                            label: saved ? 'Saved' : 'Save',
                            highlight: true,
                            onTap: saved ? null : () => saveWithFeedback(context, widget.service, _current),
                          ),
                        _Action(icon: Icons.share_rounded, label: 'Share', onTap: () => _share()),
                        _Action(
                          icon: Icons.repeat_rounded,
                          label: 'Repost',
                          onTap: () => _share(target: widget.service.app.pkg),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, this.onTap, this.highlight = false});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final color = highlight ? const Color(0xFF25D366) : Colors.white;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ image

class _ImagePage extends StatefulWidget {
  const _ImagePage({
    super.key,
    required this.service,
    required this.item,
    required this.onTap,
    required this.onZoomChanged,
  });

  final StatusService service;
  final StatusItem item;
  final VoidCallback onTap;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ImagePage> createState() => _ImagePageState();
}

class _ImagePageState extends State<_ImagePage> with SingleTickerProviderStateMixin {
  final _transform = TransformationController();
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  Animation<Matrix4>? _zoomAnim;
  Offset _tapPos = Offset.zero;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _anim.addListener(() => _transform.value = _zoomAnim!.value);
    _transform.addListener(() {
      final z = _transform.value.getMaxScaleOnAxis() > 1.01;
      if (z != _zoomed) {
        _zoomed = z;
        widget.onZoomChanged(z);
      }
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _doubleTap() {
    final Matrix4 end;
    if (_zoomed) {
      end = Matrix4.identity();
    } else {
      const scale = 2.5;
      end = Matrix4.identity()
        ..translateByDouble(-_tapPos.dx * (scale - 1), -_tapPos.dy * (scale - 1), 0, 1)
        ..scaleByDouble(scale, scale, 1, 1);
    }
    _zoomAnim = Matrix4Tween(begin: _transform.value, end: end)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));
    _anim.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onDoubleTapDown: (d) => _tapPos = d.localPosition,
      onDoubleTap: _doubleTap,
      child: InteractiveViewer(
        transformationController: _transform,
        minScale: 1,
        maxScale: 5,
        child: SizedBox.expand(
          child: Hero(
            tag: widget.item.heroTag,
            child: FutureBuilder<String>(
              future: widget.service.localPath(widget.item),
              builder: (context, snap) => snap.hasData
                  ? Image.file(File(snap.data!), fit: BoxFit.contain)
                  : const Center(child: CircularProgressIndicator(color: Colors.white)),
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ video

class _VideoPage extends StatefulWidget {
  const _VideoPage({
    super.key,
    required this.service,
    required this.item,
    required this.active,
    required this.onTap,
  });

  final StatusService service;
  final StatusItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  VideoPlayerController? _controller;
  bool _failed = false;
  bool _showIcon = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final path = await widget.service.localPath(widget.item);
      final c = VideoPlayerController.file(File(path));
      await c.initialize();
      await c.setLooping(true);
      if (!mounted) {
        c.dispose();
        return;
      }
      setState(() => _controller = c);
      if (widget.active) c.play();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void didUpdateWidget(covariant _VideoPage old) {
    super.didUpdateWidget(old);
    final c = _controller;
    if (c == null || old.active == widget.active) return;
    if (widget.active) {
      c.play();
    } else {
      c.pause();
      c.seekTo(Duration.zero);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null) return;
    setState(() {
      c.value.isPlaying ? c.pause() : c.play();
      _showIcon = true;
    });
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _showIcon = false);
    });
  }

  String _fmt(Duration d) =>
      '${d.inMinutes.remainder(60).toString().padLeft(1, '0')}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _togglePlay();
        widget.onTap();
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (c == null)
            Hero(
              tag: widget.item.heroTag,
              child: StatusThumbnail(
                service: widget.service,
                item: widget.item,
                fit: BoxFit.contain,
                cacheWidth: null,
              ),
            )
          else
            Hero(
              tag: widget.item.heroTag,
              child: AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c)),
            ),
          if (c == null && !_failed) const CircularProgressIndicator(color: Colors.white),
          if (_failed)
            const Text('Unable to play this video', style: TextStyle(color: Colors.white70)),
          if (c != null)
            AnimatedOpacity(
              opacity: _showIcon || !c.value.isPlaying ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                child: Icon(
                  c.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 44,
                ),
              ),
            ),
          if (c != null)
            Positioned(
              left: 24,
              right: 24,
              bottom: MediaQuery.paddingOf(context).bottom + 110,
              child: ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: c,
                builder: (context, v, _) => Row(
                  children: [
                    Text(_fmt(v.position), style: const TextStyle(color: Colors.white, fontSize: 12)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: VideoProgressIndicator(
                          c,
                          allowScrubbing: true,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          colors: const VideoProgressColors(
                            playedColor: Color(0xFF25D366),
                            bufferedColor: Colors.white38,
                            backgroundColor: Colors.white24,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(_fmt(v.duration), style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
