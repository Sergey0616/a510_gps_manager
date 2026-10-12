import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';
import '../services/ftp_service.dart';
import '../services/gps_parser.dart';
import '../services/storage_service.dart';

/// Общее состояние приложения и управление синхронизацией.
class TracksProvider extends ChangeNotifier {
  TracksProvider({required this.storage, required this.parser});

  final StorageService storage;
  final GpsParser parser;
  static const _wifiChannel = MethodChannel('ru.a510.gpsmanager/wifi');

  List<Track> _tracks = <Track>[];
  List<Track> get tracks => List.unmodifiable(_tracks);
  bool _busy = false;
  bool get busy => _busy;
  String? _error;
  String? get error => _error;
  String _status = 'Готово';
  String get status => _status;
  int _progressDone = 0;
  int _progressTotal = 0;
  int get progressDone => _progressDone;
  int get progressTotal => _progressTotal;
  DateTime? _lastSync;
  DateTime? get lastSync => _lastSync;
  String _host = '192.168.0.1';
  String get host => _host;
  String _username = 'root';
  String get username => _username;
  String _password = '';
  String get password => _password;
  bool _autoSync = false;
  bool get autoSync => _autoSync;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  double get totalDistanceKm => _tracks.fold(0.0, (sum, track) => sum + track.distanceKm);

  Future<void> initialize() async {
    await storage.initialize();
    final prefs = await SharedPreferences.getInstance();
    _host = prefs.getString('ftp_host') ?? '192.168.0.1';
    _username = prefs.getString('ftp_username') ?? 'root';
    _password = prefs.getString('ftp_password') ?? '';
    _autoSync = prefs.getBool('auto_sync') ?? false;
    final last = prefs.getInt('last_sync_ms');
    if (last != null) _lastSync = DateTime.fromMillisecondsSinceEpoch(last);
    _tracks = await storage.loadTracks();
    _sortTracks();
    unawaited(_watchNetwork());
    notifyListeners();
  }

  Future<void> saveSettings({
    required String host,
    required String username,
    required String password,
    required bool autoSync,
  }) async {
    _host = host.trim();
    _username = username.trim();
    _password = password;
    var effectiveAutoSync = autoSync;
    if (autoSync) {
      final status = await Permission.locationWhenInUse.request();
      effectiveAutoSync = status.isGranted;
      if (!status.isGranted) {
        _error = 'Для проверки имени Wi-Fi необходимо разрешение на геолокацию';
      } else {
        _error = null;
      }
    }
    _autoSync = effectiveAutoSync;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ftp_host', _host);
    await prefs.setString('ftp_username', _username);
    await prefs.setString('ftp_password', _password);
    await prefs.setBool('auto_sync', _autoSync);
    unawaited(_watchNetwork());
    notifyListeners();
  }

  FtpService _ftp() => FtpService(host: _host, username: _username, password: _password);

  Future<bool> testConnection() async {
    _error = null;
    _status = 'Проверка FTP…';
    notifyListeners();
    try {
      final ok = await _ftp().testConnection();
      _status = ok ? 'FTP доступен' : 'FTP недоступен: проверьте Wi-Fi и путь';
      if (!ok) _error = _status;
      return ok;
    } catch (e) {
      _error = 'Ошибка FTP: $e';
      _status = 'Ошибка подключения';
      return false;
    } finally {
      notifyListeners();
    }
  }

  Future<void> synchronize() async {
    if (_busy) return;
    _busy = true;
    _error = null;
    _status = 'Подключение к регистратору…';
    _progressDone = 0;
    _progressTotal = 0;
    notifyListeners();
    try {
      // === 1. GPSData000001.txt — полный трек за всё время ===
      _status = 'Загрузка GPSData000001.txt…';
      notifyListeners();
      final gpsDataFile = await _ftp().downloadGpsDataFile(destination: storage.gpsDirectory);
      var gpsDataTracks = <Track>[];
      if (gpsDataFile != null) {
        _status = 'Парсинг GPSData000001.txt…';
        notifyListeners();
        final content = await gpsDataFile.readAsString();
        gpsDataTracks = await parser.parseGpsDataFile(content);
        print('[Sync] GPSData: ${gpsDataTracks.length} треков');
      }

      // === 2. Свежие gps_* ===
      _status = 'Загрузка свежих gps_*…';
      notifyListeners();
      final downloaded = await _ftp().downloadGpsFiles(
        destination: storage.gpsDirectory,
        onProgress: (done, total) {
          _progressDone = done;
          _progressTotal = total;
          _status = total == 0 ? 'Свежие gps_* не найдены' : 'Свежие: $done из $total';
          notifyListeners();
        },
      );
      final freshFiles = await storage.gpsDirectory
          .list()
          .where((entity) => entity is File && RegExp(r'[/\\]gps_\d+$').hasMatch(entity.path))
          .cast<File>()
          .toList();
      var freshTracks = <Track>[];
      if (freshFiles.isNotEmpty) {
        _status = 'Парсинг свежих gps_*…';
        notifyListeners();
        freshTracks = await parser.parseFiles(freshFiles);
      }

      // === 3. Объединяем ===
      final allTracks = <Track>[];
      allTracks.addAll(gpsDataTracks);
      allTracks.addAll(freshTracks);
      print('[Sync] GPSData: ${gpsDataTracks.length}, fresh: ${freshTracks.length}, total: ${allTracks.length}');

      if (allTracks.isEmpty) {
        throw StateError('Не удалось получить ни одного трека');
      }

      // === 4. Сохраняем ===
      await storage.saveTracks(allTracks);
      _tracks = await storage.loadTracks();
      _sortTracks();
      _lastSync = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('last_sync_ms', _lastSync!.millisecondsSinceEpoch);
      _status = 'Готово: GPSData ${gpsDataTracks.length}, свежих ${freshTracks.length}, всего ${_tracks.length}';
    } catch (e) {
      _error = 'Синхронизация не удалась: $e';
      _status = 'Ошибка синхронизации';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> deleteTrack(Track track) async {
    final path = track.gpxPath;
    if (path != null) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } else {
      final safeId = track.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final file = File('${storage.parsedDirectory.path}/track_$safeId.gpx');
      if (await file.exists()) await file.delete();
    }
    _tracks = await storage.loadTracks();
    _sortTracks();
    notifyListeners();
  }

  Future<void> clearAllTracks() async {
    await storage.clearAll();
    _tracks = <Track>[];
    _lastSync = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('last_sync_ms');
    notifyListeners();
  }

  Future<int> get storageSizeBytes => storage.getStorageSizeBytes();

  void _sortTracks() => _tracks.sort((a, b) => b.startUtc.compareTo(a.startUtc));

  Future<void> _watchNetwork() async {
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    if (!_autoSync) return;
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) async {
      if (!results.contains(ConnectivityResult.wifi) || _busy) return;
      try {
        if (!await Permission.locationWhenInUse.isGranted) {
          _status = 'Нужно разрешение для чтения SSID';
          notifyListeners();
          return;
        }
        final ssidRaw = await _wifiChannel.invokeMethod<String>('getWifiSsid');
        final ssid = (ssidRaw ?? '').replaceAll('"', '').trim();
        if (ssid.startsWith('70mai_')) {
          await synchronize();
        } else {
          _status = ssid.isEmpty || ssid == '<unknown ssid>'
              ? 'Wi-Fi подключён, SSID недоступен'
              : 'Подключена сеть $ssid';
          notifyListeners();
        }
      } catch (_) {
        _status = 'Не удалось определить SSID Wi-Fi';
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}
