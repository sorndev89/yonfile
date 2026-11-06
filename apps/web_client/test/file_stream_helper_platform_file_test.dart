import 'dart:typed_data';

// ignore: depend_on_referenced_packages
import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yonfile_client/services/file_stream_helper.dart';

/// Mimics the PlatformFile returned by file_picker 12+, which exposes
/// `readAsByteStream()` but no longer `openRead()`.
final class _FakePlatformFile extends PlatformFile {
  _FakePlatformFile(this._chunks);

  final List<Uint8List> _chunks;
  int streamCallCount = 0;

  @override
  String get name => 'picked.bin';

  @override
  Uri get uri => Uri.parse('blob:fake');

  @override
  XFile get xFile => throw UnimplementedError('xFile should not be used');

  @override
  int? lengthSync() =>
      _chunks.fold<int>(0, (total, chunk) => total + chunk.length);

  @override
  Future<int?> length() async => lengthSync();

  @override
  Future<Uint8List> readAsBytes() async =>
      Uint8List.fromList(_chunks.expand((chunk) => chunk).toList());

  @override
  Stream<Uint8List> readAsByteStream() async* {
    streamCallCount++;
    for (final chunk in _chunks) {
      yield chunk;
    }
  }
}

void main() {
  test('PlatformFile is streamed with readAsByteStream', () async {
    final data = Uint8List.fromList(List<int>.generate(300000, (i) => i % 251));
    final file = _FakePlatformFile([
      Uint8List.sublistView(data, 0, 150000),
      Uint8List.sublistView(data, 150000),
    ]);

    final chunks = await FileStreamHelper.streamFile(file, data.length).toList();

    expect(file.streamCallCount, 1);
    expect(chunks.expand((chunk) => chunk).toList(), equals(data));
  });
}
