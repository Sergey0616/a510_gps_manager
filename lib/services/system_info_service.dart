import 'dart:io';

import 'package:ftpconnect/ftpconnect.dart';
import 'package:path_provider/path_provider.dart';

import 'telnet_service.dart';

class SystemInfo {
  const SystemInfo({this.config = '', this.firmware = '', this.kernel = '', this.partitions = '', this.inittab = '', this.sysctl = '', this.lastFile = '', this.gpsLogCount = 0, this.ram = '', this.sdSpace = '', this.wifiMac = 'N/A', this.ssid = 'N/A', this.ip = 'N/A'});
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
      final match = RegExp('^\\s*${RegExp.escape(key)}\\s*=\\s*(.*)\$').firstMatch(line);
      if (match == null) continue;
      var value = match.group(1)!.trim();
      if (value.length >= 2 && ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'")))) {
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
    final ftp = FTPConnect(host, port: 21, user: username, pass: password, timeout: 15, showLog: false);
    final telnet = TelnetService(host: host, username: username, password: password);
    var config = '', firmware = '', kernel = '', partitions = '', inittab = '', sysctl = '', lastFile = '', ram = '', sdSpace = '';
    var gpsCount = 0;
    try {
      if (!await ftp.connect()) throw const SocketException('FTP недоступен');
      config = await _readRemoteText(ftp, '/etc/profile_prjcfg');
      firmware = await _readRemoteText(ftp, '/etc/firmware.info');
      kernel = await _readRemoteText(ftp, '/proc/version');
      partitions = await _readRemoteText(ftp, '/proc/mtd');
      inittab = await _readRemoteText(ftp, '/etc/inittab');
      sysctl = await _readRemoteText(ftp, '/etc/init.d/S99_Sysctl');
      lastFile = await _readRemoteText(ftp, '/mnt/other/.LastFileName');
      try {
        await ftp.changeDirectory('/mnt/other/4g_gps');
        final entries = await ftp.listDirectoryContent();
        gpsCount = entries.where((entry) => RegExp(r'^gps_\d+$').hasMatch(entry.name)).length;
      } catch (_) {
        // Отсутствие GPS-каталога не отменяет остальные диагностические данные.
      }
    } finally {
      try { await ftp.disconnect(); } catch (_) { /* Соединение могло быть закрыто сервером. */ }
    }
    try {
      final meminfo = await telnet.runReadOnly('cat /proc/meminfo');
      final total = RegExp(r'^MemTotal:\s*(.+)$', multiLine: true).firstMatch(meminfo)?.group(1);
      final available = RegExp(r'^MemAvailable:\s*(.+)$', multiLine: true).firstMatch(meminfo)?.group(1) ?? RegExp(r'^MemFree:\s*(.+)$', multiLine: true).firstMatch(meminfo)?.group(1);
      ram = 'Всего: ${total ?? "N/A"}; доступно: ${available ?? "N/A"}';
    } catch (e) { ram = 'Недоступно: $e'; }
    try { sdSpace = await telnet.runReadOnly('df -k /mnt/sd'); } catch (e) { sdSpace = 'Недоступно: $e'; }
    return SystemInfo(config: config, firmware: firmware, kernel: kernel, partitions: partitions, inittab: inittab, sysctl: sysctl, lastFile: lastFile, gpsLogCount: gpsCount, ram: ram, sdSpace: sdSpace);
  }

  Future<String> _readRemoteText(FTPConnect ftp, String remotePath) async {
    final tempDir = await getTemporaryDirectory();
    final safe = remotePath.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    final local = File('${tempDir.path}/a510_info_$safe');
    try {
      final ok = await ftp.downloadFile(remotePath, local);
      if (!ok || !await local.exists()) return 'Недоступно';
      return await local.readAsString();
    } catch (_) {
      return 'Недоступно';
    } finally {
      try { if (await local.exists()) await local.delete(); } catch (_) { /* Временный файл мог исчезнуть. */ }
    }
  }
}
