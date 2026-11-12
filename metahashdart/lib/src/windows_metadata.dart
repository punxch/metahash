import 'dart:ffi';
import 'dart:io';

import 'metadata.dart';
import 'native_memory.dart';
import 'path.dart';

final _kernel32 = DynamicLibrary.open('kernel32.dll');
final _crt = DynamicLibrary.open('msvcrt.dll');

final _createFile = _kernel32
    .lookupFunction<
      IntPtr Function(
        Pointer<Uint16>,
        Uint32,
        Uint32,
        Pointer<Void>,
        Uint32,
        Uint32,
        IntPtr,
      ),
      int Function(Pointer<Uint16>, int, int, Pointer<Void>, int, int, int)
    >('CreateFileW');
final _closeHandle = _kernel32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');
final _getFileInformation = _kernel32
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<_FileInformation>),
      int Function(int, Pointer<_FileInformation>)
    >('GetFileInformationByHandle');
final _getFinalPath = _kernel32
    .lookupFunction<
      Uint32 Function(IntPtr, Pointer<Uint16>, Uint32, Uint32),
      int Function(int, Pointer<Uint16>, int, int)
    >('GetFinalPathNameByHandleW');
final _getFullPath = _kernel32
    .lookupFunction<
      Uint32 Function(
        Pointer<Uint16>,
        Uint32,
        Pointer<Uint16>,
        Pointer<Pointer<Uint16>>,
      ),
      int Function(
        Pointer<Uint16>,
        int,
        Pointer<Uint16>,
        Pointer<Pointer<Uint16>>,
      )
    >('GetFullPathNameW');
final _getLastError = _kernel32
    .lookupFunction<Uint32 Function(), int Function()>(
      'GetLastError',
      isLeaf: true,
    );

final class _FileTime extends Struct {
  @Uint32()
  external int low;
  @Uint32()
  external int high;

  MetaTimestamp toTimestamp() =>
      MetaTimestamp.fromWindowsFileTime(_wideUnsigned(low, high));
}

final class _FileInformation extends Struct {
  @Uint32()
  external int attributes;
  external _FileTime creationTime;
  external _FileTime lastAccessTime;
  external _FileTime lastWriteTime;
  @Uint32()
  external int volumeSerialNumber;
  @Uint32()
  external int sizeHigh;
  @Uint32()
  external int sizeLow;
  @Uint32()
  external int numberOfLinks;
  @Uint32()
  external int indexHigh;
  @Uint32()
  external int indexLow;
}

BigInt _wideUnsigned(int low, int high) =>
    BigInt.from(low) | (BigInt.from(high) << 32);

(MetaPath, Cha) readWindowsMetadata(
  MetaPath input, {
  required bool canonicalize,
}) {
  final text = input.text(allowMalformed: false);
  final lastError = _getLastError;
  Never fail(String operation) => throw FileSystemException(
    operation,
    text,
    OSError('Windows file API failed', lastError()),
  );

  final memory = NativeMemory(_crt);
  try {
    final nativePath = _openPath(memory, input, fail);
    const readAttributes = 0x80;
    const shareReadWriteDelete = 7;
    const openExisting = 3;
    const backupSemantics = 0x02000000;
    final handle = _createFile(
      nativePath,
      readAttributes,
      shareReadWriteDelete,
      nullptr,
      openExisting,
      backupSemantics,
      0,
    );
    if (handle == -1) fail('Could not open file for metadata');
    try {
      final canonical = canonicalize
          ? _readPath(
              memory,
              (buffer, length) => _getFinalPath(handle, buffer, length, 0),
              () => fail('Could not resolve final path'),
            )
          : null;
      final info = memory.allocate<_FileInformation>(
        sizeOf<_FileInformation>(),
      );
      if (_getFileInformation(handle, info) == 0)
        fail('Could not read file metadata');
      return (
        canonical == null ? input : _simplifyFinalPath(canonical),
        Cha(
          len: _wideUnsigned(info.ref.sizeLow, info.ref.sizeHigh),
          btime: info.ref.creationTime.toTimestamp(),
          ctime: null,
          mtime: info.ref.lastWriteTime.toTimestamp(),
        ),
      );
    } finally {
      _closeHandle(handle);
    }
  } finally {
    memory.close();
  }
}

