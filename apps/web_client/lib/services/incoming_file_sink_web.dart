import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'incoming_file_sink.dart';

@JS('window.showSaveFilePicker')
external JSPromise<web.FileSystemFileHandle> _showSaveFilePicker(JSAny options);

Future<IncomingFileSink> createIncomingFileSink(String fileName) async {
  final options = _SavePickerOptions(suggestedName: fileName);
  final handle = await _showSaveFilePicker(options).toDart;
  final writer = await handle.createWritable().toDart;
  return _WebIncomingFileSink(writer);
}

@JS()
extension type _SavePickerOptions._(JSObject _) implements JSObject {
  external factory _SavePickerOptions({String suggestedName});
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
