// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
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
  final input = html.FileUploadInputElement()
    ..accept = 'image/*'
    ..style.display = 'none';
  if (source == ImageSource.camera) {
    input.setAttribute('capture', 'environment');
  }

  final completer = Completer<PickedImageFile?>();
  html.document.body?.append(input);

  input.onChange.first.then((_) {
    final file = input.files?.isNotEmpty == true ? input.files!.first : null;
    if (file == null) {
      if (!completer.isCompleted) completer.complete(null);
      input.remove();
      return;
    }

    final reader = html.FileReader();
    reader.onError.first.then((_) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('No pudimos leer el archivo seleccionado.'),
        );
      }
      input.remove();
    });
    reader.onLoadEnd.first.then((_) {
      final result = reader.result;
      if (result is ByteBuffer) {
        if (!completer.isCompleted) {
          completer.complete(
            PickedImageFile(
              name: file.name,
              bytes: Uint8List.view(result),
            ),
          );
        }
      } else if (result is Uint8List) {
        if (!completer.isCompleted) {
          completer.complete(PickedImageFile(name: file.name, bytes: result));
        }
      } else if (!completer.isCompleted) {
        completer.completeError(
          StateError('No pudimos leer el archivo seleccionado.'),
        );
      }
      input.remove();
    });
    reader.readAsArrayBuffer(file);
  });

  input.click();

  html.window.onFocus.first.then((_) async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!completer.isCompleted && (input.files?.isEmpty ?? true)) {
      completer.complete(null);
      input.remove();
    }
  });

  return completer.future;
}
