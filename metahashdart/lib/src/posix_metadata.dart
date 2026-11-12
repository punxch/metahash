import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'metadata.dart';
import 'native_memory.dart';
import 'path.dart';

final _libc = DynamicLibrary.process();
final _errnoLocation =
    _libc.lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
  Platform.isMacOS ? '__error' : '__errno_location',
  isLeaf: true,
);
final _realpath = _libc.lookupFunction<
    Pointer<Uint8> Function(Pointer<Uint8>, Pointer<Uint8>),
    Pointer<Uint8> Function(Pointer<Uint8>, Pointer<Uint8>)>('realpath');

typedef _StatNative = Int32 Function(Pointer<Uint8>, Pointer<Void>);
typedef _StatDart = int Function(Pointer<Uint8>, Pointer<Void>);

final _stat = _libc.lookupFunction<_StatNative, _StatDart>(
  Platform.isMacOS && _libc.providesSymbol(r'stat$INODE64')
      ? r'stat$INODE64'
      : Platform.isLinux && _libc.providesSymbol('stat64')
          ? 'stat64'
          : 'stat',
);

typedef _StatxNative = Int32 Function(
    Int32, Pointer<Uint8>, Int32, Uint32, Pointer<_Statx>);
typedef _StatxDart = int Function(
    int, Pointer<Uint8>, int, int, Pointer<_Statx>);

// Rust uses statx on Linux glibc targets when libc and the kernel provide it.
final _statx = _libc.providesSymbol('gnu_get_libc_version') &&
        _libc.providesSymbol('statx')
    ? _libc.lookupFunction<_StatxNative, _StatxDart>('statx')
    : null;

final class _StatxTime extends Struct {
  @Int64()
  external int seconds;
  @Uint32()
  external int nanos;
  @Int32()
  external int reserved;
}

// Linux UAPI struct statx. The remaining fields are unused but the kernel
// writes the full 256-byte struct.
final class _Statx extends Struct {
  @Uint32()
  external int mask;
  @Uint32()
  external int blockSize;
  @Uint64()
  external int attributes;
  @Uint32()
  external int links;
  @Uint32()
  external int uid;
  @Uint32()
  external int gid;
  @Uint16()
  external int mode;
  @Uint16()
  external int padding;
  @Uint64()
  external int inode;
  @Uint64()
  external int size;
  @Uint64()
  external int blocks;
  @Uint64()
  external int attributesMask;
  external _StatxTime accessed;
  external _StatxTime created;
  external _StatxTime changed;
  external _StatxTime modified;
  @Array(128)
  external Array<Uint8> remaining;
}

(MetaPath, Cha) readPosixMetadata(
  MetaPath input, {
  required bool canonicalize,
}) {
  final memory = NativeMemory(_libc);
  final errno = _errnoLocation;
  try {
    final path = canonicalize ? _canonicalize(memory, input, errno) : input;
    final filename = _nativePath(memory, path);
    final info =
        Platform.isLinux ? _readStatx(memory, filename, path, errno) : null;
    return (path, info ?? _readStat(memory, filename, path, errno));
  } finally {
    memory.close();
  }
}

Pointer<Uint8> _nativePath(NativeMemory memory, MetaPath path) {
  final buffer = memory.allocate<Uint8>(path.bytes.length + 1);
  buffer.asTypedList(path.bytes.length).setAll(0, path.bytes);
  return buffer;
}

MetaPath? _resolve(NativeMemory memory, MetaPath path) {
  final nativePath = _realpath(_nativePath(memory, path), nullptr);
  if (nativePath == nullptr) return null;
  memory.own(nativePath.cast());
  var length = 0;
  while (nativePath[length] != 0) {
    length++;
  }
  return MetaPath.fromBytes(nativePath.asTypedList(length));
}

MetaPath _canonicalize(
  NativeMemory memory,
  MetaPath input,
  Pointer<Int32> Function() errno,
) {
  final canonical = _resolve(memory, input);
  if (canonical != null) return canonical;
  final firstError = errno().value;
  const enoent = 2;
  const enotdir = 20;
  if (firstError == enoent || firstError == enotdir) {
    // soft-canonicalize retries lexically normalized paths after a failed realpath.
    final normalized = _normalize(input);
    if (normalized.bytes.length != input.bytes.length || normalized != input) {
      final retry = _resolve(memory, normalized);
      if (retry != null) return retry;
      _fail('Could not canonicalize path', normalized, errno().value);
    }
  }
  _fail('Could not canonicalize path', input, firstError);
}

