import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../core/constants/app_config.dart';

class TransferCancelledException implements Exception {
  const TransferCancelledException();
}

/// ຈັດການຕັດໄຟລ໌ເປັນຕ່ອນ 64 KB, ຄວບຄຸມ Backpressure ແລະ ກວດ SHA-256.
class FileChunkerService {
  static const int chunkSize = AppConfig.chunkSize;

  /// ຄິດໄລ່ SHA-256 ຂອງໄຟລ໌ທັງໝົດ.
  String sha256Of(Uint8List data) => sha256.convert(data).toString();

  /// ແຍກ bytes ອອກເປັນຕ່ອນໆ.
  Iterable<Uint8List> chunks(Uint8List data) sync* {
    for (var offset = 0; offset < data.length; offset += chunkSize) {
      final end = (offset + chunkSize).clamp(0, data.length);
      yield Uint8List.sublistView(data, offset, end);
    }
  }

  /// ສົ່ງໄຟລ໌ຜ່ານ DataChannel ພ້ອມ backpressure & progress.
  Future<void> sendFile({
    required Uint8List bytes,
    required Future<void> Function(Uint8List chunk) sendChunk,
    required int Function() bufferedAmount,
    required void Function(int sent) onProgress,
    required bool Function() isCancelled,
  }) async {
    var offset = 0;
    while (offset < bytes.length) {
      if (isCancelled()) throw const TransferCancelledException();

      // ລໍຖ້າໃຫ້ Buffer ຫຼຸດລົງກ່ອນ (ປ້ອງກັນ browser/ອຸປະກອນຄ້າງ).
      while (bufferedAmount() > AppConfig.maxBufferedAmount) {
        await Future<void>.delayed(
          const Duration(milliseconds: AppConfig.backpressurePollMs),
        );
        if (isCancelled()) throw const TransferCancelledException();
      }

      final end = (offset + chunkSize).clamp(0, bytes.length);
      await sendChunk(Uint8List.sublistView(bytes, offset, end));
      offset = end;
      onProgress(offset);
    }
  }
}

/// ເກັບຕ່ອນໄຟລ໌ທີ່ຮັບເຂົ້າມາ ຈົນຄົບ ແລ້ວກວດສອບ SHA-256.
class IncomingFile {
  IncomingFile({
    required this.id,
    required this.fileName,
    required this.fileSize,
    this.expectedSha256,
  }) : _stopwatch = Stopwatch()..start();

  final String id;
  final String fileName;
  final int fileSize;
  final String? expectedSha256;

  final BytesBuilder _builder = BytesBuilder(copy: false);
  final Stopwatch _stopwatch;
  int received = 0;
  double bytesPerSecond = 0;
  Uint8List? _finalBytes;

  double get progress =>
      fileSize <= 0 ? 0 : (received / fileSize).clamp(0.0, 1.0);

  void addChunk(Uint8List chunk) {
    _builder.add(chunk);
    received += chunk.length;
    final seconds = _stopwatch.elapsedMilliseconds / 1000.0;
    if (seconds > 0.15) {
      bytesPerSecond = received / seconds;
    }
  }

  /// ດຶງ bytes ອອກຄັ້ງດຽວ (idempotent).
  Uint8List takeBytes() => _finalBytes ??= _builder.takeBytes();

  Future<bool> verify() async {
    final data = takeBytes();
    if (data.length != fileSize ||
        expectedSha256 == null ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedSha256!)) {
      return false;
    }
    final digest = sha256.convert(data);
    return digest.toString() == expectedSha256;
  }
}
