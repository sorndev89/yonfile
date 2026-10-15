// ignore_for_file: deprecated_member_use

import 'package:file_picker/file_picker.dart';
import 'package:file_picker_web/file_picker_web.dart';

// The file_picker web implementation still exposes `withData` as a
// deprecated switch; false is needed to keep large browser selections lazy.
WebOptions get lazyFilePickerOptions =>
    const FilePickerWebOptions(withData: false);
