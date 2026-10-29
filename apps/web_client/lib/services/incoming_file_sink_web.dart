import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'incoming_file_sink.dart';

@JS('window.showSaveFilePicker')
external JSPromise<web.FileSystemFileHandle>? _showSaveFilePicker(JSAny options);

@JS('window')
external JSObject get _window;

bool _supportsShowSaveFilePicker() {
  try {
    return _window.has('showSaveFilePicker');
  } catch (_) {
    return false;
  }
}

Future<IncomingFileSink> createIncomingFileSink(String fileName) async {
  if (_supportsShowSaveFilePicker()) {
    try {
      final options = _SavePickerOptions(suggestedName: fileName);
      final promise = _showSaveFilePicker(options);
      if (promise != null) {
        final handle = await promise.toDart;
        final writer = await handle.createWritable().toDart;
        return _WebIncomingFileSink(writer);
      }
    } catch (e) {
      // If user cancelled save picker, rethrow so offer is rejected as intended
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('aborterror') || errStr.contains('user cancelled')) {
        rethrow;
      }
      // Otherwise fall back to in-memory Blob
    }
  }
  return _BlobIncomingFileSink(fileName);
}

@JS()
extension type _SavePickerOptions._(JSObject _) implements JSObject {
  external factory _SavePickerOptions({String suggestedName});
}

class _BlobIncomingFileSink implements IncomingFileSink {
  _BlobIncomingFileSink(this.fileName);
  final String fileName;
  final List<Uint8List> _chunks = [];
  int _totalBytes = 0;
  bool _closed = false;

  // 1.5 GB limit for in-memory buffer fallback to prevent tab crash
  static const int _maxInMemoryBytes = 1536 * 1024 * 1024;

  @override
  Future<void> write(List<int> bytes) async {
    if (_closed) throw StateError('Incoming file is already closed');
    final u8 = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    _totalBytes += u8.length;
    if (_totalBytes > _maxInMemoryBytes) {
      throw StateError(
        'Browser ບໍ່ຮອງຮັບ stream ລົງ disk ແລະໄຟລ໌ໃຫຍ່ເກີນຂີດຈຳກັດ memory (1.5 GB). ກະລຸນາໃຊ້ Chrome ຫຼື Edge.',
      );
    }
    _chunks.add(u8);
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> finish() async {
    if (_closed) return;
    _closed = true;
    final parts = _chunks.map((c) => c.toJS).toList().toJS;
    final blob = web.Blob(parts);
    final url = web.URL.createObjectURL(blob);
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
    anchor.href = url;
    anchor.download = fileName;
    anchor.style.display = 'none';
    web.document.body?.appendChild(anchor);
    anchor.click();
    anchor.remove();
    _chunks.clear();
    Future.delayed(const Duration(seconds: 10), () {
      web.URL.revokeObjectURL(url);
    });
  }

  @override
  Future<void> abort() async {
    _closed = true;
    _chunks.clear();
  }
}

class _WebIncomingFileSink implements IncomingFileSink {
  _WebIncomingFileSink(this.writer);
  final web.FileSystemWritableFileStream writer;
  bool _closed = false;

  @override
  Future<void> write(List<int> bytes) async {
    if (_closed) throw StateError('Incoming file is already closed');
    final data = (bytes is Uint8List ? bytes : Uint8List.fromList(bytes)).toJS;
    await writer.write(data).toDart;
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> finish() async {
    if (_closed) return;
    await writer.close().toDart;
    _closed = true;
  }

  @override
  Future<void> abort() async {
    if (_closed) return;
    await writer.abort().toDart;
    _closed = true;
  }
}
