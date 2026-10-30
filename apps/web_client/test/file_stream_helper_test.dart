import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yonfile_client/services/file_stream_helper.dart';

class _FakeSliceableFile {
  _FakeSliceableFile(this.bytes);

  final Uint8List bytes;
  final List<List<int>> requestedRanges = [];

  Stream<Uint8List> openRead([int? start, int? end]) async* {
    final s = start ?? 0;
    final e = end ?? bytes.length;
    requestedRanges.add([s, e]);
    yield Uint8List.sublistView(bytes, s, e);
  }
}

void main() {
  group('FileStreamHelper', () {
    test('web streaming slices file into configured sliceSize chunks', () async {
      // 2.5 MB data with a smaller 1 MB slice
      final totalSize = (2.5 * 1024 * 1024).toInt();
      final data = Uint8List.fromList(
        List<int>.generate(totalSize, (i) => i % 251),
      );
      final file = _FakeSliceableFile(data);

      const sliceSize = 1024 * 1024; // 1 MB
      final chunks = await FileStreamHelper.streamFile(
        file,
        totalSize,
        sliceSize: sliceSize,
        isWeb: true,
      ).toList();

      // Should be 3 slices: 1MB, 1MB, 0.5MB
      expect(chunks.length, 3);
      expect(chunks[0].length, 1024 * 1024);
      expect(chunks[1].length, 1024 * 1024);
      expect(chunks[2].length, 512 * 1024);

      // Verify the requested ranges passed to openRead
      expect(file.requestedRanges, [
        [0, 1024 * 1024],
        [1024 * 1024, 2048 * 1024],
        [2048 * 1024, totalSize],
      ]);

      // Reassemble and verify data and SHA-256 integrity
      final reassembled = Uint8List.fromList(
        chunks.expand((c) => c).toList(),
      );
      expect(reassembled, equals(data));
      expect(
        sha256.convert(reassembled).toString(),
        sha256.convert(data).toString(),
      );
    });

    test('web streaming handles file smaller than one sliceSize', () async {
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final file = _FakeSliceableFile(data);

      final chunks = await FileStreamHelper.streamFile(
        file,
        data.length,
        sliceSize: 1024 * 1024,
        isWeb: true,
      ).toList();

      expect(chunks.length, 1);
      expect(chunks.first, equals(data));
      expect(file.requestedRanges, [
        [0, 5],
      ]);
    });

    test('web streaming handles empty file gracefully', () async {
      final file = _FakeSliceableFile(Uint8List(0));

      final chunks = await FileStreamHelper.streamFile(
        file,
        0,
        isWeb: true,
      ).toList();

      expect(chunks, isEmpty);
      expect(file.requestedRanges, isEmpty);
    });

    test('non-web streaming calls openRead without slice offsets', () async {
      final data = Uint8List.fromList([10, 20, 30, 40]);
      final file = _FakeSliceableFile(data);

      final chunks = await FileStreamHelper.streamFile(
        file,
        data.length,
        isWeb: false,
      ).toList();

      expect(chunks.length, 1);
      expect(chunks.first, equals(data));
      // Without arguments, openRead defaults to start=0, end=length
      expect(file.requestedRanges, [
        [0, 4],
      ]);
    });

    test('simulates streaming 2GB+ file logic without large memory allocation', () async {
      // Simulate a 2.5 GB file size with 1 MB slices (2560 slices)
      const simulatedSize = 2560 * 1024 * 1024;
      const sliceSize = 1024 * 1024;

      var openReadCalls = 0;
      var lastOffset = 0;

      Stream<List<int>> fakeHugeStreamFile(dynamic f, int size) async* {
        yield* FileStreamHelper.streamFile(
          f,
          size,
          sliceSize: sliceSize,
          isWeb: true,
        );
      }

      final fakeHugeFile = _FakeLazyFile((start, end) {
        openReadCalls++;
        expect(start, lastOffset);
        expect(end, (start + sliceSize).clamp(0, simulatedSize));
        lastOffset = end;
        // Return dummy 4 bytes per slice to keep test memory tiny
        return Stream.value(Uint8List.fromList([1, 2, 3, 4]));
      });

      var receivedEvents = 0;
      await for (final _ in fakeHugeStreamFile(fakeHugeFile, simulatedSize)) {
        receivedEvents++;
      }

      expect(openReadCalls, 2560);
      expect(receivedEvents, 2560);
      expect(lastOffset, simulatedSize);
    });
  });
}

class _FakeLazyFile {
  _FakeLazyFile(this.onOpenRead);

  final Stream<List<int>> Function(int start, int end) onOpenRead;

  Stream<List<int>> openRead([int? start, int? end]) =>
      onOpenRead(start ?? 0, end ?? 0);
}
