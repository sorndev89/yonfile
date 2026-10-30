import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yonfile_client/core/constants/app_config.dart';
import 'package:yonfile_client/services/file_chunker_service.dart';
import 'package:yonfile_client/services/file_stream_helper.dart';
import 'package:yonfile_client/services/incoming_file_sink.dart';

/// Mock XFile ສຳລັບຈຳລອງໄຟລ໌ 5 GB ໂດຍບໍ່ຕ້ອງຈອງ RAM 5 GB ແທ້
class _MockHuge5GbFile {
  _MockHuge5GbFile(this.totalSize);

  final int totalSize;
  int openReadCallCount = 0;
  int lastRequestedEnd = 0;

  Stream<Uint8List> openRead([int? start, int? end]) async* {
    openReadCallCount++;
    final s = start ?? 0;
    final e = end ?? totalSize;
    lastRequestedEnd = e;
    // ສົ່ງ bytes ຂະໜາດນ້ອຍເພື່ອທົດສອບ range logic ໂດຍບໍ່ໃຫ້ RAM ເຕັມ
    yield Uint8List(4);
  }
}

/// Mock Sink ສຳລັບຮັບ stream 5 GB ໂດຍການນັບ bytes ທີ່ຂຽນ
class _MockCountingSink implements IncomingFileSink {
  int totalBytesWritten = 0;
  int writeCount = 0;
  bool isFlushed = false;
  bool isFinished = false;
  bool isAborted = false;

  @override
  Future<void> write(List<int> bytes) async {
    totalBytesWritten += bytes.length;
    writeCount++;
  }

  @override
  Future<void> flush() async {
    isFlushed = true;
  }

  @override
  Future<void> finish() async {
    isFinished = true;
  }

  @override
  Future<void> abort() async {
    isAborted = true;
  }
}

void main() {
  const int size5Gb = 5 * 1024 * 1024 * 1024; // 5,368,709,120 bytes
  final chunker = FileChunkerService();

  group('5GB File Transfer Unit Tests', () {
    test('5GB file is within AppConfig.maxFileSizeBytes limit (10GB)', () {
      expect(size5Gb, lessThanOrEqualTo(AppConfig.maxFileSizeBytes));
      expect(AppConfig.maxFileSizeBytes, 10 * 1024 * 1024 * 1024);
      expect(AppConfig.maxFileSizeLabel, '10 GB');
    });

    test(
      'FileStreamHelper slices 5GB file into exactly 5,120 slices of 1MB on Web',
      () async {
        final mockFile = _MockHuge5GbFile(size5Gb);
        const int sliceSize = 1024 * 1024; // 1 MB
        const int expectedSlices = 5 * 1024; // 5,120 slices

        var sliceIndex = 0;
        final stream = FileStreamHelper.streamFile(
          mockFile,
          size5Gb,
          sliceSize: sliceSize,
          isWeb: true,
        );

        await for (final _ in stream) {
          sliceIndex++;
        }

        expect(sliceIndex, expectedSlices);
        expect(mockFile.openReadCallCount, expectedSlices);
        expect(mockFile.lastRequestedEnd, size5Gb);
      },
    );

    test(
      'FileChunkerService streams 5GB chunks with backpressure and progress tracking',
      () async {
        // ຈຳລອງ stream ທີ່ສົ່ງ chunk ຂະໜາດ 64KB
        const int chunkSize = AppConfig.chunkSize; // 64 KB
        const int numberOfChunks = 500; // ຈຳລອງ 500 chunks ເພື່ອ run test ໄວ
        const int simulatedSize = numberOfChunks * chunkSize;

        final dummyChunk = Uint8List(chunkSize);
        Stream<Uint8List> generateChunks() async* {
          for (var i = 0; i < numberOfChunks; i++) {
            yield dummyChunk;
          }
        }

        var totalSent = 0;
        var progressCallCount = 0;
        var backpressureCheckCount = 0;
        var simulatedBuffer = 0;

        final digest = await chunker.sendStream(
          stream: generateChunks(),
          expectedSize: simulatedSize,
          sendChunk: (chunk) async {
            totalSent += chunk.length;
            simulatedBuffer += chunk.length;
          },
          bufferedAmount: () {
            backpressureCheckCount++;
            // ຈຳລອງການລະບາຍ buffer
            if (simulatedBuffer > 0) simulatedBuffer = 0;
            return simulatedBuffer;
          },
          onProgress: (sent) {
            progressCallCount++;
            expect(sent, lessThanOrEqualTo(simulatedSize));
          },
          isCancelled: () => false,
          isChannelOpen: () => true,
        );

        expect(totalSent, simulatedSize);
        expect(progressCallCount, numberOfChunks);
        expect(backpressureCheckCount, greaterThan(0));
        expect(digest.length, 64); // SHA-256 64-char hex
      },
    );

    test('IncomingFile handles 5GB stream directly into sink without memory accumulation', () async {
      final sink = _MockCountingSink();
      final incoming = IncomingFile(
        id: 'transfer-5gb-test',
        fileName: 'huge_archive.zip',
        fileSize: size5Gb,
        sink: sink,
      );

      // ຈຳລອງການຮັບ chunk ເຂົ້າ sink
      const int testChunkSize = 64 * 1024; // 64 KB per chunk
      const int chunkCount = 100;
      final testData = Uint8List(testChunkSize);

      for (var i = 0; i < chunkCount; i++) {
        await incoming.writeChunk(testData);
      }

      // ກວດສອບວ່າ sink ໄດ້ຮັບຂໍ້ມູນຖືກຕ້ອງ
      expect(sink.totalBytesWritten, chunkCount * testChunkSize);
      expect(sink.writeCount, chunkCount);
      expect(incoming.received, chunkCount * testChunkSize);

      // ສຳຄັນ: ເມື່ອມີ sink, incoming.takeBytes() ຈະບໍ່ເກັບ bytes ໄວ້ໃນ RAM
      expect(incoming.takeBytes(), isEmpty);

      // ທົດສອບການ finish
      await sink.finish();
      expect(sink.isFinished, isTrue);

      incoming.dispose();
    });

    test('verifies progress calculation for a 5GB transfer', () {
      final incoming = IncomingFile(
        id: 'progress-5gb',
        fileName: 'backup_5gb.iso',
        fileSize: size5Gb,
      );

      expect(incoming.progress, 0.0);

      // ຮັບໄປແລ້ວ 2.5 GB (50%)
      incoming.received = (2.5 * 1024 * 1024 * 1024).toInt();
      expect(incoming.progress, closeTo(0.5, 0.001));

      // ຮັບຄົບ 5 GB (100%)
      incoming.received = size5Gb;
      expect(incoming.progress, 1.0);

      incoming.dispose();
    });
  });
}
