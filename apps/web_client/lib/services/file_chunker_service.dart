import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../core/constants/app_config.dart';
import 'incoming_file_sink.dart';

class TransferCancelledException implements Exception {
  const TransferCancelledException();
}

class TransferStalledException implements Exception {
  const TransferStalledException();

  @override
  String toString() => 'Transfer stalled: data channel made no progress';
}

/// ຈັດການຕັດໄຟລ໌ເປັນຕ່ອນ 16 KB, ຄວບຄຸມ Backpressure ແລະ ກວດ SHA-256.
class FileChunkerService {
  static const int chunkSize = AppConfig.chunkSize;

  Future<String> sendStream({
    required Stream<List<int>> stream,
    required int expectedSize,
    required Future<void> Function(Uint8List chunk) sendChunk,
    required int Function() bufferedAmount,
    required void Function(int sent) onProgress,
    required bool Function() isCancelled,
    required bool Function() isChannelOpen,
  }) async {
    final digestSink = _DigestSink();
    final hashSink = sha256.startChunkedConversion(digestSink);
    var sent = 0;
    var lastProgress = DateTime.now();
    var hashClosed = false;
    try {
      await for (final source in stream.timeout(
        const Duration(seconds: AppConfig.transferStallTimeoutSeconds),
      )) {
        if (source.isEmpty) continue;
        if (sent + source.length > expectedSize) {
          throw StateError('Picked file size changed while sending');
        }
        hashSink.add(source);
        final sourceBytes = Uint8List.fromList(source);
        for (var offset = 0; offset < source.length; offset += chunkSize) {
          if (isCancelled()) throw const TransferCancelledException();
          if (!isChannelOpen()) throw const TransferStalledException();
          while (bufferedAmount() > AppConfig.maxBufferedAmount) {
            if (isCancelled()) throw const TransferCancelledException();
            if (!isChannelOpen() ||
                DateTime.now().difference(lastProgress) >=
                    const Duration(
                      seconds: AppConfig.transferStallTimeoutSeconds,
                    )) {
              throw const TransferStalledException();
            }
            await Future<void>.delayed(
              const Duration(milliseconds: AppConfig.backpressurePollMs),
            );
          }
          final end = (offset + chunkSize).clamp(0, source.length);
          await sendChunk(
            Uint8List.sublistView(sourceBytes, offset, end),
          ).timeout(
            const Duration(seconds: AppConfig.transferStallTimeoutSeconds),
          );
          sent += end - offset;
          lastProgress = DateTime.now();
          onProgress(sent);
        }
      }
      hashSink.close();
      hashClosed = true;
      if (sent != expectedSize || digestSink.value == null) {
        throw StateError('Picked file size changed while sending');
      }
      return digestSink.value.toString();
    } on TimeoutException {
      throw const TransferStalledException();
    } finally {
      if (!hashClosed) hashSink.close();
    }
  }

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
    required bool Function() isChannelOpen,
  }) async {
    var offset = 0;
    var lastDrain = DateTime.now();
    while (offset < bytes.length) {
      if (isCancelled()) throw const TransferCancelledException();
      if (!isChannelOpen()) throw const TransferStalledException();

      // ລໍຖ້າໃຫ້ Buffer ຫຼຸດລົງກ່ອນ (ປ້ອງກັນ browser/ອຸປະກອນຄ້າງ).
      while (bufferedAmount() > AppConfig.maxBufferedAmount) {
        if (!isChannelOpen()) throw const TransferStalledException();
        if (DateTime.now().difference(lastDrain) >=
            const Duration(seconds: AppConfig.transferStallTimeoutSeconds)) {
          throw const TransferStalledException();
        }
        await Future<void>.delayed(
          const Duration(milliseconds: AppConfig.backpressurePollMs),
        );
        if (isCancelled()) throw const TransferCancelledException();
      }
      lastDrain = DateTime.now();

      final end = (offset + chunkSize).clamp(0, bytes.length);
      await sendChunk(Uint8List.sublistView(bytes, offset, end));
      offset = end;
      onProgress(offset);
    }
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// ເກັບຕ່ອນໄຟລ໌ທີ່ຮັບເຂົ້າມາ ຈົນຄົບ ແລ້ວກວດສອບ SHA-256.
class IncomingFile {
  IncomingFile({
    required this.id,
    required this.fileName,
    required this.fileSize,
    this.expectedSha256,
    this.sink,
    Duration stallTimeout = const Duration(
      seconds: AppConfig.transferStallTimeoutSeconds,
    ),
    void Function()? onStalled,
  }) : _stopwatch = Stopwatch()..start(),
       _stallTimeout = stallTimeout,
       _onStalled = onStalled {
    _resetStallTimer();
  }

  final String id;
  final String fileName;
  final int fileSize;
  final String? expectedSha256;
  final IncomingFileSink? sink;

  final BytesBuilder _builder = BytesBuilder(copy: false);
  final _DigestSink _digestResult = _DigestSink();
  late final ByteConversionSink _hashSink = sha256.startChunkedConversion(
    _digestResult,
  );
  final Stopwatch _stopwatch;
  final Duration _stallTimeout;
  final void Function()? _onStalled;
  Timer? _stallTimer;
  int received = 0;
  double bytesPerSecond = 0;
  Uint8List? _finalBytes;
  bool _hashClosed = false;

  double get progress =>
      fileSize <= 0 ? 0 : (received / fileSize).clamp(0.0, 1.0);

  void addChunk(Uint8List chunk) {
    _resetStallTimer();
    _hashSink.add(chunk);
    if (sink == null) _builder.add(chunk);
    _updateProgress(chunk.length);
  }

  Future<void> writeChunk(Uint8List chunk) async {
    if (sink == null) {
      addChunk(chunk);
      return;
    }
    _resetStallTimer();
    _hashSink.add(chunk);
    await sink!.write(chunk);
    _updateProgress(chunk.length);
  }

  void _updateProgress(int length) {
    received += length;
    final seconds = _stopwatch.elapsedMilliseconds / 1000.0;
    if (seconds > 0.15) bytesPerSecond = received / seconds;
  }

  void _resetStallTimer() {
    _stallTimer?.cancel();
    if (_onStalled != null) {
      _stallTimer = Timer(_stallTimeout, _onStalled);
    }
  }

  void dispose() {
    _stallTimer?.cancel();
    _stallTimer = null;
  }

  /// ດຶງ bytes ອອກຄັ້ງດຽວ (idempotent).
  Uint8List takeBytes() => _finalBytes ??= _builder.takeBytes();

  Future<bool> verify() async {
    return verifyWith(expectedSha256);
  }

  Future<bool> verifyWith(String? expectedSha256) async {
    if (!_hashClosed) {
      _hashSink.close();
      _hashClosed = true;
    }
    if (received != fileSize ||
        expectedSha256 == null ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedSha256)) {
      return false;
    }
    if (sink == null) {
      return sha256.convert(takeBytes()).toString() == expectedSha256;
    }
    return _digestResult.value?.toString() == expectedSha256;
  }
}
