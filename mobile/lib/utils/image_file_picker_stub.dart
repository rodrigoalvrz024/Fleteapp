import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

class PickedImageFile {
  final String name;
  final Uint8List bytes;

  const PickedImageFile({
    required this.name,
    required this.bytes,
  });
}

Future<PickedImageFile?> pickImageFile(ImageSource source) async {
  final file = await ImagePicker().pickImage(
    source: source,
    imageQuality: 78,
    maxWidth: 1800,
    requestFullMetadata: false,
  );
  if (file == null) return null;

  return PickedImageFile(
    name: file.name,
    bytes: await file.readAsBytes(),
  );
}
