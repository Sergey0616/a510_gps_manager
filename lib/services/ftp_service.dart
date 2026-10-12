import 'dart:io';

import 'ftp_client.dart';

/// Загрузка GPS CSV с FTP-сервера регистратора (совместимо с busybox ftpd).
class FtpService {
  FtpService({
    required this.host,
    required this.username,
    required this.password,
    this.port = 21,
    this.remoteDirectory = '/mnt/other/4g_gps',
  });

  final String host;
  final String username;
  final String password;
  final int port;
  final String remoteDirectory;

  Future<bool> testConnection() async {
    FtpClient? ftp;
    try {
      ftp = await FtpClient.connect(host, port, username, password);
      final cwd = await ftp.command('CWD $remoteDirectory');
      if (cwd.code >= 400) return false;
      await ftp.list('.');
      return true;
    } catch (e) {
      print('[FTP] testConnection error: $e');
      return false;
    } finally {
      await ftp?.close();
    }
  }

  Future<List<File>> downloadGpsFiles({
    required Directory destination,
    void Function(int completed, int total)? onProgress,
  }) async {
    await destination.create(recursive: true);
    final downloaded = <File>[];
    final ftp = await FtpClient.connect(host, port, username, password);
    try {
      final cwd = await ftp.command('CWD $remoteDirectory');
      if (cwd.code >= 400) {
        throw SocketException('CWD $remoteDirectory → ${cwd.code}: ${cwd.text}');
      }
      final entries = await ftp.list('.');
      final gpsFiles = entries
          .where((e) => !e.isDirectory && RegExp(r'^gps_\d+$').hasMatch(e.name))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      print('[FTP] Found ${gpsFiles.length} gps files');
      onProgress?.call(0, gpsFiles.length);
      var done = 0;
      for (final entry in gpsFiles) {
        final target = File('${destination.path}/${entry.name}');
        final temp = File('${destination.path}/${entry.name}.part');
        try {
          if (await temp.exists()) await temp.delete();
          await ftp.retrieveFile(entry.name, temp);
          if (!await temp.exists() || await temp.length() == 0) {
            throw const FileSystemException('Получен пустой файл');
          }
          if (await target.exists()) await target.delete();
          await temp.rename(target.path);
          downloaded.add(target);
          print('[FTP] ${entry.name} → ${await target.length()} байт');
        } catch (e) {
          print('[FTP] download ${entry.name} failed: $e');
          if (await temp.exists()) await temp.delete();
        } finally {
          done++;
          onProgress?.call(done, gpsFiles.length);
        }
      }
      return downloaded;
    } finally {
      await ftp.close();
    }
  }
}
