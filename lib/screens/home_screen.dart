import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/tracks_provider.dart';
import 'map_screen.dart';
import 'settings_screen.dart';
import 'tracks_list_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => Consumer<TracksProvider>(
        builder: (context, provider, _) => Scaffold(
          appBar: AppBar(
            title: const Text('70mai GPS Manager'),
            actions: [
              IconButton(
                tooltip: 'Настройки',
                icon: const Icon(Icons.settings),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
              ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(child: ListTile(
                  leading: Icon(provider.error == null ? Icons.wifi : Icons.wifi_off),
                  title: const Text('Состояние'),
                  subtitle: Text(provider.status),
                  trailing: provider.busy ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)) : null,
                )),
                if (provider.busy) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: provider.progressTotal > 0 ? provider.progressDone / provider.progressTotal : null),
                  const SizedBox(height: 8),
                  Text(provider.progressTotal > 0 ? 'Файлы: ${provider.progressDone} / ${provider.progressTotal}' : 'Подготовка…', textAlign: TextAlign.center),
                ],
                if (provider.error != null) ...[
                  const SizedBox(height: 12),
                  Text(provider.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 16),
                SizedBox(height: 62, child: FilledButton.icon(
                  onPressed: provider.busy ? null : () => _showSyncDialog(context, provider),
                  icon: const Icon(Icons.sync),
                  label: const Text('Синхронизировать GPS', style: TextStyle(fontSize: 17)),
                )),
                const SizedBox(height: 12),
                SizedBox(height: 58, child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MapScreen())),
                  icon: const Icon(Icons.map), label: const Text('Открыть карту'),
                )),
                const SizedBox(height: 12),
                SizedBox(height: 58, child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pushNamed('/video'),
                  icon: const Icon(Icons.video_library), label: const Text('Видео и фото'),
                )),
                const SizedBox(height: 12),
                SizedBox(height: 58, child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TracksListScreen())),
                  icon: const Icon(Icons.route), label: const Text('Список треков'),
                )),
                const SizedBox(height: 20),
                Card(child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Сводка', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    _StatRow(label: 'Последняя синхронизация', value: provider.lastSync == null ? 'Ещё не выполнялась' : DateFormat('dd.MM.yyyy HH:mm').format(provider.lastSync!.toLocal())),
                    _StatRow(label: 'Количество треков', value: '${provider.tracks.length}'),
                    _StatRow(label: 'Общее расстояние', value: '${provider.totalDistanceKm.toStringAsFixed(2)} км'),
                  ]),
                )),
              ],
            ),
          ),
        ),
      );

  void _showSyncDialog(BuildContext context, TracksProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Откуда синхронизировать?'),
        content: const Text('Выберите источник данных:'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              provider.syncViaFtp();
            },
            child: const Text('С регистратора (Wi-Fi)'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              provider.syncFromLocalFolder();
            },
            child: const Text('Из локальной папки'),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 12),
          Flexible(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      );
}
