import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Минимальный Telnet-клиент для штатных команд обслуживания регистратора.
/// Использовать только в доверенной Wi-Fi-сети: Telnet не шифрует трафик.
class TelnetService {
  TelnetService({required this.host, this.port = 23, this.username = 'root', this.password = ''});

  final String host;
  final int port;
  final String username;
  final String password;

  Future<String> runReadOnly(String command) async {
    const allowed = <String>{
      'cat /etc/profile_prjcfg', 'cat /etc/firmware.info', 'cat /proc/version',
      'cat /proc/mtd', 'cat /proc/meminfo', 'df -k /mnt/sd',
      'cat /etc/inittab', 'cat /etc/init.d/S99_Sysctl',
      'cat /mnt/other/.LastFileName', 'ls -1 /mnt/other/4g_gps',
      'tail -n 100 /mnt/other/log/logfile',
    };
    if (!allowed.contains(command)) throw ArgumentError('Команда не разрешена в режиме чтения');
    return _run(command);
  }

  Future<String> reboot() => _run('reboot');
  Future<String> restartMainApp() => _run('killall main_app; sleep 2; main_app &');
  Future<String> showLogs() => runReadOnly('tail -n 100 /mnt/other/log/logfile');

  Future<String> _run(String command) async {
    final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 10));
    final buffer = StringBuffer();
    Timer? idleTimer;
    Completer<void>? quietCompleter;
    var receivedAny = false;
    final subscription = socket.listen((bytes) {
      // Отвечаем на базовые Telnet-переговоры и удаляем IAC-последовательности.
      final cleaned = <int>[];
      for (var i = 0; i < bytes.length; i++) {
        if (bytes[i] == 255 && i + 2 < bytes.length) {
          final option = bytes[i + 1];
          if (option == 251 || option == 252) socket.add([255, 254, bytes[i + 2]]); // WILL/WONT -> DONT
          if (option == 253 || option == 254) socket.add([255, 252, bytes[i + 2]]); // DO/DONT -> WONT
          i += 2;
        } else {
          cleaned.add(bytes[i]);
        }
      }
      if (cleaned.isNotEmpty) {
        buffer.write(utf8.decode(cleaned, allowMalformed: true));
        receivedAny = true;
        idleTimer?.cancel();
        idleTimer = Timer(const Duration(milliseconds: 500), () {
          if (quietCompleter != null && !quietCompleter!.isCompleted) quietCompleter!.complete();
        });
      }
    }, onError: (Object _) {}, onDone: () {
      if (quietCompleter != null && !quietCompleter!.isCompleted) quietCompleter!.complete();
    });

    Future<String> readQuietly({Duration timeout = const Duration(seconds: 5)}) async {
      quietCompleter = Completer<void>();
      idleTimer?.cancel();
      idleTimer = Timer(const Duration(milliseconds: 900), () {
        if (!quietCompleter!.isCompleted) quietCompleter!.complete();
      });
      try {
        await quietCompleter!.future.timeout(timeout);
      } on TimeoutException {
        // Возвращаем то, что успели получить; далее команда может быть повторена.
      }
      idleTimer?.cancel();
      final value = buffer.toString();
      buffer.clear();
      return value;
    }

    try {
      await readQuietly(); // приветствие и приглашение логина
      socket.write('$username\n');
      await socket.flush();
      var prompt = await readQuietly();
      if (prompt.toLowerCase().contains('password')) {
        socket.write('$password\n');
        await socket.flush();
        prompt = await readQuietly();
      }
      if (!receivedAny && prompt.isEmpty) throw const SocketException('Telnet не ответил');
      socket.write('$command\n');
      await socket.flush();
      return await readQuietly(timeout: const Duration(seconds: 12));
    } finally {
      idleTimer?.cancel();
      await subscription.cancel();
      socket.destroy();
    }
  }
}
