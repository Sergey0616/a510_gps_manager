import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/tracks_provider.dart';
import '../services/storage_paths.dart';
import '../services/system_info_service.dart';
import '../services/telnet_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _host = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _autoSync = false;
  bool _hidePassword = true;
  bool _loaded = false;
  bool _testing = false;
  bool _loadingInfo = false;
  bool _runningAction = false;
  SystemInfo? _info;
  String? _infoError;
  String _logs = '';

  // Укажите URL репозитория после публикации исходного кода.
  static const String _githubRepositoryUrl = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    final provider = context.read<TracksProvider>();
    _host.text = provider.host;
    _username.text = provider.username;
    _password.text = provider.password;
    _autoSync = provider.autoSync;
    _loaded = true;
  }

  @override
  void dispose() {
    _host.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _pickFolder() async {
    try {
      final picked = await FilePicker.platform.getDirectoryPath();
      if (picked == null) return;
      await StoragePaths.setCustomPath(picked);
      await _reinitStorage();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Папка: $picked')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка выбора папки: $e')),
      );
    }
  }

  Future<void> _resetFolder() async {
    await StoragePaths.setCustomPath(null);
    await _reinitStorage();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Используется стандартная папка')),
    );
  }

  Future<void> _reinitStorage() async {
    final provider = context.read<TracksProvider>();
    await provider.reloadFromDisk();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    await context.read<TracksProvider>().saveSettings(host: _host.text, username: _username.text, password: _password.text, autoSync: _autoSync);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Настройки сохранены')));
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;
    await _save();
    if (!mounted) return;
    setState(() => _testing = true);
    final ok = await context.read<TracksProvider>().testConnection();
    if (!mounted) return;
    setState(() => _testing = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'FTP доступен' : 'Не удалось подключиться. Проверьте Wi-Fi, логин и каталог.')));
  }

  Future<void> _loadInfo() async {
    final provider = context.read<TracksProvider>();
    setState(() { _loadingInfo = true; _infoError = null; });
    try {
      final info = await SystemInfoService(host: provider.host, username: provider.username, password: provider.password).load();
      if (mounted) setState(() => _info = info);
    } catch (error) {
      if (mounted) setState(() => _infoError = 'Не удалось прочитать информацию: $error');
    } finally {
      if (mounted) setState(() => _loadingInfo = false);
    }
  }

  Future<void> _clearData() async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Удалить все данные?'),
      content: const Text('Будут удалены GPS-файлы, GPX, сводная таблица и скачанные видео/фото. Это действие нельзя отменить.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить всё'))],
    ));
    if (confirmed != true || !mounted) return;
    await context.read<TracksProvider>().clearAllTracks();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Данные приложения очищены')));
  }

  Future<void> _confirmDeviceAction({required String title, required String message, required Future<String> Function(TelnetService) action}) async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Продолжить'))],
    ));
    if (confirmed != true || !mounted) return;
    final provider = context.read<TracksProvider>();
    setState(() => _runningAction = true);
    try {
      final output = await action(TelnetService(host: provider.host, username: provider.username, password: provider.password));
      if (!mounted) return;
      if (title.contains('логи')) {
        setState(() => _logs = output.trim().isEmpty ? 'Регистратор не вернул текст.' : output);
        await showDialog<void>(context: context, builder: (context) => AlertDialog(
          title: const Text('Последние 100 строк лога'),
          content: SizedBox(width: double.maxFinite, height: 420, child: SingleChildScrollView(child: SelectableText(_logs))),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Закрыть'))],
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(output.trim().isEmpty ? 'Команда отправлена. Ответ устройства отсутствует.' : output.trim())));
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Команда не выполнена: $error')));
    } finally {
      if (mounted) setState(() => _runningAction = false);
    }
  }

  Future<void> _resetSettings() async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Сбросить настройки?'),
      content: const Text('Адрес будет сброшен на 192.168.0.1, логин — root, пароль — пустой, автосинхронизация будет выключена.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Сбросить'))],
    ));
    if (confirmed != true || !mounted) return;
    _host.text = '192.168.0.1';
    _username.text = 'root';
    _password.clear();
    setState(() { _autoSync = false; _info = null; _infoError = null; });
    await context.read<TracksProvider>().saveSettings(host: _host.text, username: _username.text, password: '', autoSync: false);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Настройки сброшены')));
  }

  String _bytes(int bytes) {
    if (bytes < 1024) return '$bytes Б';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} КБ';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} ГБ';
  }

  Widget _detail(String label, String value) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: Text(label)), const SizedBox(width: 12), Expanded(child: SelectableText(value.trim().isEmpty ? 'N/A' : value.trim(), textAlign: TextAlign.end))]));

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TracksProvider>();
    final info = _info;
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('FTP', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Form(key: _formKey, child: Column(children: [
          TextFormField(controller: _host, decoration: const InputDecoration(labelText: 'IP регистратора', hintText: '192.168.0.1', border: OutlineInputBorder()), keyboardType: TextInputType.url, validator: (value) => value == null || value.trim().isEmpty ? 'Введите IP или адрес хоста' : null),
          const SizedBox(height: 12),
          TextFormField(controller: _username, decoration: const InputDecoration(labelText: 'Логин FTP / Telnet', border: OutlineInputBorder()), validator: (value) => value == null || value.trim().isEmpty ? 'Введите логин' : null),
          const SizedBox(height: 12),
          TextFormField(controller: _password, obscureText: _hidePassword, decoration: InputDecoration(labelText: 'Пароль FTP / Telnet', helperText: 'Оставьте пустым, если пароля нет', border: const OutlineInputBorder(), suffixIcon: IconButton(icon: Icon(_hidePassword ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => _hidePassword = !_hidePassword)))),
        ])),
        const SizedBox(height: 12),
        SizedBox(height: 52, child: FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('Сохранить настройки'))),
        const SizedBox(height: 8),
        SizedBox(height: 52, child: OutlinedButton.icon(onPressed: _testing ? null : _testConnection, icon: _testing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.wifi_find), label: const Text('Тест подключения FTP'))),
        const Divider(height: 32),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Автосинхронизация GPS'), subtitle: const Text('При подключении к Wi-Fi с именем 70mai_*. Нужны разрешения Android.'), value: _autoSync, onChanged: (value) async { setState(() => _autoSync = value); await _save(); }),
        const Divider(height: 32),
        Text('О устройстве', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        SizedBox(height: 52, child: OutlinedButton.icon(onPressed: _loadingInfo ? null : _loadInfo, icon: _loadingInfo ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.system_update_alt), label: const Text('Прочитать данные регистратора'))),
        if (_infoError != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_infoError!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        if (info != null) ...[
          Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _detail('Модель', info.configValue('CONFIG_DEVICE_MODEL')),
            _detail('Чип (если указан в конфигурации)', info.configValue('CONFIG_CHIP')),
            _detail('Прошивка', info.configValue('CONFIG_SOFT_VERSION')),
            _detail('Дата версии', info.configValue('CONFIG_VERSION_DATE')),
            _detail('Канал', info.configValue('CONFIG_DEV_CHN')),
            _detail('Иностранный канал', info.configValue('CONFIG_DEV_CHN_FOREIGN')),
            _detail('Язык', info.configValue('CONFIG_LANGUAGE')),
            _detail('Версия 4G', info.configValue('CONFIG_4G_VERSION')),
            _detail('SDK / firmware.info', info.firmware),
          ]))),
          ExpansionTile(title: const Text('Все переменные CONFIG_*'), children: [
            Padding(padding: const EdgeInsets.all(12), child: SelectableText(
              info.config.split(RegExp(r'\r?\n')).where((line) => line.trim().startsWith('CONFIG_')).join('\n').isEmpty
                  ? 'Переменные CONFIG_* не прочитаны.'
                  : info.config.split(RegExp(r'\r?\n')).where((line) => line.trim().startsWith('CONFIG_')).join('\n'),
            )),
          ]),
          ExpansionTile(title: const Text('Система'), children: [Padding(padding: const EdgeInsets.all(12), child: Column(children: [
            _detail('Ядро', info.kernel),
            _detail('RAM (/proc/meminfo)', info.ram),
            _detail('Свободное место SD (df)', info.sdSpace),
            _detail('Карта разделов (/proc/mtd)', info.partitions),
            _detail('Wi-Fi MAC', info.wifiMac),
            _detail('SSID', info.ssid),
            _detail('IP', info.ip),
          ]))]),
          ExpansionTile(title: const Text('Скрипты и состояние записи'), children: [Padding(padding: const EdgeInsets.all(12), child: Column(children: [
            _detail('Последний файл', info.lastFile),
            _detail('GPS-логов', '${info.gpsLogCount}'),
            _detail('/etc/inittab', info.inittab),
            _detail('/etc/init.d/S99_Sysctl', info.sysctl),
          ]))]),
        ] else
          const ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.info_outline), title: Text('Данные устройства ещё не загружены'), subtitle: Text('Сведения доступны, если FTP/Telnet регистратора разрешает чтение указанных файлов.')),
        const Divider(height: 32),
        Text('Действия с регистратором', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.restart_alt), title: const Text('Перезагрузить регистратор'), subtitle: const Text('Запись прервётся; устройство временно станет недоступно.'), enabled: !_runningAction, onTap: () => _confirmDeviceAction(title: 'Перезагрузить регистратор?', message: 'Вы уверены? Регистратор перезагрузится, текущая запись прервётся.', action: (telnet) => telnet.reboot())),
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.refresh), title: const Text('Перезапустить main_app'), subtitle: const Text('Интерфейс и запись могут кратковременно прерваться.'), enabled: !_runningAction, onTap: () => _confirmDeviceAction(title: 'Перезапустить main_app?', message: 'Вы уверены? Приложение регистратора будет перезапущено; запись может прерваться.', action: (telnet) => telnet.restartMainApp())),
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.article_outlined), title: const Text('Показать логи'), subtitle: const Text('Последние 100 строк /mnt/other/log/logfile'), enabled: !_runningAction, onTap: () => _confirmDeviceAction(title: 'Показать логи?', message: 'Будет выполнено чтение последних 100 строк системного лога.', action: (telnet) => telnet.showLogs())),
        if (_runningAction) const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())),
        const Divider(height: 32),
        Text('Экспорт данных', style: Theme.of(context).textTheme.titleLarge),
        FutureBuilder<String?>(
          future: StoragePaths.getCustomPath(),
          builder: (context, snapshot) {
            final custom = snapshot.data;
            return FutureBuilder<String>(
              future: custom != null ? Future.value(custom) : StoragePaths.defaultPath(),
              builder: (context, pathSnap) {
                final currentPath = pathSnap.data ?? '…';
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.folder),
                      title: const Text('Папка сохранения'),
                      subtitle: Text(
                        currentPath,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickFolder,
                            icon: const Icon(Icons.folder_open),
                            label: const Text('Выбрать папку'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: custom == null ? null : _resetFolder,
                          child: const Text('Сбросить'),
                        ),
                      ],
                    ),
                    if (custom == null)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'По умолчанию — приватная папка приложения. Выберите /Download/A510, чтобы файлы были видны в файловом менеджере.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.storage), title: const Text('Размер локальных данных'), subtitle: FutureBuilder<int>(future: provider.storageSizeBytes, builder: (context, snapshot) { if (snapshot.connectionState == ConnectionState.waiting) return const Text('Подсчёт…'); if (snapshot.hasError) return const Text('Не удалось определить размер'); return Text(_bytes(snapshot.data ?? 0)); })),
        SizedBox(height: 52, child: OutlinedButton.icon(style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error), onPressed: _clearData, icon: const Icon(Icons.delete_forever), label: const Text('Очистить всё'))),
        const Divider(height: 32),
        Text('О приложении', style: Theme.of(context).textTheme.titleLarge),
        const ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.info_outline), title: Text('70mai A510 GPS Manager'), subtitle: const Text('Версия приложения: 1.1.0+4')),
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.code), title: const Text('GitHub-репозиторий'), subtitle: Text(_githubRepositoryUrl.isEmpty ? 'Ссылка не настроена — добавьте URL после публикации проекта.' : _githubRepositoryUrl), enabled: _githubRepositoryUrl.isNotEmpty, onTap: _githubRepositoryUrl.isEmpty ? null : () {}),
        SizedBox(height: 52, child: OutlinedButton.icon(onPressed: _resetSettings, icon: const Icon(Icons.settings_backup_restore), label: const Text('Сбросить настройки'))),
        const SizedBox(height: 12),
        Text('FTP и Telnet передают данные без шифрования. Подключайтесь только к доверенной Wi-Fi-сети регистратора. Сетевые сведения, недоступные через FTP/Telnet, отображаются как N/A.', style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }
}
