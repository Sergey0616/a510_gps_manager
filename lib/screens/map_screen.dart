import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/gps_point.dart';
import '../models/track.dart';
import '../models/video_file.dart';
import '../providers/tracks_provider.dart';
import '../services/video_service.dart';
import 'video_player_screen.dart';
import '../widgets/animated_track_marker.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key, this.initialTrackId});
  final String? initialTrackId;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  final GlobalKey<AnimatedTrackMarkerState> _animKey = GlobalKey();
  Track? _selectedTrack;
  static const _colors = <Color>[Colors.blue, Colors.deepPurple, Colors.orange, Colors.teal, Colors.pink, Colors.indigo, Colors.brown, Colors.cyan];

  void _fitAll(List<Track> tracks) {
    final points = tracks.expand((track) => track.points).toList();
    if (points.isEmpty) return;
    _mapController.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(points.map((point) => point.position).toList()),
      padding: const EdgeInsets.all(48),
      maxZoom: 16,
    ));
  }

  void _showTrack(Track track) {
    setState(() => _selectedTrack = track);
    showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (_) => _TrackDetails(track: track));
  }

  /// Расстояние между точками в метрах (упрощённая формула).
  double _distanceMeters(LatLng a, LatLng b) {
    final dlat = (a.latitude - b.latitude) * 111320.0;
    final dlon = (a.longitude - b.longitude) * 111320.0 * math.cos(a.latitude * math.pi / 180.0);
    return math.sqrt(dlat * dlat + dlon * dlon);
  }

  /// Long-press по карте → ближайшая точка маршрута → bottom sheet.
  /// Приоритет — точки с videoName (можно открыть видео).
  Future<void> _handleLongPress(LatLng tapPoint, List<Track> tracks) async {
    GpsPoint? nearest;
    GpsPoint? nearestWithVideo;
    double bestDist = double.infinity;
    double bestVideoDist = double.infinity;

    for (final track in tracks) {
      for (final p in track.points) {
        final d = _distanceMeters(tapPoint, p.position);
        if (d < bestDist) {
          bestDist = d;
          nearest = p;
        }
        if (p.videoName != null && p.videoName!.isNotEmpty && d < bestVideoDist) {
          bestVideoDist = d;
          nearestWithVideo = p;
        }
      }
    }

    GpsPoint? chosen;
    if (nearestWithVideo != null && bestVideoDist <= 1500) {
      chosen = nearestWithVideo;
    } else if (nearest != null && bestDist <= 300) {
      chosen = nearest;
    }

    if (chosen == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Рядом нет точек маршрута. Приблизьте карту и нажмите ещё раз.'),
        ));
      }
      return;
    }
    if (!mounted) return;
    final point = chosen;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _PointDetails(point: point, onOpenVideo: () => _openVideoAt(point)),
    );
  }

  /// Открывает видео с точки: проверяет, скачано ли, и передаёт startPosition.
  Future<void> _openVideoAt(GpsPoint point) async {
    final name = point.videoName;
    if (name == null || name.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Для этой точки нет привязки к видео'),
        ));
      }
      return;
    }
    final videoStart = VideoFile.parseDateFromName(name);
    if (videoStart == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Не удалось определить время начала видео из имени'),
        ));
      }
      return;
    }
    final videoStartUtc = videoStart.toUtc().millisecondsSinceEpoch ~/ 1000;
    final offsetSec = (point.timestamp - videoStartUtc).clamp(0, 3600);

    final provider = context.read<TracksProvider>();
    final videoService = VideoService(host: provider.host, username: provider.username, password: provider.password);
    final root = await videoService.videoRootPath();
    final video = VideoFile.fromName(name);
    final localFile = File('$root/${video.category.folderName}/$name');

    if (!await localFile.exists()) {
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Видео не скачано'),
          content: Text('Файл $name отсутствует локально.\n\nСкачать его с регистратора (~100–200 МБ)?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Скачать')),
          ],
        ),
      );
      if (confirmed != true) return;
      if (!mounted) return;

      // State: прогресс в МБ, скорость и ETA.
      final downloadedMb = ValueNotifier<double>(0);
      final totalMb = ValueNotifier<double>(0);
      final speedMbs = ValueNotifier<double>(0);
      final etaSec = ValueNotifier<int?>(null);

      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: Text('Скачивание $name', maxLines: 1, overflow: TextOverflow.ellipsis),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ValueListenableBuilder<double>(
                valueListenable: totalMb,
                builder: (_, total, __) => ValueListenableBuilder<double>(
                  valueListenable: downloadedMb,
                  builder: (_, done, __) {
                    final known = total > 0;
                    final fraction = known ? (done / total).clamp(0.0, 1.0) : null;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LinearProgressIndicator(value: fraction),
                        const SizedBox(height: 8),
                        Text(known
                            ? '${done.toStringAsFixed(1)} / ${total.toStringAsFixed(1)} МБ (${(fraction! * 100).toStringAsFixed(0)}%)'
                            : 'Скачано: ${done.toStringAsFixed(1)} МБ'),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              ValueListenableBuilder<double>(
                valueListenable: speedMbs,
                builder: (_, s, __) => Text('Скорость: ${s.toStringAsFixed(2)} МБ/с'),
              ),
              ValueListenableBuilder<int?>(
                valueListenable: etaSec,
                builder: (_, e, __) => Text(e == null ? 'Осталось: —' : 'Осталось: $e сек'),
              ),
            ],
          ),
        ),
      );

      // Небольшая задержка, чтобы диалог точно отрисовался.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      try {
        await videoService.download(video, onProgress: (received, total, speed, remaining) {
          downloadedMb.value = received / (1024 * 1024);
          // total может быть 0 для VideoFile.fromName — но download передаёт received.size когда не знает.
          if (total > 0) totalMb.value = total / (1024 * 1024);
          speedMbs.value = speed / (1024 * 1024);
          etaSec.value = remaining?.inSeconds;
        });
      } catch (e) {
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка скачивания: $e')));
        }
        return;
      }
      if (mounted) Navigator.of(context).pop();
    }

    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => VideoPlayerScreen(
        path: localFile.path,
        title: name,
        startPosition: Duration(seconds: offsetSec),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) => Consumer<TracksProvider>(
        builder: (context, provider, _) {
          final tracks = provider.tracks;
          if (tracks.isEmpty) {
            return Scaffold(appBar: AppBar(title: const Text('Карта треков')), body: const Center(child: Text('Нет треков. Сначала выполните синхронизацию.')));
          }
          Track? requested;
          for (final track in tracks) {
            if (track.id == widget.initialTrackId) requested = track;
          }
          final startTrack = requested ?? tracks.first;
          final polylines = <Polyline>[];
          final markers = <Marker>[];
          for (var i = 0; i < tracks.length; i++) {
            final track = tracks[i];
            if (track.points.isEmpty) continue;
            final color = _colors[i % _colors.length];
            final positions = track.points.map((point) => point.position).toList();
            if (positions.length >= 2) polylines.add(Polyline(points: positions, color: color, strokeWidth: 4));
            markers.add(Marker(point: positions.first, width: 36, height: 36, child: GestureDetector(onTap: () => _showTrack(track), child: const Icon(Icons.trip_origin, color: Colors.green, size: 28))));
            markers.add(Marker(point: positions.last, width: 36, height: 36, child: GestureDetector(onTap: () => _showTrack(track), child: const Icon(Icons.location_on, color: Colors.red, size: 30))));
          }
          return Scaffold(
            appBar: AppBar(
              title: const Text('Карта треков'),
              actions: [
                IconButton(tooltip: 'Центрировать маршруты', icon: const Icon(Icons.center_focus_strong), onPressed: () => _fitAll(tracks)),
              ],
            ),
            floatingActionButton: _selectedTrack != null
              ? FloatingActionButton.extended(
                  onPressed: () {
                    _animKey.currentState?.restart();
                    _mapController.fitCamera(CameraFit.bounds(
                      bounds: LatLngBounds.fromPoints(_selectedTrack!.points.map((p) => p.position).toList()),
                      padding: const EdgeInsets.all(48),
                      maxZoom: 17,
                    ));
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play'),
                )
              : null,
            floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
            body: Stack(children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: startTrack.points.first.position,
                  initialZoom: 13,
                  
                  onLongPress: (_, tapPoint) => _handleLongPress(tapPoint, tracks),
                ),
                children: [
                  TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'ru.a510.gpsmanager'),
                  PolylineLayer(polylines: _selectedTrack != null ? [Polyline(points: _selectedTrack!.points.map((p) => p.position).toList(), strokeWidth: 4.0, color: Colors.blue)] : polylines),
                  MarkerLayer(markers: _selectedTrack != null ? [] : markers),
                  if (_selectedTrack != null && _selectedTrack!.points.length > 1)
                    AnimatedTrackMarker(
                      key: _animKey,
                      autoplay: false,
                      points: _selectedTrack!.points.map((p) => p.position).toList(),
                      duration: const Duration(seconds: 30),
                    ),
                  const RichAttributionWidget(attributions: [TextSourceAttribution('© OpenStreetMap contributors')]),
                ],
              ),
              Positioned(right: 12, bottom: 20, child: Column(children: [
                FloatingActionButton.small(heroTag: 'zoom_in', tooltip: 'Приблизить', onPressed: () { final camera = _mapController.camera; _mapController.move(camera.center, camera.zoom + 1); }, child: const Icon(Icons.add)),
                const SizedBox(height: 8),
                FloatingActionButton.small(heroTag: 'zoom_out', tooltip: 'Отдалить', onPressed: () { final camera = _mapController.camera; _mapController.move(camera.center, camera.zoom - 1); }, child: const Icon(Icons.remove)),
              ])),
              Positioned(left: 12, right: 76, top: 12, child: Card(
                color: Colors.black87,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    'Долгое нажатие на маршрут → открыть видео с этой точки',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
              )),
              if (_selectedTrack != null) Positioned(left: 12, right: 76, bottom: 20, child: Card(child: ListTile(
                title: Text(DateFormat('dd.MM.yyyy HH:mm').format(_selectedTrack!.startLocal)),
                subtitle: Text('${_selectedTrack!.distanceKm.toStringAsFixed(2)} км · макс. ${_selectedTrack!.maxSpeedKmh.toStringAsFixed(0)} км/ч'),
                trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _selectedTrack = null)),
              ))),
            ]),
          );
        },
      );
}

