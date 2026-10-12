import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../providers/tracks_provider.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key, this.initialTrackId});
  final String? initialTrackId;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
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
            appBar: AppBar(title: const Text('Карта треков'), actions: [IconButton(tooltip: 'Центрировать маршруты', icon: const Icon(Icons.center_focus_strong), onPressed: () => _fitAll(tracks))]),
            body: Stack(children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(initialCenter: startTrack.points.first.position, initialZoom: 13, onTap: (_, __) => setState(() => _selectedTrack = null)),
                children: [
                  TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'ru.a510.gpsmanager'),
                  PolylineLayer(polylines: polylines),
                  MarkerLayer(markers: markers),
                  const RichAttributionWidget(attributions: [TextSourceAttribution('© OpenStreetMap contributors')]),
                ],
              ),
              Positioned(right: 12, bottom: 20, child: Column(children: [
                FloatingActionButton.small(heroTag: 'zoom_in', tooltip: 'Приблизить', onPressed: () { final camera = _mapController.camera; _mapController.move(camera.center, camera.zoom + 1); }, child: const Icon(Icons.add)),
                const SizedBox(height: 8),
                FloatingActionButton.small(heroTag: 'zoom_out', tooltip: 'Отдалить', onPressed: () { final camera = _mapController.camera; _mapController.move(camera.center, camera.zoom - 1); }, child: const Icon(Icons.remove)),
              ])),
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
        ]),
      ));
}
