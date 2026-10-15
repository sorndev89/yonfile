import 'dart:typed_data';

/// ໄຟລ໌ທີ່ຖືກເລືອກ ຫຼື ລາກມາວາງ ພ້ອມ bytes ສຳລັບສົ່ງ.
class PickedFile {
  final String name;
  final int size;
  final Uint8List? bytes;
  final Stream<List<int>>? readStream;
  final String mimeType;

  const PickedFile({
    required this.name,
    required this.size,
    this.bytes,
    this.readStream,
    this.mimeType = 'application/octet-stream',
  }) : assert(bytes != null || readStream != null);
}
