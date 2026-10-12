import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:open_filex/open_filex.dart';

class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({super.key, required this.path, required this.title});
  final String path;
  final String title;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final Player _player;
  late final VideoController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _player = Player();
    _controller = VideoController(_player);
    _open();
  }

  Future<void> _open() async {
    try {
      await _player.open(Media(widget.path));
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              tooltip: 'Открыть во внешнем плеере',
              icon: const Icon(Icons.open_in_new),
              onPressed: () async {
                final result = await OpenFilex.open(widget.path, type: 'video/mp4');
                if (!context.mounted) return;
                if (result.type != ResultType.done) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не удалось открыть файл: ${result.message}')));
                }
              },
            ),
          ],
        ),
        body: Center(
          child: _error != null
              ? Padding(padding: const EdgeInsets.all(24), child: Text('Ошибка воспроизведения: $_error', style: const TextStyle(color: Colors.white)))
              : Video(controller: _controller, controls: MaterialVideoControls),
        ),
      );
}
