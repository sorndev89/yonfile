import 'package:flutter_test/flutter_test.dart';
import 'package:yonfile_client/services/file_chunker_service.dart';
import 'package:yonfile_client/core/constants/app_config.dart';
import 'dart:typed_data';

void main() {
  group('FileChunkerService.sendFile', () {
    test('sends all chunks and reports progress', () async {
      final service = FileChunkerService();
      const fileSize = 256 * 1024; // 256 KB
      final data = Uint8List(fileSize);
      final sentChunks = <Uint8List>[];
      final progress = <int>[];

      await service.sendFile(
        bytes: data,
        sendChunk: (chunk) async {
          sentChunks.add(chunk);
        },
        bufferedAmount: () => 0,
        onProgress: (sent) => progress.add(sent),
        isCancelled: () => false,
        isChannelOpen: () => true,
      );

      // Expect 4 chunks (64 KB each)
      expect(sentChunks.length, 4);
      final totalSent = sentChunks.fold<int>(0, (sum, c) => sum + c.length);
      expect(totalSent, fileSize);
      // Progress values should accumulate by chunkSize
      expect(progress, [
        AppConfig.chunkSize,
        AppConfig.chunkSize * 2,
        AppConfig.chunkSize * 3,
        fileSize,
      ]);
    });

    test('respects back‑pressure and still completes', () async {
      final service = FileChunkerService();
      const fileSize = 128 * 1024; // 128 KB => 2 chunks
      final data = Uint8List(fileSize);
      final sentChunks = <Uint8List>[];
      final progress = <int>[];

      // Simulate bufferedAmount that is high for the first two checks, then low.
      int callCount = 0;
      int bufferedAmount() {
        callCount++;
        return callCount <= 2 ? AppConfig.maxBufferedAmount + 1 : 0;
      }

      await service.sendFile(
        bytes: data,
        sendChunk: (chunk) async {
          sentChunks.add(chunk);
        },
        bufferedAmount: bufferedAmount,
        onProgress: (sent) => progress.add(sent),
        isCancelled: () => false,
        isChannelOpen: () => true,
      );

      expect(sentChunks.length, 2);
      // Final progress must equal total size
      expect(progress.last, fileSize);
    });
  });
}

