import 'dart:io';

import 'package:ftpconnect/ftpconnect.dart';

/// Загрузка GPS CSV с FTP-сервера регистратора.
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

  FTPConnect _client() => FTPConnect(
        host,
        port: port,
        user: username,
        pass: password,
        timeout: 20,
        showLog: false,
      );

  Future<bool> testConnection() async {
    final ftp = _client();
    try {
      final connected = await ftp.connect();
      if (!connected) return false;
      await ftp.changeDirectory(remoteDirectory);
      await ftp.listDirectoryContent();
      return true;
    } catch (_) {
      return false;
    } finally {
      try {
        await ftp.disconnect();
      } catch (_) {
        // Игнорируем ошибку закрытия соединения.
      }
    }
  }

  Future<List<File>> downloadGpsFiles({
    required Directory destination,
    void Function(int completed, int total)? onProgress,
  }) async {
    await destination.create(recursive: true);
    final ftp = _client();
    final downloaded = <File>[];
    try {
      final connected = await ftp.connect();
      if (!connected) throw const SocketException('FTP connect failed');
      await ftp.changeDirectory(remoteDirectory);
      final entries = await ftp.listDirectoryContent();
      final names = entries
          .map((entry) => entry.name)
          .where((name) => RegExp(r'^gps_\d+$').hasMatch(name))
          .toSet()
          .toList()
        ..sort();
      var completed = 0;
      onProgress?.call(0, names.length);

      for (final name in names) {
        final target = File('${destination.path}/$name');
        final temp = File('${destination.path}/$name.part');
        try {
          if (await temp.exists()) await temp.delete();
          final ok = await ftp.downloadFile(name, temp);
          if (!ok || !await temp.exists() || await temp.length() == 0) {
            throw const FileSystemException('Незавершённая загрузка');
          }
          if (await target.exists()) await target.delete();
          await temp.rename(target.path);
          downloaded.add(target);
        } catch (_) {
          if (await temp.exists()) await temp.delete();
        } finally {
          completed++;
          onProgress?.call(completed, names.length);
        }
      }
      return downloaded;
    } finally {
      try {
        await ftp.disconnect();
      } catch (_) {
        // Закрытие FTP не должно скрывать результат операции.
      }
    }
  }
}
