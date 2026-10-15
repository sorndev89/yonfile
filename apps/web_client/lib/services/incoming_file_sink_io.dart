import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

import 'incoming_file_sink.dart';

const _channel = MethodChannel('la.yonfile/incoming_file');

Future<IncomingFileSink> createIncomingFileSink(String fileName) async {
  final dir = await Directory.systemTemp.createTemp('yonfile-receive-');
  final file = File('${dir.path}/$fileName');
  final output = file.openWrite();
  return _IoIncomingFileSink(dir, file, output);
}

class _IoIncomingFileSink implements IncomingFileSink {
  _IoIncomingFileSink(this.directory, this.file, this.output);

  final Directory directory;
  final File file;
  final IOSink output;
  bool _closed = false;

  @override
  Future<void> write(List<int> bytes) async {
    if (_closed) throw StateError('Incoming file is already closed');
    output.add(bytes);
  }

  @override
  Future<void> flush() async {
    if (!_closed) await output.flush();
  }

  @override
  Future<void> finish() async {
    if (_closed) return;
    await output.flush();
    await output.close();
    _closed = true;
    if (Platform.isAndroid || Platform.isIOS) {
      final saved = await _channel.invokeMethod<bool>('saveIncomingFile', {
        'path': file.path,
        'fileName': file.uri.pathSegments.last,
      });
      if (saved != true) throw StateError('Save was cancelled');
      if (saved == true && await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } else {
      final location = await getSaveLocation(
        suggestedName: file.uri.pathSegments.last,
      );
      if (location == null) throw StateError('Save was cancelled');
      await file.copy(location.path);
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  }

  @override
  Future<void> abort() async {
    if (!_closed) {
      await output.close();
      _closed = true;
    }
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
