import 'incoming_file_sink.dart';

Future<IncomingFileSink> createIncomingFileSink(String fileName) =>
    throw UnsupportedError('Receiving files is not supported on this platform');

Future<IncomingBatchSinkFactory?> createIncomingBatchSinkFactory() async =>
    null;
