/// Platform-agnostic file download.
///
/// On the web the file is handed to the browser as a regular download.
/// On other platforms [downloadFile] returns `false` (not supported yet).
library;

export 'file_download_stub.dart'
    if (dart.library.js_interop) 'file_download_web.dart';
