import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../providers/tracks_provider.dart';
import 'map_screen.dart';

class TracksListScreen extends StatefulWidget {
  const TracksListScreen({super.key});
  @override
  State<TracksListScreen> createState() => _TracksListScreenState();
}

class _TracksListScreenState extends State<TracksListScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  @override
  void dispose() { _searchController.dispose(); super.dispose(); }

  String _duration(Duration duration) {
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60);
    final s = duration.inSeconds.remainder(60);
    if (h > 0) return '$h ч $m мин';
    if (m > 0) return '$m мин $s с';
    return '$s с';
  }

  Future<void> _delete(Track track) async {
    final yes = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Удалить трек?'),
      content: const Text('Будет удалён GPX этого трека. Исходные CSV останутся в архиве.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить'))],
    ));
    if (yes == true && mounted) await context.read<TracksProvider>().deleteTrack(track);
  }

  @override
  Widget build(BuildContext context) => Consumer<TracksProvider>(builder: (context, provider, _) {
    final format = DateFormat('dd.MM.yyyy HH:mm');
    final tracks = provider.tracks.where((track) => _query.trim().isEmpty || format.format(track.startLocal).contains(_query.trim())).toList()..sort((a, b) => b.startUtc.compareTo(a.startUtc));
    return Scaffold(
      appBar: AppBar(title: const Text('Список треков')),
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: TextField(
          controller: _searchController,
          decoration: InputDecoration(prefixIcon: const Icon(Icons.search), labelText: 'Поиск по дате', hintText: 'Например, 06.10.2026', border: const OutlineInputBorder(), suffixIcon: _query.isEmpty ? null : IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchController.clear(); setState(() => _query = ''); })),
          onChanged: (value) => setState(() => _query = value),
        )),
        Expanded(child: tracks.isEmpty ? const Center(child: Text('Треки не найдены')) : ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 20), itemCount: tracks.length,
          itemBuilder: (context, index) {
            final track = tracks[index];
            return Card(margin: const EdgeInsets.symmetric(vertical: 6), child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(format.format(track.startLocal), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text('Расстояние: ${track.distanceKm.toStringAsFixed(2)} км'),
              Text('Длительность: ${_duration(track.duration)}'),
              Text('Средняя скорость: ${track.averageSpeedKmh.toStringAsFixed(1)} км/ч'),
              Text('Максимальная скорость: ${track.maxSpeedKmh.toStringAsFixed(1)} км/ч'),
              Text('Точек: ${track.points.length}'),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 4, children: [
                OutlinedButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MapScreen(initialTrackId: track.id))), icon: const Icon(Icons.map), label: const Text('На карте')),
                TextButton.icon(onPressed: () => _delete(track), icon: const Icon(Icons.delete_outline), label: const Text('Удалить')),
              ]),
            ])));
          },
        )),
      ]),
    );
  });
}