Pointer<Uint16> _widePath(NativeMemory memory, String text) {
  final units = text.codeUnits;
  final buffer = memory.allocate<Uint16>((units.length + 1) * sizeOf<Uint16>());
  buffer.asTypedList(units.length).setAll(0, units);
  return buffer;
}

String _readPath(
  NativeMemory memory,
  int Function(Pointer<Uint16>, int) read,
  Never Function() fail,
) {
  var capacity = 260;
  while (true) {
    final buffer = memory.allocate<Uint16>(capacity * sizeOf<Uint16>());
    final length = read(buffer, capacity);
    if (length == 0) fail();
    if (length < capacity)
      return String.fromCharCodes(buffer.asTypedList(length));
    capacity = length + 1;
  }
}

const _verbatim = '\\\\?\\';
const _device = '\\\\.\\';
const _nt = '\\??\\';
const _network = '\\\\';
const _verbatimNetwork = '${_verbatim}UNC\\';

Pointer<Uint16> _openPath(
  NativeMemory memory,
  MetaPath input,
  Never Function(String) fail,
) {
  final text = input.text(allowMalformed: false);
  final wide = _widePath(memory, text);
  if (text.startsWith(_verbatim) || text.startsWith(_nt)) return wide;

  final prefix = input.windowsPrefix?.kind;
  if (text.length + 1 < 248 &&
      (input.isAbsolute ||
          (prefix == WindowsPrefixKind.disk && text.length == 2))) {
    return wide;
  }
  final fullPath = _readPath(
    memory,
    (buffer, capacity) => _getFullPath(wide, capacity, buffer, nullptr),
    () => fail('Could not make path absolute'),
  );
  if (fullPath.startsWith(_verbatim) || fullPath.startsWith(_nt)) {
    return _widePath(memory, fullPath);
  }
  if (fullPath.startsWith(_device)) {
    return _widePath(memory, _verbatim + fullPath.substring(4));
  }
  if (fullPath.startsWith(_network)) {
    return _widePath(memory, _verbatimNetwork + fullPath.substring(2));
  }
  if (fullPath.length >= 3 &&
      fullPath.codeUnitAt(1) == 58 &&
      fullPath.codeUnitAt(2) == 92) {
    return _widePath(memory, _verbatim + fullPath);
  }
  return _widePath(memory, fullPath);
}

final _reservedName = RegExp(
  r'^(AUX|NUL|PRN|CON|COM[1-9]|LPT[1-9])$',
  caseSensitive: false,
);
final _invalidName = RegExp(r'[\x00-\x1f<>:"/\\|?*]|[ .]$');
final _trailingDotsSpaces = RegExp(r'[ .]+$');

MetaPath _simplifyFinalPath(String text) {
  final path = MetaPath(text, style: PathStyle.windows);
  if (path.windowsPrefix?.kind != WindowsPrefixKind.verbatimDisk ||
      text.length > 260) {
    return path;
  }
  for (final component in path.components.skip(1)) {
    if (component.kind == PathComponentKind.root) continue;
    if (component.kind != PathComponentKind.normal) return path;
    final namePath = MetaPath.fromBytes(
      component.bytes,
      style: PathStyle.windows,
    );
    final name = namePath.text();
    if (name.length > 255 || _invalidName.hasMatch(name) || !_isUnicode(name))
      return path;
    final stem = namePath.stem?.text().replaceFirst(_trailingDotsSpaces, '');
    if (stem != null && _reservedName.hasMatch(stem)) return path;
  }
  return path.slice(4);
}

bool _isUnicode(String text) {
  for (final rune in text.runes) {
    if (rune >= 0xd800 && rune <= 0xdfff) return false;
  }
  return true;
}
