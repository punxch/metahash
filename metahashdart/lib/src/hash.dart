import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'metadata.dart';
import 'native_metadata.dart';
import 'path.dart';
import 'url.dart';
import 'xxh3.dart';

/// The Rust target layout used to serialize Path, SystemTime and usize.
final class RustHashTarget {
  const RustHashTarget({
    required this.pathStyle,
    this.wordBytes = 8,
    this.endian = Endian.little,
  }) : assert(wordBytes == 4 || wordBytes == 8);

  static const windows64 = RustHashTarget(pathStyle: PathStyle.windows);
  static const unix64 = RustHashTarget(pathStyle: PathStyle.posix);
  static final host = RustHashTarget(
    pathStyle: hostPathStyle,
    wordBytes: sizeOf<IntPtr>(),
    endian: Endian.host,
  );

  final PathStyle pathStyle;
  final int wordBytes;
  final Endian endian;
}

/// A metahash URL paired with a file metadata snapshot.
final class MetaFile {
  const MetaFile(this.url, this.cha) : _target = null;
  const MetaFile._local(this.url, this.cha, this._target);

  /// Resolves a local path and reads its metadata with the host OS APIs.
  factory MetaFile.fromPath(String path) =>
      MetaFile.fromOsPath(MetaPath(path, style: hostPathStyle));

  /// Like [MetaFile.fromPath], with access to raw path bytes.
  factory MetaFile.fromOsPath(MetaPath path) {
    final (resolved, metadata) = readMetadata(path, canonicalize: true);
    return MetaFile._local(
      Url.regular(resolved),
      metadata,
      RustHashTarget.host,
    );
  }

  /// Reads metadata for a local URL, keeping the original URL in the hash.
  factory MetaFile.fromUrl(Url url) {
    final path = url.asPath;
    if (path == null)
      throw ArgumentError('URL cannot be converted to a local path');
    final (_, metadata) = readMetadata(path, canonicalize: false);
    return MetaFile._local(url, metadata, RustHashTarget.host);
  }

  final Url url;
  final Cha cha;
  final RustHashTarget? _target;

  /// Bytes written by Rust's File::hash followed by skip.hash.
  Uint8List hashInput({BigInt? skip, RustHashTarget? target}) {
    final path = url.loc.path;
    final layout = target ?? _target ?? RustHashTarget(pathStyle: path.style);
    if (layout.pathStyle != path.style) {
      throw ArgumentError('Hash target and path must use the same path style');
    }
    if (layout.wordBytes != 4 && layout.wordBytes != 8) {
      throw ArgumentError.value(
        layout.wordBytes,
        'wordBytes',
        'Expected 4 or 8',
      );
    }
    final skipValue = skip ?? BigInt.zero;
    if (skipValue.isNegative || skipValue.bitLength > layout.wordBytes * 8) {
      throw ArgumentError.value(
        skipValue,
        'skip',
        'Expected an unsigned Rust usize',
      );
    }

    final writer = _RustHashWriter(layout);
    writer.path(path);
    writer.word(BigInt.from(url.scheme.kind.index));
    final domain = url.scheme.domain;
    if (domain != null) {
      writer.bytes.add(utf8.encode(domain));
      writer.bytes.addByte(255); // Rust's str::hash terminator.
    }
    writer.integer(cha.len, 8);
    writer.time(cha.btime);
    writer.time(cha.ctime);
    writer.time(cha.mtime);
    writer.word(skipValue);
    return writer.bytes.takeBytes();
  }

  BigInt hash({BigInt? skip, RustHashTarget? target}) =>
      xxh3_128(hashInput(skip: skip, target: target));

  /// Rust's lowercase hexadecimal u128 display.
  String hashHex({BigInt? skip, RustHashTarget? target}) =>
      hash(skip: skip, target: target).toRadixString(16);
}

final _byteMask = BigInt.from(255);

final class _RustHashWriter {
  _RustHashWriter(this.target);

  final RustHashTarget target;
  final bytes = BytesBuilder(copy: false);

  void integer(BigInt value, int width) {
    final buffer = Uint8List(width);
    for (var i = 0; i < width; i++) {
      final index = target.endian == Endian.little ? i : width - i - 1;
      buffer[index] = (value & _byteMask).toInt();
      value >>= 8;
    }
    bytes.add(buffer);
  }

  void word(BigInt value) => integer(value, target.wordBytes);

  void time(MetaTimestamp? value) {
    word(value == null ? BigInt.zero : BigInt.one);
    if (value == null) return;
    if (target.pathStyle == PathStyle.windows) {
      integer(value.toWindowsFileTime(), 8);
    } else {
      integer(value.seconds, 8);
      integer(BigInt.from(value.nanoseconds), 4);
    }
  }

  void path(MetaPath path) {
    final prefix = path.windowsPrefix;
    if (prefix != null) {
      word(BigInt.from(prefix.kind.index));
      final drive = prefix.drive;
      if (drive != null) bytes.addByte(drive);
      for (final segment in [prefix.first, prefix.second]) {
        if (segment == null) continue;
        word(BigInt.from(segment.length));
        bytes.add(segment);
      }
    }

    final size = target.wordBytes * 8;
    final input = path.bytes;
    var chunkBits = BigInt.zero;
    var start = path.bodyStart;

    void addChunk(int end) {
      if (end <= start) return;
      final sum = (chunkBits + BigInt.from(end - start)).toUnsigned(size);
      chunkBits = ((sum >> 2) | (sum << (size - 2))).toUnsigned(size);
      bytes.add(Uint8List.sublistView(input, start, end));
    }

    // Path::hash concatenates components and mixes their byte lengths.
    // Root markers are omitted and a dot immediately after a separator is
    // skipped unless the Windows prefix is verbatim.
    for (var i = start; i < input.length; i++) {
      if (!path.isHashSeparator(input[i])) continue;
      addChunk(i);
      start = i + 1;
      if (!(prefix?.isVerbatim ?? false) &&
          start < input.length &&
          input[start] == 46 &&
          (start + 1 == input.length ||
              path.isHashSeparator(input[start + 1]))) {
        start++;
      }
    }
    addChunk(input.length);
    word(chunkBits);
  }
}
