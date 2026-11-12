import 'dart:ffi';

/// Owns temporary C allocations made during one metadata query.
final class NativeMemory {
  NativeMemory(DynamicLibrary libc)
    : _calloc = libc
          .lookupFunction<
            Pointer<Void> Function(Size, Size),
            Pointer<Void> Function(int, int)
          >('calloc'),
      _free = libc
          .lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('free');

  final Pointer<Void> Function(int, int) _calloc;
  final void Function(Pointer<Void>) _free;
  final _owned = <Pointer<Void>>[];

  Pointer<T> allocate<T extends NativeType>(int bytes) {
    final pointer = _calloc(1, bytes);
    if (pointer == nullptr)
      throw StateError('Could not allocate native buffer');
    _owned.add(pointer);
    return pointer.cast<T>();
  }

  void own(Pointer<Void> pointer) {
    _owned.add(pointer);
  }

  void close() {
    for (final pointer in _owned.reversed) {
      _free(pointer);
    }
    _owned.clear();
  }
}
