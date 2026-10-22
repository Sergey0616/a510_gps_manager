import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:open_filex/open_filex.dart';

class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({
    super.key,
    required this.path,
    required this.title,
    this.startPosition,
  });

  final String path;
  final String title;

  /// Стартовая позиция (для перехода к моменту из точки трека).
  final Duration? startPosition;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final Player _player;
  late final VideoController _controller;
  String? _error;
  bool _isPlaying = false;
  double _speed = 1.0;
  StreamSubscription<bool>? _playingSub;

  static const List<double> _speeds = [0.5, 1.0, 2.0, 4.0];

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _player = Player();
    _controller = VideoController(_player);
    _playingSub = _player.stream.playing.listen((playing) {
      if (mounted) setState(() => _isPlaying = playing);
    });
    _open();
  }

  Future<void> _open() async {
    try {
      await _player.open(Media(widget.path));
      await _player.setRate(_speed);
      final start = widget.startPosition;
      if (start != null && start > Duration.zero) {
        // Ждём, пока плеер загрузит файл, потом переходим к нужной секунде.
        await _player.stream.duration.firstWhere((d) => d > Duration.zero).timeout(
          const Duration(seconds: 8),
          onTimeout: () => Duration.zero,
        );
        await _player.seek(start);
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  void _togglePlay() {
    _player.playOrPause();
  }

  void _setSpeed(double s) {
    setState(() => _speed = s);
    _player.setRate(s);
  }

  @override
  void dispose() {
    _playingSub?.cancel();
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
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Не удалось открыть файл: ${result.message}')),
                  );
                }
              },
            ),
          ],
        ),
        body: _error != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Ошибка воспроизведения: $_error',
                  style: const TextStyle(color: Colors.white),
                ),
              )
            : Column(
                children: [
                  Expanded(
                    child: Video(
                      controller: _controller,
                      controls: MaterialVideoControls,
                    ),
                  ),
                  _BottomBar(
                    isPlaying: _isPlaying,
                    speed: _speed,
                    speeds: _speeds,
                    onTogglePlay: _togglePlay,
                    onSpeedChanged: _setSpeed,
                  ),
                ],
              ),
      );
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.isPlaying,
    required this.speed,
    required this.speeds,
    required this.onTogglePlay,
    required this.onSpeedChanged,
  });

  final bool isPlaying;
  final double speed;
  final List<double> speeds;
  final VoidCallback onTogglePlay;
  final ValueChanged<double> onSpeedChanged;

  String _label(double s) => '${s}x'.replaceAll('.0x', 'x');

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Container(
          color: Colors.black87,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              IconButton(
                iconSize: 32,
                color: Colors.white,
                tooltip: isPlaying ? 'Пауза' : 'Играть',
                icon: Icon(
                  isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                ),
                onPressed: onTogglePlay,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: speeds
                        .map(
                          (s) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: ChoiceChip(
                              label: Text(_label(s)),
                              selected: (s - speed).abs() < 0.01,
                              onSelected: (_) => onSpeedChanged(s),
                              showCheckmark: false,
                              labelStyle: const TextStyle(color: Colors.white),
                              selectedColor: Theme.of(context).colorScheme.primary,
                              backgroundColor: Colors.grey.shade800,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}
