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

/// ສ້າງ sink ສຳລັບໄຟລ໌ໃນ batch ດ້ວຍການເລືອກປາຍທາງພຽງຄັ້ງດຽວ.
abstract interface class IncomingBatchSinkFactory {
  Future<IncomingFileSink> create(String fileName);

  Future<void> dispose();
}

Future<IncomingFileSink> createIncomingFileSink(String fileName) =>
    impl.createIncomingFileSink(fileName);

Future<IncomingBatchSinkFactory?> createIncomingBatchSinkFactory() =>
    impl.createIncomingBatchSinkFactory();
