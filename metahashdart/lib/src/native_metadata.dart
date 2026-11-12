import 'dart:io';

import 'metadata.dart';
import 'path.dart';
import 'posix_metadata.dart';
import 'windows_metadata.dart';

PathStyle get hostPathStyle =>
    Platform.isWindows ? PathStyle.windows : PathStyle.posix;

(MetaPath, Cha) readMetadata(MetaPath path, {required bool canonicalize}) {
  if (path.style != hostPathStyle) {
    throw ArgumentError('File path style must match the host OS');
  }
  if (path.isEmpty || path.bytes.contains(0)) {
    throw ArgumentError('File path must be nonempty and cannot contain NUL');
  }
  if (Platform.isWindows)
    return readWindowsMetadata(path, canonicalize: canonicalize);
  if (Platform.isLinux || Platform.isMacOS)
    return readPosixMetadata(path, canonicalize: canonicalize);
  throw UnsupportedError(
    'File metadata is unavailable on ${Platform.operatingSystem}',
  );
}