MetaPath _normalize(MetaPath path) {
  final names = <PathComponent>[];
  for (final component in path.components) {
    if (component.kind == PathComponentKind.normal) {
      names.add(component);
    } else if (component.kind == PathComponentKind.parent) {
      if (names.isNotEmpty && names.last.kind == PathComponentKind.normal) {
        names.removeLast();
      } else if (!path.hasRoot) {
        names.add(component);
      }
    }
  }
  return MetaPath.fromBytes([
    if (path.hasRoot) 47,
    if (!path.hasRoot && names.isEmpty) 46,
    for (var i = 0; i < names.length; i++) ...[
      if (i > 0) 47,
      ...names[i].bytes,
    ],
  ]);
}

const _statxBtime = 0x800;
const _statxBasicStats = 0x7ff;

Cha? _readStatx(
  NativeMemory memory,
  Pointer<Uint8> filename,
  MetaPath path,
  Pointer<Int32> Function() errno,
) {
  final call = _statx;
  if (call == null) return null;
  final buffer = memory.allocate<_Statx>(sizeOf<_Statx>());
  const atFdcwd = -100;
  const mask = _statxBasicStats | _statxBtime;
  if (call(atFdcwd, filename, 0, mask, buffer) != 0) {
    final error = errno().value;
    // An invalid pointer distinguishes an available syscall from an older
    // kernel or a policy that disables statx. Rust checks the same way.
    call(atFdcwd, nullptr, 0, mask, nullptr);
    const efault = 14;
    if (errno().value == efault)
      _fail('Could not read file metadata', path, error);
    return null;
  }
  final stat = buffer.ref;
  return Cha(
    len: BigInt.from(stat.size).toUnsigned(64),
    btime: stat.mask & _statxBtime == 0
        ? null
        : _timestamp(stat.created.seconds, stat.created.nanos),
    ctime: _changeTime(stat.changed.seconds, stat.changed.nanos),
    mtime: _timestamp(stat.modified.seconds, stat.modified.nanos),
  );
}

Cha _readStat(
  NativeMemory memory,
  Pointer<Uint8> filename,
  MetaPath path,
  Pointer<Int32> Function() errno,
) {
  final mac = Platform.isMacOS;
  final abi = Abi.current();
  final supported = mac
      ? abi == Abi.macosArm64 || abi == Abi.macosX64
      : abi == Abi.linuxArm64 || abi == Abi.linuxX64;
  if (!supported) throw UnsupportedError('stat layout is unavailable on $abi');
  final stat = _stat;
  final buffer = memory.allocate<Uint8>(256);
  if (stat(filename, buffer.cast()) != 0)
    _fail('Could not read file metadata', path, errno().value);
  final data = ByteData.sublistView(buffer.asTypedList(256));
  int read(int offset) => data.getInt64(offset, Endian.host);
  // Darwin's 64-bit inode layout contains four timespecs before st_size.
  // On Linux x64/arm64, stat64 has three timespecs following st_size.
  return Cha(
    len: BigInt.from(read(mac ? 96 : 48)).toUnsigned(64),
    btime: mac ? _timestamp(read(80), read(88), apple: true) : null,
    ctime: mac
        ? _changeTime(read(64), read(72))
        : _changeTime(read(104), read(112)),
    mtime: mac
        ? _timestamp(read(48), read(56), apple: true)
        : _timestamp(read(88), read(96)),
  );
}

MetaTimestamp? _timestamp(int seconds, int nanos, {bool apple = false}) {
  const minI64 = -9223372036854775808;
  if (apple &&
      seconds > minI64 &&
      seconds <= 0 &&
      nanos < 0 &&
      nanos > -1000000000) {
    return MetaTimestamp(BigInt.from(seconds) - BigInt.one, nanos + 1000000000);
  }
  if (nanos < 0 || nanos >= 1000000000) return null;
  return MetaTimestamp(BigInt.from(seconds), nanos);
}

// Cha::from_metadata constructs ctime from UNIX_EPOCH + Duration.
MetaTimestamp? _changeTime(int seconds, int nanos) {
  final fraction = nanos.toUnsigned(32);
  final secs =
      BigInt.from(seconds).toUnsigned(64) + BigInt.from(fraction ~/ 1000000000);
  return secs.bitLength > 63
      ? null
      : MetaTimestamp(secs, fraction % 1000000000);
}

Never _fail(String message, MetaPath path, int code) =>
    throw FileSystemException(
      message,
      path.text(),
      OSError('POSIX file API failed', code),
    );
