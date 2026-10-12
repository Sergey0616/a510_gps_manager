import 'dart:io';

import 'ftp_client.dart';
import 'telnet_service.dart';

class SystemInfo {
  const SystemInfo({
    this.config = '',
    this.firmware = '',
    this.kernel = '',
    this.partitions = '',
    this.inittab = '',
    this.sysctl = '',
    this.lastFile = '',
    this.gpsLogCount = 0,
    this.ram = '',
    this.sdSpace = '',
    this.wifiMac = 'N/A',
    this.ssid = 'N/A',
    this.ip = 'N/A',
  });

  final String config;
  final String firmware;
  final String kernel;
  final String partitions;
  final String inittab;
  final String sysctl;
  final String lastFile;
  final int gpsLogCount;
  final String ram;
  final String sdSpace;
  final String wifiMac;
  final String ssid;
  final String ip;

  String configValue(String key) {
    for (final line in config.split(RegExp(r'\r?\n'))) {
      final match = RegExp('^\\s*' + RegExp.escape(key) + '\\s*=\\s*(.*)\$').firstMatch(line);
      if (match == null) continue;
      var value = match.group(1)!.trim();
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      return value.isEmpty ? 'N/A' : value;
    }
    return 'N/A';
  }
}

/// Получение диагностической информации без изменения файлов регистратора.
class SystemInfoService {
  SystemInfoService({required this.host, required this.username, required this.password});
  final String host;
  final String username;
  final String password;

  Future<SystemInfo> load() async {
    FtpClient? ftp;
    final telnet = TelnetService(host: host, username: username, password: password);
    var config = '';
    var firmware = '';
    var kernel = '';
    var partitions = '';
    var inittab = '';
    var sysctl = '';
    var lastFile = '';
    var ram = '';
    var sdSpace = '';
    var gpsCount = 0;

    try {
      ftp = await FtpClient.connect(host, 21, username, password);
      config = await _readRemoteText(ftp, '/etc/profile_prjcfg');
      firmware = await _readRemoteText(ftp, '/etc/firmware.info');
      kernel = await _readRemoteText(ftp, '/proc/version');
      partitions = await _readRemoteText(ftp, '/proc/mtd');
      inittab = await _readRemoteText(ftp, '/etc/inittab');
      sysctl = await _readRemoteText(ftp, '/etc/init.d/S99_Sysctl');
      lastFile = await _readRemoteText(ftp, '/mnt/other/.LastFileName');
      try {
        await ftp.command('CWD /mnt/other/4g_gps');
        final entries = await ftp.list('.');
        gpsCount = entries.where((e) => !e.isDirectory && RegExp(r'^gps_\d+$').hasMatch(e.name)).length;
      } catch (_) {
        // Отсутствие GPS-каталога не отменяет остальные данные.
      }
    } catch (e) {
      print('[SystemInfo] FTP error: $e');
    } finally {
      try {
        await ftp?.close();
      } catch (_) {}
    }

    try {
      final meminfo = await telnet.runReadOnly('cat /proc/meminfo');
      final total = RegExp(r'^MemTotal:\s*(.+)$', multiLine: true).firstMatch(meminfo)?.group(1);
      final available = RegExp(r'^MemAvailable:\s*(.+)$', multiLine: true).firstMatch(meminfo)?.group(1) ??
          RegExp(r'^MemFree:\s*(.+)$', multiLine: true).firstMatch(meminfo)?.group(1);
      ram = 'Всего: ' + (total ?? 'N/A') + '; доступно: ' + (available ?? 'N/A');
    } catch (e) {
      ram = 'Недоступно: $e';
    }

    try {
      sdSpace = await telnet.runReadOnly('df -k /mnt/sd');
    } catch (e) {
      sdSpace = 'Недоступно: $e';
    }

    return SystemInfo(
      config: config,
      firmware: firmware,
      kernel: kernel,
      partitions: partitions,
      inittab: inittab,
      sysctl: sysctl,
      lastFile: lastFile,
      gpsLogCount: gpsCount,
      ram: ram,
      sdSpace: sdSpace,
    );
  }

  /// Читает текстовый файл с регистратора через FTP (CWD + RETR).
  Future<String> _readRemoteText(FtpClient ftp, String remotePath) async {
    final lastSlash = remotePath.lastIndexOf('/');
    if (lastSlash <= 0) return 'Недоступно';
    final dir = remotePath.substring(0, lastSlash);
    final name = remotePath.substring(lastSlash + 1);
    try {
      final cwd = await ftp.command('CWD $dir');
      if (cwd.code >= 400) return 'Недоступно';
      final dataSocket = await ftp.openRetrieve(name);
      final chunks = <int>[];
      await for (final chunk in dataSocket) {
        chunks.addAll(chunk);
      }
      dataSocket.destroy();
      return String.fromCharCodes(chunks);
    } catch (e) {
      return 'Недоступно: $e';
    }
  }
}
