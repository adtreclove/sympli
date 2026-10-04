/// Fallback for non-web platforms: downloading is not supported there yet.
/// Returns `false` so the caller can inform the user.
Future<bool> downloadFile({
  required String fileName,
  required String content,
  required String mimeType,
}) async => false;
