import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Виджет, который рисует движущийся маркер вдоль трека.
/// Работает через AnimationController, без внешних пакетов.
class AnimatedTrackMarker extends StatefulWidget {
  final List<LatLng> points;
  final Duration duration;
  final bool autoplay;
  final VoidCallback? onFinished;

  const AnimatedTrackMarker({
    super.key,
    required this.points,
    this.duration = const Duration(seconds: 30),
    this.autoplay = true,
    this.onFinished,
  });

  @override
  State<AnimatedTrackMarker> createState() => AnimatedTrackMarkerState();
}

class AnimatedTrackMarkerState extends State<AnimatedTrackMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _ctrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onFinished?.call();
    });
    if (widget.autoplay) _ctrl.forward();
  }

  @override
  void didUpdateWidget(covariant AnimatedTrackMarker old) {
    super.didUpdateWidget(old);
    if (widget.duration != old.duration) {
      _ctrl.duration = widget.duration;
    }
    if (widget.autoplay && !_ctrl.isAnimating && !_ctrl.isCompleted) {
      _ctrl.forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void play() {
    if (_ctrl.isCompleted) {
      _ctrl.forward(from: 0);
    } else {
      _ctrl.forward();
    }
  }

  void pause() => _ctrl.stop();

  void restart() => _ctrl.forward(from: 0);

  bool get isPlaying => _ctrl.isAnimating;

  @override
  Widget build(BuildContext context) {
    if (widget.points.length < 2) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final pos = _interpolate(widget.points, _ctrl.value);
        return MarkerLayer(
          markers: [
            Marker(
              point: pos,
              width: 36,
              height: 36,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: const [
                    BoxShadow(color: Colors.black45, blurRadius: 8),
                  ],
                ),
                child: const Icon(
                  Icons.navigation,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  LatLng _interpolate(List<LatLng> pts, double t) {
    final total = pts.length - 1;
    if (total < 1) return pts.first;
    final scaled = t * total;
    final seg = scaled.floor().clamp(0, total - 1);
    final local = (scaled - seg).clamp(0.0, 1.0);
    final a = pts[seg];
    final b = pts[seg + 1];
    return LatLng(
      a.latitude + (b.latitude - a.latitude) * local,
      a.longitude + (b.longitude - a.longitude) * local,
    );
  }
}
