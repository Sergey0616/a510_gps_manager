import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Одна запись в листинге FTP.
class FtpEntry {
  const FtpEntry({required this.name, required this.size, required this.isDirectory});
  final String name;
  final int size;
  final bool isDirectory;
}

/// Ответ FTP-сервера: код + текст.
class FtpResponse {
  const FtpResponse(this.code, this.text);
  final int code;
  final String text;
}

/// Минимальный FTP-клиент на Socket.
/// Совместим с busybox ftpd (70mai A510): только USER/PASS/TYPE/CWD/PASV/LIST/RETR/QUIT.
class FtpClient {
  FtpClient(this._control, this._lines);
  final Socket _control;
  final StreamIterator<String> _lines;
  bool _closed = false;

  static Future<FtpClient> connect(String host, int port, String username, String password) async {
    print('[FTP] connect $host:$port');
    final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 12));
    final client = FtpClient(socket, StreamIterator<String>(socket.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter())));
    final greeting = await client.readResponse();
    print('[FTP] greeting → ${greeting.code}');
    if (greeting.code >= 400) throw SocketException('FTP greeting: ${greeting.text}');
    final user = await client.command('USER $username');
    print('[FTP] USER → ${user.code}');
    if (user.code == 331) {
      final pass = await client.command('PASS $password');
      print('[FTP] PASS → ${pass.code}');
      if (pass.code >= 400) throw SocketException('FTP login: ${pass.text}');
    } else if (user.code >= 400) {
      throw SocketException('FTP login: ${user.text}');
    }
    final binary = await client.command('TYPE I');
    print('[FTP] TYPE I → ${binary.code}');
    if (binary.code >= 400) throw SocketException('FTP TYPE I: ${binary.text}');
    return client;
  }

  Future<FtpResponse> command(String command) async {
    if (_closed) throw const SocketException('FTP-соединение закрыто');
    _control.write('$command\r\n');
    await _control.flush();
    return readResponse();
  }

  Future<FtpResponse> readResponse() async {
    String? line;
    try {
      line = await _lines.moveNext().timeout(const Duration(seconds: 30)) ? _lines.current : null;
    } on TimeoutException {
      throw const SocketException('Тайм-аут ответа FTP');
    }
    if (line == null) throw const SocketException('FTP-соединение прервано');
    final match = RegExp(r'^(\d{3})([ -])(.*)$').firstMatch(line);
    if (match == null) return FtpResponse(0, line);
    final code = int.parse(match.group(1)!);
    final lines = <String>[line];
    if (match.group(2) == '-') {
      while (await _lines.moveNext().timeout(const Duration(seconds: 30))) {
        final next = _lines.current;
        lines.add(next);
        if (next.startsWith('$code ')) break;
      }
    }
    return FtpResponse(code, lines.join('\n'));
  }

  Future<Socket> _openPassiveDataSocket() async {
    final response = await command('PASV');
    if (response.code >= 400) throw SocketException('FTP PASV: ${response.text}');
    final match = RegExp(r'(\d{1,3},\d{1,3},\d{1,3},\d{1,3}),(\d{1,3}),(\d{1,3})').firstMatch(response.text);
    if (match == null) throw const SocketException('Не удалось разобрать ответ PASV');
    final ip = match.group(1)!.replaceAll(',', '.');
    final dataPort = int.parse(match.group(2)!) * 256 + int.parse(match.group(3)!);
    final address = InternetAddress.tryParse(ip) ?? _control.address;
    return Socket.connect(address, dataPort, timeout: const Duration(seconds: 12));
  }

  Future<List<FtpEntry>> list(String path) async {
    final data = await _openPassiveDataSocket();
    _control.write('LIST $path\r\n');
    await _control.flush();
    final initial = await readResponse();
    if (initial.code >= 400) { data.destroy(); throw FileSystemException('FTP LIST: ${initial.text}'); }
    final lines = await data.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter()).toList();
    data.destroy();
    final completion = await readResponse();
    if (completion.code >= 400) throw FileSystemException('FTP LIST: ${completion.text}');
    final entries = <FtpEntry>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('total ')) continue;
      final isDir = trimmed.startsWith('d');
      final unix = RegExp(r'^\S+\s+\d+\s+\S+\s+\S+\s+(\d+)\s+\w+\s+\d+\s+[\d:]+\s+(.+)$').firstMatch(trimmed);
      if (unix == null) continue;
      final name = unix.group(2)!;
      if (name == '.' || name == '..') continue;
      entries.add(FtpEntry(name: name, size: int.tryParse(unix.group(1)!) ?? -1, isDirectory: isDir));
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

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try { _control.write('QUIT\r\n'); await _control.flush(); } catch (_) {}
    try { await _lines.cancel(); } catch (_) {}
    _control.destroy();
  }
}

/// Расширение: корректная загрузка файла с чтением финального 226.
extension FtpClientRetrieve on FtpClient {
  Future<void> retrieveFile(String remotePath, File target) async {
    final data = await openRetrieve(remotePath);
    final sink = target.openWrite();
    try {
      await for (final chunk in data) {
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
    } finally {
      data.destroy();
    }
    final completion = await readResponse();
    if (completion.code >= 400) {
      throw FileSystemException('FTP RETR complete: ${completion.text}');
    }
  }
}
