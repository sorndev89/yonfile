import 'incoming_file_sink_stub.dart'
    if (dart.library.io) 'incoming_file_sink_io.dart'
    if (dart.library.js_interop) 'incoming_file_sink_web.dart'
    as impl;

abstract interface class IncomingFileSink {
  Future<void> write(List<int> bytes);
  Future<void> flush();
  Future<void> finish();
  Future<void> abort();
}

Future<IncomingFileSink> createIncomingFileSink(String fileName) =>
    impl.createIncomingFileSink(fileName);
