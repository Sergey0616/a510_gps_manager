import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/video_file.dart';
import 'storage_paths.dart';

/// FTP-доступ к видео с записью непосредственно в конечный файл.
class VideoService {
  VideoService({required this.host, required this.username, required this.password, this.port = 21});

  final String host;
  final String username;
  final String password;
  final int port;
  _FtpSession? _activeSession;
  Socket? _activeDataSocket;
  IOSink? _activeSink;
  bool _cancelRequested = false;

  // Все категории на регистраторе имеют подпапки Front/Back.
  static const Map<VideoCategory, List<String>> _directories = {
    VideoCategory.normal: ['/mnt/sd/Normal/Front', '/mnt/sd/Normal/Rear'],
    VideoCategory.parking: ['/mnt/sd/Parking/Front', '/mnt/sd/Parking/Back'],
    VideoCategory.event: ['/mnt/sd/Event/Front', '/mnt/sd/Event/Back'],
    VideoCategory.lapse: ['/mnt/sd/Lapse/Front', '/mnt/sd/Lapse/Back'],
    VideoCategory.photo: ['/mnt/sd/Photo/Front', '/mnt/sd/Photo/Back'],
  };

  Future<List<VideoFile>> scan(VideoCategory category, {String? localRoot}) async {
    final session = await _FtpSession.connect(host, port, username, password);
    _activeSession = session;
    try {
      final result = <VideoFile>[];
      for (final directory in _directories[category]!) {
        try {
          for (final entry in await session.list(directory)) {
            final lower = entry.name.toLowerCase();
            final allowed = category == VideoCategory.photo
                ? (lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png'))
                : lower.endsWith('.mp4');
            if (!allowed || entry.size < 0) continue;
            String? localPath;
            if (localRoot != null) {
              final candidate = File('$localRoot/${category.folderName}/${entry.name}');
              if (await candidate.exists()) localPath = candidate.path;
            }
            result.add(VideoFile(
              name: entry.name,
              remotePath: '$directory/${entry.name}',
              category: category,
              sizeBytes: entry.size,
              recordedAt: VideoFile.parseDateFromName(entry.name),
              localPath: localPath,
            ));
          }
        } on SocketException {
          // Например, каталог Rear может отсутствовать на однокамерной модели.
        } on FileSystemException {
          // Недоступный каталог пропускается; остальные проверяются дальше.
        }
      }
      result.sort((a, b) => (b.recordedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(a.recordedAt ?? DateTime.fromMillisecondsSinceEpoch(0)));
      return result;
    } finally {
      _activeSession = null;
      await session.close();
    }
  }

  Future<String> videoRootPath() async {
    final base = await StoragePaths.baseDir();
    return '${base.path}/video';
  }

  Future<int?> freeBytes() async {
    try {
      return await const MethodChannel('ru.a510.gpsmanager/storage').invokeMethod<int>('getFreeBytes');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<File> download(VideoFile video, {
    required void Function(int received, int total, double bytesPerSecond, Duration? remaining) onProgress,
  }) async {
    _cancelRequested = false;
    final root = await videoRootPath();
    final directory = Directory('$root/${video.category.folderName}');
    await directory.create(recursive: true);
    final destination = File('${directory.path}/${video.name}');
    final session = await _FtpSession.connect(host, port, username, password);
    _activeSession = session;
    final stopwatch = Stopwatch()..start();
    var received = 0;
    var expectedTotal = video.sizeBytes;

    // Если размер неизвестен (VideoFile.fromName), узнаём через FTP SIZE.
    if (expectedTotal <= 0) {
      try {
        expectedTotal = await session.size(video.remotePath);
        print('[Video] SIZE ${video.remotePath} = $expectedTotal bytes');
      } catch (e) {
        print('[Video] SIZE failed: $e');
      }
    }

    try {
      final dataSocket = await session.openRetrieve(video.remotePath);
      _activeDataSocket = dataSocket;
      final sink = destination.openWrite(mode: FileMode.write);
      _activeSink = sink;
      try {
        await for (final chunk in dataSocket) {
          if (_cancelRequested) throw const _DownloadCancelled();
          sink.add(chunk);
          received += chunk.length;
          final elapsed = stopwatch.elapsedMilliseconds / 1000.0;
          final speed = elapsed > 0 ? received / elapsed : 0.0;
          final total = expectedTotal > 0 ? expectedTotal : received;
          final seconds = speed > 0 && total > received ? ((total - received) / speed).ceil() : null;
          onProgress(received, total, speed, seconds == null ? null : Duration(seconds: seconds));
        }
        await sink.flush();
        await sink.close();
        _activeSink = null;
      } catch (_) {
        await sink.close();
        _activeSink = null;
        rethrow;
      }
      final completion = await session.readResponse();
      if (completion.code >= 400) throw FileSystemException('FTP RETR: ${completion.text}');
      if (expectedTotal > 0 && received != expectedTotal) {
        throw FileSystemException('Размер файла не совпал: получено $received из $expectedTotal байт');
      }
      return destination;
    } catch (error) {
      if (await destination.exists()) {
        try { await destination.delete(); } catch (_) { /* Удаление частичного файла — best effort. */ }
      }
      rethrow;
    } finally {
      _activeDataSocket = null;
      _activeSession = null;
      await session.close();
    }
  }

  Future<void> cancelDownload() async {
    _cancelRequested = true;
    _activeDataSocket?.destroy();
    try { await _activeSink?.close(); } catch (_) { /* Поток мог уже закрыться. */ }
    try { await _activeSession?.command('ABOR'); } catch (_) { /* FTP-сервер мог закрыть канал первым. */ }
  }
}

class _DownloadCancelled implements Exception {
  const _DownloadCancelled();
  @override
  String toString() => 'Загрузка отменена';
}

class _FtpEntry {
  const _FtpEntry(this.name, this.size);
  final String name;
  final int size;
}

class _FtpResponse {
  const _FtpResponse(this.code, this.text);
  final int code;
  final String text;
}

/// Минимальный FTP-клиент для PASV/LIST/RETR. Поддерживает обычный FTP без TLS.
class _FtpSession {
  _FtpSession(this._control, this._lines);
  final Socket _control;
  final StreamIterator<String> _lines;
  bool _closed = false;

  static Future<_FtpSession> connect(String host, int port, String username, String password) async {
    final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 12));
    final session = _FtpSession(socket, StreamIterator<String>(socket.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter())));
    final greeting = await session.readResponse();
    if (greeting.code >= 400) throw SocketException('FTP greeting: ${greeting.text}');
    final user = await session.command('USER $username');
    if (user.code == 331) {
      final pass = await session.command('PASS $password');
      if (pass.code >= 400) throw SocketException('FTP login: ${pass.text}');
    } else if (user.code >= 400) {
      throw SocketException('FTP login: ${user.text}');
    }
    final binary = await session.command('TYPE I');
    if (binary.code >= 400) throw SocketException('FTP TYPE I: ${binary.text}');
    return session;
  }

  Future<_FtpResponse> command(String command) async {
    if (_closed) throw const SocketException('FTP-соединение закрыто');
    _control.write('$command\r\n');
    await _control.flush();
    return readResponse();
  }

  Future<_FtpResponse> readResponse() async {
    String? line;
    try {
      line = await _lines.moveNext().timeout(const Duration(seconds: 30)) ? _lines.current : null;
    } on TimeoutException {
      throw const SocketException('Тайм-аут ответа FTP');
    }
    if (line == null) throw const SocketException('FTP-соединение прервано');
    final match = RegExp(r'^(\d{3})([ -])(.*)$').firstMatch(line);
    if (match == null) return _FtpResponse(0, line);
    final code = int.parse(match.group(1)!);
    final lines = <String>[line];
    if (match.group(2) == '-') {
      while (await _lines.moveNext().timeout(const Duration(seconds: 30))) {
        final next = _lines.current;
        lines.add(next);
        if (next.startsWith('$code ')) break;
      }
    }
    return _FtpResponse(code, lines.join('\n'));
  }

  Future<Socket> _openPassiveDataSocket() async {
    final response = await command('PASV');
    if (response.code >= 400) throw SocketException('FTP PASV: ${response.text}');
    final match = RegExp(r'(\d{1,3},\d{1,3},\d{1,3},\d{1,3}),(\d{1,3}),(\d{1,3})').firstMatch(response.text);
    if (match == null) throw const SocketException('Не удалось разобрать ответ PASV');
    final ip = match.group(1)!.replaceAll(',', '.');
    final dataPort = int.parse(match.group(2)!) * 256 + int.parse(match.group(3)!);
    // Некоторые FTP-серверы возвращают внутренний адрес; используем IP контрольного соединения.
    final address = InternetAddress.tryParse(ip) ?? InternetAddress(_control.address.address);
    final data = await Socket.connect(address, dataPort, timeout: const Duration(seconds: 12));
    return data;
  }

  Future<List<_FtpEntry>> list(String path) async {
    final data = await _openPassiveDataSocket();
    _control.write('LIST $path\r\n');
    await _control.flush();
    final initial = await readResponse();
    if (initial.code >= 400) { data.destroy(); throw FileSystemException('FTP LIST: ${initial.text}'); }
    // Прочитываем данные каталога и закрываем data socket перед финальным ответом.
    final lines = await data.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter()).toList();
    data.destroy();
    final completion = await readResponse();
    if (completion.code >= 400) throw FileSystemException('FTP LIST: ${completion.text}');
    final entries = <_FtpEntry>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('total ')) continue;
      final unix = RegExp(r'^\S+\s+\d+\s+\S+\s+\S+\s+(\d+)\s+\w+\s+\d+\s+[\d:]+\s+(.+)$').firstMatch(trimmed);
      if (unix != null) {
        final name = unix.group(2)!;
        if (name != '.' && name != '..' && !trimmed.startsWith('d')) entries.add(_FtpEntry(name, int.tryParse(unix.group(1)!) ?? -1));
      }
    }
    return entries;
  }

  Future<Socket> openRetrieve(String path) async {
    final data = await _openPassiveDataSocket();
    _control.write('RETR $path\r\n');
    await _control.flush();
    final response = await readResponse();
    if (response.code >= 400) {
      data.destroy();
      throw FileSystemException('FTP RETR: ${response.text}');
    }
    return data;
  }

  /// Возвращает размер файла (байт) через FTP SIZE. 0 — если не удалось.
  Future<int> size(String path) async {
    try {
      final response = await command('SIZE $path');
      if (response.code >= 400) {
        // busybox ftpd может не поддерживать SIZE — тогда пробуем LIST.
        return await _sizeViaList(path);
      }
      final match = RegExp(r'213\s+(\d+)').firstMatch(response.text);
      if (match == null) return 0;
      return int.tryParse(match.group(1)!) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Fallback: получает размер файла через LIST <path>.
  Future<int> _sizeViaList(String path) async {
    try {
      final entries = await list(path);
      if (entries.isEmpty) return 0;
      return entries.first.size;
    } catch (_) {
      return 0;
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try { _control.write('QUIT\r\n'); await _control.flush(); } catch (_) { /* Закрываем сокет в любом случае. */ }
    try { await _lines.cancel(); } catch (_) { /* Поток уже мог завершиться. */ }
    _control.destroy();
  }
}
