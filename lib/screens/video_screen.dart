import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/video_file.dart';
import '../providers/tracks_provider.dart';
import '../services/video_service.dart';
import 'video_player_screen.dart';

class VideoScreen extends StatefulWidget {
  const VideoScreen({super.key});
  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: VideoCategory.values.length, vsync: this)..addListener(_tabChanged);
  late VideoService _service;
  final Map<VideoCategory, List<VideoFile>> _files = {};
  final Set<String> _selected = {};
  final Map<String, _DownloadProgress> _progress = {};
  bool _scanning = false;
  bool _downloading = false;
  String? _error;
  VideoCategory get _category => VideoCategory.values[_tabs.index];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<TracksProvider>();
    _service = VideoService(host: provider.host, username: provider.username, password: provider.password);
    if (!_files.containsKey(_category) && !_scanning) _scan();
  }

  void _tabChanged() {
    if (mounted) setState(() {});
    if (!_files.containsKey(_category) && !_scanning) _scan();
  }

  @override
  void dispose() {
    _tabs.removeListener(_tabChanged);
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() { _scanning = true; _error = null; });
    try {
      final root = await _service.videoRootPath();
      final found = await _service.scan(_category, localRoot: root);
      if (!mounted) return;
      setState(() => _files[_category] = found);
    } catch (error) {
      if (mounted) setState(() => _error = 'Не удалось получить список с FTP: $error');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  List<VideoFile> get _currentFiles => _files[_category] ?? const [];
  String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} КБ';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} ГБ';
  }

  /// Скачать ОДИН файл и сразу открыть его в плеере.
  /// Не зависит от _selected и не показывает диалог.
  Future<void> _downloadOne(VideoFile file) async {
    if (_downloading) return;
    if (file.isDownloaded) {
      if (file.isPhoto) {
        await OpenPhoto.open(context, file.localPath!);
      } else {
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => VideoPlayerScreen(path: file.localPath!, title: file.name),
        ));
      }
      return;
    }
    setState(() {
      _downloading = true;
      _error = null;
      _progress[file.remotePath] = _DownloadProgress(received: 0, total: file.sizeBytes, speed: 0, remaining: null);
    });
    try {
      final local = await _service.download(file, onProgress: (received, total, speed, remaining) {
        if (mounted) setState(() => _progress[file.remotePath] = _DownloadProgress(received: received, total: total, speed: speed, remaining: remaining));
      });
      if (!mounted) return;
      setState(() {
        final current = _files[file.category] ?? [];
        final index = current.indexWhere((item) => item.remotePath == file.remotePath);
        if (index >= 0) {
          current[index] = file.copyWith(localPath: local.path);
        }
        _progress.remove(file.remotePath);
      });
      if (file.isPhoto) {
        await OpenPhoto.open(context, local.path);
      } else {
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => VideoPlayerScreen(path: local.path, title: file.name),
        ));
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка скачивания: $error')));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _downloadSelected() async {
    final selected = _currentFiles.where((f) => _selected.contains(f.remotePath) && !f.isDownloaded).toList();
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Выберите файлы, которые ещё не скачаны')));
      return;
    }
    final totalBytes = selected.fold<int>(0, (sum, file) => sum + file.sizeBytes);
    final free = await _service.freeBytes();
    if (free != null && free < totalBytes) {
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (context) => AlertDialog(
        title: const Text('Недостаточно места'),
        content: Text('Для выбранных файлов требуется ${_formatBytes(totalBytes)}, свободно ${_formatBytes(free)}. Освободите место и повторите попытку.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Понятно'))],
      ));
      return;
    }
    final unknownSpace = free == null;
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Скачать выбранные файлы?'),
      content: Text('Файлов: ${selected.length}\nОжидаемый объём: ${_formatBytes(totalBytes)}\n${free == null ? 'Свободное место определить не удалось — убедитесь, что его достаточно.\n' : 'Свободно: ${_formatBytes(free)}\n'}Папка: A510_Exports/video/${_category.folderName}'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')), FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(unknownSpace ? 'Продолжить' : 'Скачать'))],
    ));
    if (confirmed != true || !mounted) return;
    setState(() { _downloading = true; _error = null; });
    try {
      for (final file in selected) {
        if (!mounted) break;
        setState(() => _progress[file.remotePath] = _DownloadProgress(received: 0, total: file.sizeBytes, speed: 0, remaining: null));
        final local = await _service.download(file, onProgress: (received, total, speed, remaining) {
          if (mounted) setState(() => _progress[file.remotePath] = _DownloadProgress(received: received, total: total, speed: speed, remaining: remaining));
        });
        final current = _files[file.category] ?? [];
        final index = current.indexWhere((item) => item.remotePath == file.remotePath);
        if (index >= 0) current[index] = file.copyWith(localPath: local.path);
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Загрузка завершена')));
    } catch (error) {
      if (mounted) setState(() => _error = 'Ошибка загрузки: $error');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _cancel() async {
    await _service.cancelDownload();
    if (mounted) setState(() => _downloading = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Видео и фото'), actions: [
          IconButton(tooltip: 'Обновить', onPressed: _scanning || _downloading ? null : _scan, icon: const Icon(Icons.refresh)),
        ], bottom: TabBar(controller: _tabs, isScrollable: true, tabs: VideoCategory.values.map((c) => Tab(text: c.label)).toList()),),
        body: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 4), child: Wrap(spacing: 8, runSpacing: 4, children: [
            OutlinedButton.icon(onPressed: _downloading || _currentFiles.isEmpty ? null : () => setState(() {
              final all = _currentFiles.map((f) => f.remotePath).toSet();
              if (_selected.containsAll(all)) { _selected.removeAll(all); } else { _selected.addAll(all); }
            }), icon: const Icon(Icons.select_all), label: const Text('Выбрать все')),
            FilledButton.icon(onPressed: _downloading ? null : _downloadSelected, icon: const Icon(Icons.download), label: const Text('Скачать выбранные')),
            if (_downloading) OutlinedButton.icon(onPressed: _cancel, icon: const Icon(Icons.cancel), label: const Text('Отменить')),
          ])),
          if (_scanning) const LinearProgressIndicator(),
          if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          Expanded(child: _currentFiles.isEmpty && !_scanning
              ? const Center(child: Text('Нет файлов или FTP-каталог недоступен'))
              : ListView.separated(itemCount: _currentFiles.length, separatorBuilder: (_, __) => const Divider(height: 1), itemBuilder: (context, index) {
                  final file = _currentFiles[index];
                  final selected = _selected.contains(file.remotePath);
                  final progress = _progress[file.remotePath];
                  final active = _downloading && progress != null && progress.received < progress.total;
                  return ListTile(
                    leading: Checkbox(value: selected, onChanged: _downloading ? null : (value) => setState(() { value == true ? _selected.add(file.remotePath) : _selected.remove(file.remotePath); })),
                    title: Text(file.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${file.recordedAt == null ? 'Дата не распознана' : DateFormat('dd.MM.yyyy HH:mm:ss').format(file.recordedAt!)} · ${_formatBytes(file.sizeBytes)}'),
                      if (active) ...[
                        const SizedBox(height: 6),
                        LinearProgressIndicator(value: progress.total > 0 ? (progress.received / progress.total).clamp(0, 1) : null),
                        Text('${progress.total > 0 ? (progress.received * 100 / progress.total).toStringAsFixed(1) : '…'}% · ${_formatBytes(progress.received)} · ${_formatBytes(progress.speed.round())}/с · ${progress.remaining == null ? 'осталось —' : 'осталось ${progress.remaining!.inMinutes} мин ${progress.remaining!.inSeconds % 60} с'}'),
                      ],
                    ]),
                    trailing: IconButton(
                      tooltip: file.isDownloaded ? 'Воспроизвести' : 'Скачать и воспроизвести',
                      onPressed: _downloading ? null : () => _downloadOne(file),
                      icon: Icon(file.isDownloaded ? (file.isPhoto ? Icons.photo : Icons.play_circle) : Icons.download),
                    ),
                  );
                })),
        ]),
      );
}

class _DownloadProgress {
  const _DownloadProgress({required this.received, required this.total, required this.speed, required this.remaining});
  final int received;
  final int total;
  final double speed;
  final Duration? remaining;
}

class OpenPhoto {
  static Future<void> open(BuildContext context, String path) async {
    await showDialog<void>(context: context, builder: (context) => Dialog(child: Column(mainAxisSize: MainAxisSize.min, children: [
      AppBar(title: const Text('Фото'), automaticallyImplyLeading: false, actions: [IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close))]),
      Flexible(child: Image.file(File(path), fit: BoxFit.contain)),
    ])));
  }
}
