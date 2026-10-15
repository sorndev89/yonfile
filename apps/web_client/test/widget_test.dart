import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yonfile_client/core/constants/app_config.dart';
import 'package:yonfile_client/services/file_chunker_service.dart';
import 'package:yonfile_client/services/incoming_file_sink.dart';

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

    test(
      'streams chunks, reports progress, and returns the stream digest',
      () async {
        final source = [
          List<int>.generate(AppConfig.chunkSize + 3, (i) => i % 251),
          [7, 8, 9],
        ];
        final sentChunks = <Uint8List>[];
        final progress = <int>[];
        final bytes = Uint8List.fromList(
          source.expand((part) => part).toList(),
        );

        final digest = await chunker.sendStream(
          stream: Stream.fromIterable(source),
          expectedSize: bytes.length,
          sendChunk: (chunk) async => sentChunks.add(Uint8List.fromList(chunk)),
          bufferedAmount: () => 0,
          onProgress: progress.add,
          isCancelled: () => false,
          isChannelOpen: () => true,
        );

        expect(sentChunks.map((chunk) => chunk.length), [
          AppConfig.chunkSize,
          3,
          3,
        ]);
        expect(progress, [
          AppConfig.chunkSize,
          AppConfig.chunkSize + 3,
          bytes.length,
        ]);
        expect(sentChunks.expand((chunk) => chunk).toList(), bytes);
        expect(digest, chunker.sha256Of(bytes));
      },
    );

    test('rejects a stream whose size changed after selection', () async {
      await expectLater(
        chunker.sendStream(
          stream: Stream.value([1, 2, 3]),
          expectedSize: 4,
          sendChunk: (_) async {},
          bufferedAmount: () => 0,
          onProgress: (_) {},
          isCancelled: () => false,
          isChannelOpen: () => true,
        ),
        throwsA(isA<StateError>()),
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

    test(
      'streams chunks into sink and verifies without assembling bytes',
      () async {
        final data = Uint8List.fromList(
          List<int>.generate(1024, (i) => i % 251),
        );
        final sink = _MemoryTestSink();
        final incoming = IncomingFile(
          id: 'streamed-file',
          fileName: 'streamed.bin',
          fileSize: data.length,
          sink: sink,
        );
        for (var offset = 0; offset < data.length; offset += 127) {
          final end = (offset + 127).clamp(0, data.length);
          await incoming.writeChunk(Uint8List.sublistView(data, offset, end));
        }

        expect(
          await incoming.verifyWith(sha256.convert(data).toString()),
          isTrue,
        );
        expect(incoming.received, data.length);
        expect(sink.writes.length, greaterThan(1));
        expect(sink.writes.expand((chunk) => chunk).toList(), data);
        expect(incoming.takeBytes(), isEmpty);
        incoming.dispose();
      },
    );
  });
}

class _MemoryTestSink implements IncomingFileSink {
  final List<List<int>> writes = [];

  @override
  Future<void> write(List<int> bytes) async => writes.add(List.of(bytes));

  @override
  Future<void> flush() async {}

  @override
  Future<void> finish() async {}

  @override
  Future<void> abort() async {}
}
