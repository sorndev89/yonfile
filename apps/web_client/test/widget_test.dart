import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yonfile_client/core/constants/app_config.dart';
import 'package:yonfile_client/services/file_chunker_service.dart';

void main() {
  final chunker = FileChunkerService();

  group('FileChunkerService', () {
    test('chunk size is 16KB for broad RTC data channel compatibility', () {
      expect(AppConfig.chunkSize, 16 * 1024);
    });

    test('sha256Of returns 64-char hex digest', () {
      final digest = chunker.sha256Of(Uint8List.fromList([1, 2, 3, 4]));
      expect(digest.length, 64);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(digest), isTrue);
    });

    test('chunks split and reassemble correctly', () {
      final data = Uint8List.fromList(
        List<int>.generate(AppConfig.chunkSize + 123, (i) => i % 251),
      );
      final pieces = chunker.chunks(data).toList();
      expect(pieces.length, 2);
      expect(pieces.first.length, AppConfig.chunkSize);
      expect(pieces.last.length, 123);

      final rebuilt = BytesBuilder();
      for (final piece in pieces) {
        rebuilt.add(piece);
      }
      expect(rebuilt.toBytes(), equals(data));
    });

    test('stops immediately when the data channel is closed', () async {
      await expectLater(
        chunker.sendFile(
          bytes: Uint8List.fromList([1]),
          sendChunk: (_) async {},
          bufferedAmount: () => 0,
          onProgress: (_) {},
          isCancelled: () => false,
          isChannelOpen: () => false,
        ),
        throwsA(isA<TransferStalledException>()),
      );
    });
  });

  group('IncomingFile', () {
    test('verifies matching sha256 and keeps bytes', () async {
      final data = Uint8List.fromList(List<int>.generate(1000, (i) => i % 256));
      final sha = chunker.sha256Of(data);

      final incoming = IncomingFile(
        id: 't1',
        fileName: 'a.bin',
        fileSize: data.length,
        expectedSha256: sha,
      );
      for (final piece in chunker.chunks(data)) {
        incoming.addChunk(piece);
      }

      expect(await incoming.verify(), isTrue);
      expect(incoming.takeBytes(), equals(data));
    });

    test('fails on mismatched sha256', () async {
      final data = Uint8List.fromList([1, 2, 3]);
      final incoming = IncomingFile(
        id: 't2',
        fileName: 'b.bin',
        fileSize: data.length,
        expectedSha256: 'deadbeef',
      );
      incoming.addChunk(data);
      expect(await incoming.verify(), isFalse);
    });

    test('rejects bytes when received size differs from the offer', () async {
      final data = Uint8List.fromList([1, 2, 3]);
      final incoming = IncomingFile(
        id: 't3',
        fileName: 'short.bin',
        fileSize: data.length + 1,
        expectedSha256: chunker.sha256Of(data),
      );
      incoming.addChunk(data);
      expect(await incoming.verify(), isFalse);
    });
  });
}
