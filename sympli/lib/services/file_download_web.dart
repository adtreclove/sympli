import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Triggers a browser download of [content] as [fileName].
/// Works on desktop and mobile browsers (incl. iOS Safari 13+).
Future<bool> downloadFile({
  required String fileName,
  required String content,
  required String mimeType,
}) async {
  final blob = web.Blob(
    <JSAny>[content.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);

  // A hidden <a download> element is the most compatible way to start a
  // download from a blob URL.
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName;
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();

  // Revoke later – some browsers (Safari) still read the blob after click().
  Future<void>.delayed(
    const Duration(seconds: 30),
    () => web.URL.revokeObjectURL(url),
  );
  return true;
}
