import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// ຄ່າຄົງທີ່ຂອງລະບົບ (Chunk size, STUN/TURN, Signaling URL).
class AppConfig {
  AppConfig._();

  static const String appName = 'ໂຍນໄຟລ໌';
  static const String appNameEn = 'YonFile';

  /// ຂະໜາດ Chunk 64 KB.
  static const int chunkSize = 64 * 1024;

  /// ຂີດຈຳກັດ Buffer ສູງສຸດ 1 MB (Backpressure control).
  static const int maxBufferedAmount = 1024 * 1024;

  /// ເວລາລໍຖ້າລະຫວ່າງກວດ Buffer (ms).
  static const int backpressurePollMs = 20;
  static const int maxFileSizeBytes = 512 * 1024 * 1024;

  static const String _envSignalingUrl = String.fromEnvironment(
    'SIGNALING_URL',
  );
  static const String _envStunUrl = String.fromEnvironment('STUN_URL');

  /// Public STUN ຟຣີຂອງ Google.
  static const String defaultStunUrl = 'stun:stun.l.google.com:19302';

  static String get stunUrl =>
      _envStunUrl.isNotEmpty ? _envStunUrl : defaultStunUrl;

  /// ສ້າງ ICE servers list ສຳລັບ RTCPeerConnection.
  static Future<List<Map<String, dynamic>>> iceServers() async {
    try {
      final base = _envSignalingUrl.isNotEmpty
          ? Uri.parse(_envSignalingUrl)
          : Uri.base;
      final endpoint = base.replace(
        scheme: base.scheme == 'https' ? 'https' : 'http',
        path: '/api/ice-servers',
        query: null,
        fragment: null,
      );
      final response = await http
          .get(endpoint)
          .timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final values = decoded['iceServers'] as List<dynamic>;
        return values.cast<Map<String, dynamic>>();
      }
    } catch (error) {
      debugPrint('Unable to load ICE server credentials: $error');
    }
    return [
      {'urls': stunUrl},
    ];
  }

  /// Signaling URL. ຖ້າບໍ່ໄດ້ກຳນົດຜ່ານ --dart-define ຈະໃຊ້ host ດຽວກັນກັບໜ້າເວັບ.
  static String get signalingUrl {
    if (_envSignalingUrl.isNotEmpty) return _envSignalingUrl;

    final base = Uri.base;
    final isSecure = base.scheme == 'https';
    final scheme = isSecure ? 'wss' : 'ws';
    final host = base.host.isEmpty ? 'localhost' : base.host;

    var port = base.port;
    // ໃນໂໝດ dev (flutter run --web-port 8080) server ແລ່ນຢູ່ 3000.
    if (kDebugMode && (port == 0 || port == 8080)) {
      port = 3000;
    }

    final portPart = (port == 0 || port == 80 || port == 443) ? '' : ':$port';
    return '$scheme://$host$portPart/ws';
  }
}
