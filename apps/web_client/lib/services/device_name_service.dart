import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import 'local_hostname.dart';

/// Resolves a useful device label from the current operating system.
class DeviceNameService {
  DeviceNameService._();

  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  static Future<String> getDefaultName() async {
    try {
      if (kIsWeb) {
        final info = await _deviceInfo.webBrowserInfo;
        final browser = _capitalize(info.browserName.name);
        final platform = switch (defaultTargetPlatform) {
          TargetPlatform.android => 'Android',
          TargetPlatform.iOS => 'iOS',
          TargetPlatform.macOS => 'Mac',
          TargetPlatform.windows => 'Windows',
          TargetPlatform.linux => 'Linux',
          TargetPlatform.fuchsia => 'Web',
        };
        return '$platform · $browser';
      }

      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final info = await _deviceInfo.androidInfo;
          final name = _usableName(info.name);
          if (name != null && !_isGenericAndroidName(name)) return name;
          final brand = _usableName(info.brand);
          final model = _usableName(info.model);
          if (brand != null && model != null) {
            return brand.toLowerCase() == model.toLowerCase()
                ? brand
                : '$brand $model';
          }
          return model ?? brand ?? 'Android';
        case TargetPlatform.iOS:
          final info = await _deviceInfo.iosInfo;
          final name = _usableName(info.name);
          if (name != null && !_isGenericAppleName(name)) return name;
          return _usableName(info.modelName) ??
              _usableName(info.localizedModel) ??
              'iPhone/iPad';
        case TargetPlatform.macOS:
          final info = await _deviceInfo.macOsInfo;
          return _usableName(info.computerName) ??
              _usableName(info.modelName) ??
              'Mac';
        case TargetPlatform.windows:
          final info = await _deviceInfo.windowsInfo;
          return _usableName(info.computerName) ??
              _usableName(info.productName) ??
              'Windows PC';
        case TargetPlatform.linux:
          return _usableName(await getLocalHostname()) ?? 'Linux PC';
        case TargetPlatform.fuchsia:
          return 'Fuchsia device';
      }
    } catch (error) {
      debugPrint('Could not read system device name: $error');
    }

    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'Android',
      TargetPlatform.iOS => 'iPhone/iPad',
      TargetPlatform.macOS => 'Mac',
      TargetPlatform.windows => 'Windows PC',
      TargetPlatform.linux => 'Linux PC',
      TargetPlatform.fuchsia => 'YonFile device',
    };
  }

  static String? _usableName(String? value) {
    final name = value?.trim();
    if (name == null || name.isEmpty || name.toLowerCase() == 'unknown') {
      return null;
    }
    return name;
  }

  static bool _isGenericAndroidName(String name) => const {
    'android',
    'localhost',
    'unknown',
  }.contains(name.trim().toLowerCase());

  static bool _isGenericAppleName(String name) => const {
    'iphone',
    'ipad',
    'ipod touch',
  }.contains(name.trim().toLowerCase());

  static String _capitalize(String value) =>
      value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
}