class _TrackDetails extends StatelessWidget {
  const _TrackDetails({required this.track});
  final Track track;

  String _duration(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60);
    final seconds = value.inSeconds.remainder(60);
    if (hours > 0) return '$hours ч $minutes мин';
    if (minutes > 0) return '$minutes мин $seconds с';
    return '$seconds с';
  }

  @override
  Widget build(BuildContext context) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(DateFormat('dd.MM.yyyy HH:mm').format(track.startLocal), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text('Расстояние: ${track.distanceKm.toStringAsFixed(2)} км'),
          Text('Длительность: ${_duration(track.duration)}'),
          Text('Максимальная скорость: ${track.maxSpeedKmh.toStringAsFixed(1)} км/ч'),
          Text('Точек: ${track.points.length}'),
          if (track.videoNames.isNotEmpty)
            Text('Видео: ${track.videoNames.length} файлов'),
        ]),
      ));
}

class _PointDetails extends StatelessWidget {
  const _PointDetails({required this.point, required this.onOpenVideo});
  final GpsPoint point;
  final VoidCallback onOpenVideo;

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('dd.MM.yyyy HH:mm:ss').format(point.timeUtc.toLocal());
    return SafeArea(child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Точка маршрута', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Text('Время: $time'),
        Text('Скорость: ${point.speedKmh.toStringAsFixed(1)} км/ч'),
        if (point.course != null) Text('Курс: ${point.course}°'),
        if (point.tilt != null) Text('Наклон: ${point.tilt}°'),
        Text('Координаты: ${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}'),
        if (point.videoName != null) Text('Видео: ${point.videoName}'),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: point.videoName == null ? null : () {
              Navigator.of(context).pop();
              onOpenVideo();
            },
            icon: const Icon(Icons.play_circle),
            label: const Text('Открыть видео с этого момента'),
          ),
        ),
      ]),
    ));
  }
}
