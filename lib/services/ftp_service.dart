import 'dart:io';
import 'app_logger.dart';

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
      AppLogger.log('[FTP] testConnection error: $e');
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
      final entries = await ftp.list('.').timeout(const Duration(seconds: 30));
      final gpsFiles = entries
          .where((e) => !e.isDirectory && RegExp(r'^gps_\d+$').hasMatch(e.name))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      AppLogger.log('[FTP] Found ${gpsFiles.length} gps files');
      onProgress?.call(0, gpsFiles.length);
      var done = 0;
      for (final entry in gpsFiles) {
        final target = File('${destination.path}/${entry.name}');
        final temp = File('${destination.path}/${entry.name}.part');
        if (await target.exists()) {
          done++;
          onProgress?.call(done, gpsFiles.length);
          continue;
        }
        try {
          if (await temp.exists()) await temp.delete();
          await ftp.retrieveFile(entry.name, temp);
          if (!await temp.exists() || await temp.length() == 0) {
            throw const FileSystemException('Получен пустой файл');
          }
          if (await target.exists()) await target.delete();
          await temp.rename(target.path);
          downloaded.add(target);
          AppLogger.log('[FTP] ${entry.name} → ${await target.length()} байт');
        } catch (e) {
          AppLogger.log('[FTP] download ${entry.name} failed: $e');
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


  Future<int> deleteEventVideos() async {
    FtpClient? ftp;
    int deleted = 0;
    try {
      ftp = await FtpClient.connect(host, port, username, password);
      final paths = ['/mnt/sd/Event', '/mnt/sd/events', '/mnt/sd/DCIM/Event', '/mnt/sd/DCIM/events'];
      bool found = false;
      for (final path in paths) {
        final cwd = await ftp.command('CWD $path');
        if (cwd.code < 400) {
          found = true;
          break;
        }
      }
      if (!found) return 0;
      final entries = await ftp.list('.').timeout(const Duration(seconds: 30));
      for (final entry in entries) {
        if (entry.isDirectory) continue;
        try {
          await ftp.command('DELE ${entry.name}');
          deleted++;
        } catch (_) {}
      }
    } catch (e) {
      AppLogger.log('[FTP] deleteEventVideos error: $e');
    } finally {
      await ftp?.close();
    }
    return deleted;
  }

  /// Скачивает сводный GPS-лог `/mnt/sd/GPSData000001.txt`.
  /// Возвращает локальный файл или null, если не удалось.
  Future<File?> downloadGpsDataFile({required Directory destination}) async {
    await destination.create(recursive: true);
    final target = File('${destination.path}/GPSData000001.txt');
    final temp = File('${destination.path}/GPSData000001.txt.part');
    FtpClient? ftp;
    try {
      ftp = await FtpClient.connect(host, port, username, password);
      final cwd = await ftp.command('CWD /mnt/sd');
      if (cwd.code >= 400) {
        AppLogger.log('[FTP] CWD /mnt/sd → ${cwd.code}: ${cwd.text}');
        return null;
      }
      if (await temp.exists()) await temp.delete();
      await ftp.retrieveFile('GPSData000001.txt', temp);
      if (!await temp.exists() || await temp.length() == 0) {
        AppLogger.log('[FTP] GPSData000001.txt пустой');
        return null;
      }
      if (await target.exists()) await target.delete();
      await temp.rename(target.path);
      AppLogger.log('[FTP] GPSData000001.txt → ${await target.length()} байт');
      return target;
    } catch (e) {
      AppLogger.log('[FTP] downloadGpsDataFile error: $e');
      if (await temp.exists()) await temp.delete();
      return null;
    } finally {
      await ftp?.close();
    }
  }
}
