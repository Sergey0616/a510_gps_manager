import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/tracks_provider.dart';
import '../models/track.dart';
import '../models/gps_point.dart';
import '../models/video_file.dart';
import '../services/storage_paths.dart';
import 'video_player_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key, this.initialTrackId});
  final String? initialTrackId;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  late AnimationController _animController;
  LatLng? _currentAnimatedPos;
  double _currentAngle = 0.0;
  Track? _selectedTrack;
  bool _isPlaying = false;
  double _speed = 1.0;
  static const Duration _baseDuration = Duration(seconds: 30);
  static const List<double> _speeds = [0.5, 1.0, 2.0, 4.0];
  static const _colors = <Color>[
    Colors.blue, Colors.red, Colors.green, Colors.orange,
    Colors.purple, Colors.teal, Colors.brown, Colors.pink
  ];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: _baseDuration);
    _animController.addStatusListener((status) {
      if (!mounted) return;
      if (status == AnimationStatus.completed) {
        setState(() => _isPlaying = false);
      }
    });
    _animController.addListener(() {
      if (_selectedTrack != null && _selectedTrack!.points.length > 1) {
        final t = _animController.value;
        final pts = _selectedTrack!.points.map((p) => p.position).toList();
        final total = pts.length - 1;
        final scaled = t * total;
        final seg = scaled.floor().clamp(0, total - 1);
        final local = (scaled - seg).clamp(0.0, 1.0);
        final a = pts[seg];
        final b = pts[seg + 1];
        setState(() {
          _currentAnimatedPos = LatLng(
            a.latitude + (b.latitude - a.latitude) * local,
            a.longitude + (b.longitude - a.longitude) * local,
          );
          final dLon = b.longitude - a.longitude;
          final dLat = b.latitude - a.latitude;
          _currentAngle = math.atan2(dLon, dLat);
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await context.read<TracksProvider>().reloadFromDisk();
      if (!mounted) return;
      
      if (widget.initialTrackId != null) {
        final provider = context.read<TracksProvider>();
        try {
          final track = provider.tracks.firstWhere((t) => t.id == widget.initialTrackId);
          _showTrack(track);
        } catch (_) {}
      }
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _fitAll(List<Track> tracks) {
    final points = tracks.expand((t) => t.points).map((p) => p.position).toList();
    if (points.isEmpty) return;
    _mapController.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(points),
      padding: const EdgeInsets.all(48),
      maxZoom: 16,
    ));
  }

  void _showTrack(Track track) {
    setState(() {
      _selectedTrack = track;
      _currentAnimatedPos = null;
      _isPlaying = false;
    });
    _animController.stop();
    _animController.value = 0;
    _mapController.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(track.points.map((p) => p.position).toList()),
      padding: const EdgeInsets.all(48),
      maxZoom: 17,
    ));
  }

  void _togglePlay() {
    if (_selectedTrack == null) return;
    if (_isPlaying) {
      _animController.stop();
      setState(() => _isPlaying = false);
      return;
    }
    if (_animController.value >= 1.0) {
      _animController.value = 0;
    }
    _animController.forward();
    setState(() => _isPlaying = true);
    _mapController.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(_selectedTrack!.points.map((p) => p.position).toList()),
      padding: const EdgeInsets.all(48),
      maxZoom: 17,
    ));
  }

  void _setSpeed(double s) {
    if (s == _speed) return;
    final wasPlaying = _isPlaying;
    if (wasPlaying) _animController.stop();
    final currentValue = _animController.value;
    setState(() {
      _speed = s;
      _animController.duration = Duration(
        milliseconds: (_baseDuration.inMilliseconds / s).round(),
      );
    });
    if (wasPlaying) {
      _animController.forward(from: currentValue);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TracksProvider>();
    final tracks = provider.tracks.where((t) => t.points.length > 1 && t.distanceKm > 0.01).toList();
    
    if (tracks.isEmpty) return const Scaffold(body: Center(child: Text('Нет треков')));
    final startTrack = tracks.first;

    final polylines = <Polyline>[];
    final markers = <Marker>[];

    // Если трек выбран — рисуем только его. Если нет — рисуем все.
    final displayTracks = _selectedTrack != null ? [_selectedTrack!] : tracks;

    for (var i = 0; i < displayTracks.length; i++) {
      final track = displayTracks[i];
      final color = _colors[i % _colors.length];
      final positions = track.points.map((point) => point.position).toList();
      
      if (positions.length >= 2) polylines.add(Polyline(points: positions, color: color, strokeWidth: 4));
      
      // Показываем маркеры только если трек не выбран (чтобы не засорять карту)
      if (_selectedTrack == null) {
        markers.add(Marker(point: positions.first, width: 36, height: 36, child: GestureDetector(onTap: () => _showTrack(track), child: const Icon(Icons.trip_origin, color: Colors.green, size: 28))));
        markers.add(Marker(point: positions.last, width: 36, height: 36, child: GestureDetector(onTap: () => _showTrack(track), child: const Icon(Icons.location_on, color: Colors.red, size: 30))));
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Карта треков'),
        actions: [
          IconButton(
            tooltip: 'Live-трансляция (RTSP)',
            icon: const Icon(Icons.videocam),
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const VideoPlayerScreen(
                  path: 'rtsp://192.168.0.1/liveRTSP/av4',
                  title: 'Live-трансляция',
                ),
              ));
            },
          ),
          IconButton(
            tooltip: 'Обновить локальные треки',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              context.read<TracksProvider>().reloadFromDisk();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Обновление...')));
            },
          ),
          PopupMenuButton<Track>(
            icon: const Icon(Icons.list),
            tooltip: 'Выбрать трек',
            onSelected: (track) => _showTrack(track),
            itemBuilder: (context) => tracks.map((t) {
              return PopupMenuItem(
                value: t,
                child: Text('${DateFormat('dd.MM.yyyy HH:mm').format(t.startLocal)} (${t.distanceKm.toStringAsFixed(1)} км)'),
              );
            }).toList(),
          ),
          IconButton(tooltip: 'Центрировать', icon: const Icon(Icons.center_focus_strong), onPressed: () => _fitAll(tracks)),
        ],
      ),
      body: Stack(children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: startTrack.points.first.position,
            initialZoom: 13,
            onTap: (_, __) => setState(() => _selectedTrack = null),
            onLongPress: (_, tapPoint) => _handleLongPress(tapPoint, tracks),
          ),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'ru.a510.gpsmanager'),
            PolylineLayer(polylines: polylines),
            MarkerLayer(
              markers: _selectedTrack != null
                  ? [
                      ...markers,
                      if (_currentAnimatedPos != null)
                        Marker(
                          point: _currentAnimatedPos!,
                          width: 48,
                          height: 48,
                          child: Transform.rotate(
                            angle: _currentAngle,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.blue,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 3),
                                boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8)],
                              ),
                              child: const Icon(Icons.navigation, color: Colors.white, size: 24),
                            ),
                          ),
                        ),
                    ]
                  : markers,
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
        if (_selectedTrack != null)
          Positioned(
            left: 12,
            right: 76,
            bottom: 116,
            child: Card(
              color: Colors.black87,
              elevation: 6,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: _animController,
                      builder: (context, _) => LinearProgressIndicator(
                        value: _animController.value,
                        minHeight: 2,
                        backgroundColor: Colors.grey.shade800,
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          iconSize: 32,
                          color: Colors.blue,
                          tooltip: _isPlaying ? 'Пауза' : 'Играть',
                          icon: Icon(
                            _isPlaying
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_filled,
                          ),
                          onPressed: _togglePlay,
                        ),
                        const SizedBox(width: 2),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: _speeds
                                  .map(
                                    (s) => Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 2),
                                      child: ChoiceChip(
                                        label: Text('${s}x'.replaceAll('.0x', 'x')),
                                        selected: (s - _speed).abs() < 0.01,
                                        onSelected: (_) => _setSpeed(s),
                                        showCheckmark: false,
                                        labelStyle: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                        ),
                                        selectedColor: Colors.blue,
                                        backgroundColor: Colors.grey.shade800,
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(horizontal: 4),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (_selectedTrack != null)
          Positioned(left: 12, right: 76, bottom: 20, child: Card(child: ListTile(
            title: Text(DateFormat('dd.MM.yyyy HH:mm').format(_selectedTrack!.startLocal)),
            subtitle: Text('${_selectedTrack!.distanceKm.toStringAsFixed(2)} км · макс. ${_selectedTrack!.maxSpeedKmh.toStringAsFixed(0)} км/ч'),
            leading: IconButton(
              icon: const Icon(Icons.play_circle, color: Colors.blue, size: 30),
              onPressed: () {
                final videos = _selectedTrack!.videoNames.toList();
                if (videos.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Для этого трека нет видео')));
                } else {
                  Navigator.of(context).pushNamed('/video', arguments: videos.first);
                }
              },
              tooltip: 'Смотреть видео',
            ),
            trailing: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                _selectedTrack = null;
                _currentAnimatedPos = null;
                _isPlaying = false;
                _animController.stop();
              }),
            ),
          ))),
      ]),
    );
  }

  void _handleLongPress(LatLng tapPoint, List<Track> tracks) async {
    GpsPoint? nearest;
    double minDistance = double.infinity;

    for (var track in tracks) {
      for (var p in track.points) {
        final dLat = (p.latitude - tapPoint.latitude) * 111320;
        final dLon = (p.longitude - tapPoint.longitude) * 111320 * math.cos(tapPoint.latitude * math.pi / 180);
        final dist = math.sqrt(dLat * dLat + dLon * dLon);
        if (dist < minDistance) {
          minDistance = dist;
          nearest = p;
        }
      }
    }

    if (nearest == null || minDistance > 150) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Рядом нет точек трека (ближе 150 м)')));
      return;
    }

    final videoName = nearest.videoName;
    if (videoName == null || videoName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('К этой точке не привязано видео')));
      return;
    }

    final videoTime = VideoFile.parseDateFromName(videoName);
    if (videoTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Не удалось распознать время файла')));
      return;
    }

    var startPos = nearest.timeUtc.difference(videoTime.toUtc());
    if (startPos.isNegative) startPos = Duration.zero;

    String? localPath;
    final base = await StoragePaths.baseDir();
    String category = 'Normal';
    String camera = videoName.toUpperCase().contains('R.MP4') ? 'Back' : 'Front';

    for (final cat in ['Normal', 'Parking', 'Event', 'Lapse']) {
      for (final cam in ['Front', 'Back', 'Rear']) {
        final f = File('${base.path}/video/$cat/$cam/$videoName');
        if (await f.exists()) {
          localPath = f.path;
          category = cat;
          camera = cam;
          break;
        }
      }
      if (localPath != null) break;
    }

    final String playPath = localPath ?? 'http://192.168.0.1/mnt/sd/$category/$camera/$videoName';
    final bool isLocal = localPath != null;

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(isLocal ? 'Открываем локальное видео с ${startPos.inSeconds} сек.' : 'Открываем онлайн с ${startPos.inSeconds} сек.'),
      duration: const Duration(seconds: 2),
    ));

    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => VideoPlayerScreen(
        path: playPath,
        title: videoName,
        startPosition: startPos,
      ),
    ));
  }
}
