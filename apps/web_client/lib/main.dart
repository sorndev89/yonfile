import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/constants/app_config.dart';
import 'core/theme/yon_theme.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/splash_screen.dart';

void main() {
  runApp(const YonFileApp());
}

class YonFileApp extends StatefulWidget {
  const YonFileApp({super.key});

  @override
  State<YonFileApp> createState() => _YonFileAppState();
}

class _YonFileAppState extends State<YonFileApp> {
  ThemeMode _themeMode = ThemeMode.dark;
  bool _startupComplete = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final minimumSplashTime = Future<void>.delayed(
      const Duration(milliseconds: 900),
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      final isDark = prefs.getBool('dark_mode');
      if (isDark != null) {
        _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
      }
    } catch (_) {
      // Keep the default dark theme if local preferences are unavailable.
    }
    await minimumSplashTime;
    if (mounted) setState(() => _startupComplete = true);
  }

  Future<void> _toggleTheme() async {
    final next = _themeMode == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    setState(() => _themeMode = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', next == ThemeMode.dark);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appNameEn,
      debugShowCheckedModeBanner: false,
      theme: YonTheme.lightTheme,
      darkTheme: YonTheme.darkTheme,
      themeMode: _themeMode,
      // Keep mouse, trackpad, touch and keyboard scrolling while hiding the
      // automatically-added desktop scrollbar decorations.
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        scrollbars: false,
      ),
      home: _startupComplete
          ? HomeScreen(themeMode: _themeMode, onToggleTheme: _toggleTheme)
          : const YonFileSplashScreen(),
    );
  }
}
