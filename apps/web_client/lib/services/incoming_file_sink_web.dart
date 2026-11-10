import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'app_log_service.dart';
import 'incoming_file_sink.dart';

bool _supportsShowSaveFilePicker() {
  try {
    final win = web.window as JSObject;
    return win.has('showSaveFilePicker');
  } catch (_) {
    return false;
  }
}

bool _supportsShowDirectoryPicker() {
  try {
    final win = web.window as JSObject;
    return win.has('showDirectoryPicker');
  } catch (_) {
    return false;
  }
}

Future<IncomingFileSink> createIncomingFileSink(String fileName) async {
  if (_supportsShowSaveFilePicker()) {
    try {
      final win = web.window as JSObject;
      final options = _SavePickerOptions(suggestedName: fileName);
      final promise = win.callMethod<JSPromise<web.FileSystemFileHandle>>(
        'showSaveFilePicker'.toJS,
        options,
      );
      final handle = await promise.toDart;
      final writer = await handle.createWritable().toDart;
      AppLogService.instance.info(
        'ໃຊ້ FileSystem Access API (SaveFilePicker) ສຳລັບ $fileName',
        tag: 'Storage',
      );
      return _WebIncomingFileSink(writer);
    } catch (e) {
      // If user cancelled save picker, rethrow so offer is rejected as intended
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('aborterror') || errStr.contains('user cancelled')) {
        AppLogService.instance.warn(
          'ຜູ້ໃຊ້ຍົກເລີກການເລືອກບ່ອນບັນທຶກ: $fileName',
          tag: 'Storage',
        );
        rethrow;
      }
      AppLogService.instance.warn(
        'ບໍ່ສາມາດເປີດ showSaveFilePicker, ປ່ຽນໄປໃຊ້ in-memory Blob ($e)',
        tag: 'Storage',
      );
      // Otherwise fall back to in-memory Blob
    }
  } else {
    AppLogService.instance.info(
      'Browser ບໍ່ຮອງຮັບ showSaveFilePicker, ໃຊ້ in-memory Blob ສຳລັບ $fileName',
      tag: 'Storage',
    );
  }
  return _BlobIncomingFileSink(fileName);
}

/// ເລືອກໂຟນເດີປາຍທາງພຽງຄັ້ງດຽວ ແລ້ວຂຽນທຸກໄຟລ໌ໃນ batch ລົງໂຟນເດີນັ້ນ.
/// ຕ້ອງເອີ້ນພາຍໃນ user gesture (ປຸ່ມ Accept).
Future<IncomingBatchSinkFactory?> createIncomingBatchSinkFactory() async {
  if (!_supportsShowDirectoryPicker()) return _BlobBatchSinkFactory();
  try {
    final win = web.window as JSObject;
    final promise = win.callMethod<JSPromise<web.FileSystemDirectoryHandle>>(
      'showDirectoryPicker'.toJS,
    );
    final handle = await promise.toDart;
    return _DirectoryBatchSinkFactory(handle);
  } catch (e) {
    final errStr = e.toString().toLowerCase();
    if (errStr.contains('aborterror') || errStr.contains('user cancelled')) {
      rethrow;
    }
    return _BlobBatchSinkFactory();
  }
}

@JS()
extension type _SavePickerOptions._(JSObject _) implements JSObject {
  external factory _SavePickerOptions({String suggestedName});
}

class _DirectoryBatchSinkFactory implements IncomingBatchSinkFactory {
  _DirectoryBatchSinkFactory(this._directory);

  final web.FileSystemDirectoryHandle _directory;
  final Set<String> _usedNames = {};

  @override
  Future<IncomingFileSink> create(String fileName) async {
    final name = _uniqueName(fileName);
    final handle = await _directory
        .getFileHandle(name, web.FileSystemGetFileOptions(create: true))
        .toDart;
    final writer = await handle.createWritable().toDart;
    return _WebIncomingFileSink(writer);
  }

  String _uniqueName(String rawName) {
    final sanitized = rawName
        .replaceAll(RegExp(r'[\\/\u0000-\u001f]'), '_')
        .trim();
    final base = sanitized.isEmpty ? 'file' : sanitized;
    var candidate = base;
    var index = 1;
    while (_usedNames.contains(candidate.toLowerCase())) {
      final dot = base.lastIndexOf('.');
      final stem = dot > 0 ? base.substring(0, dot) : base;
      final extension = dot > 0 ? base.substring(dot) : '';
      candidate = '$stem ($index)$extension';
      index++;
    }
    _usedNames.add(candidate.toLowerCase());
    return candidate;
  }

  @override
  Future<void> dispose() async {}
}

/// ສຳລັບ browser ທີ່ບໍ່ຮອງຮັບ directory picker: ດາວໂຫຼດແຕ່ລະໄຟລ໌ອັດຕະໂນມັດ.
class _BlobBatchSinkFactory implements IncomingBatchSinkFactory {
  @override
  Future<IncomingFileSink> create(String fileName) async =>
      _BlobIncomingFileSink(fileName);

  @override
  Future<void> dispose() async {}
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
      AppLogService.instance.error(
        'ໄຟລ໌ໃຫຍ່ເກີນຂີດຈຳກັດ memory ($fileName): ${( _totalBytes / (1024*1024) ).toStringAsFixed(0)} MB > 1.5 GB',
        tag: 'Storage',
      );
      throw StateError(
        'Browser ບໍ່ຮອງຮັບ stream ລົງ disk (ຫຼືບໍ່ໄດ້ໃຊ້ HTTPS) ແລະໄຟລ໌ໃຫຍ່ເກີນຂີດຈຳກັດ memory (1.5 GB). ກະລຸນາໃຊ້ Chrome/Edge ຜ່ານ HTTPS ຫຼື ໃຊ້ YonFile App ແທນ.',
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
