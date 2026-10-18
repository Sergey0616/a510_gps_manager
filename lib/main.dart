import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:media_kit/media_kit.dart';

import 'providers/tracks_provider.dart';
import 'screens/home_screen.dart';
import 'screens/video_screen.dart';
import 'services/gps_parser.dart';
import 'services/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final provider = TracksProvider(storage: StorageService(), parser: const GpsParser());
  try {
    await provider.initialize();
  } catch (_) {
    // Ошибка инициализации будет отображена на главном экране при дальнейшей работе.
  }
  runApp(ChangeNotifierProvider.value(value: provider, child: const A510App()));
}

class A510App extends StatelessWidget {
  const A510App({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: '70mai GPS Manager',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.system,
        theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
        darkTheme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal, brightness: Brightness.dark)),
        routes: {'/video': (_) => const VideoScreen()},
        home: const HomeScreen(),
      );
}
