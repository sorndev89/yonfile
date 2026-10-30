import 'package:flutter/foundation.dart';

/// Helper ສຳລັບຈັດການ stream ໄຟລ໌ໃຫ້ປອດໄພ
/// ໂດຍສະເພາະເທິງ Web ເພື່ອປ້ອງກັນບັນຫາ V8 2GB ArrayBuffer allocation limit.
class FileStreamHelper {
  FileStreamHelper._();

  /// ຂະໜາດ Slice 1 MB ເທິງ Web ເພື່ອບໍ່ໃຫ້ກິນ Memory ແລະ ບໍ່ຕິດ ArrayBuffer limit.
  static const int defaultSliceSize = 1024 * 1024;

  /// Stream ໄຟລ໌ໂດຍການຕັດເປັນ slice ຍ່ອຍໆ ເທິງ Web (ຫຼື stream ປົກກະຕິເທິງ Mobile/Desktop).
  static Stream<List<int>> streamFile(
    dynamic file,
    int fileSize, {
    int sliceSize = defaultSliceSize,
    bool isWeb = kIsWeb,
  }) async* {
    if (fileSize <= 0) return;
    if (isWeb) {
      var offset = 0;
      while (offset < fileSize) {
        final end = (offset + sliceSize).clamp(0, fileSize);
        yield* (file.openRead(offset, end) as Stream<List<int>>);
        offset = end;
      }
    } else {
      yield* (file.openRead() as Stream<List<int>>);
    }
  }
}
