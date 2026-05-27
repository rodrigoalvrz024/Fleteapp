import 'package:flutter/services.dart';

Future<void> downloadTextFile({
  required String filename,
  required String content,
  String mimeType = 'text/plain;charset=utf-8',
}) async {
  await Clipboard.setData(ClipboardData(text: content));
}
