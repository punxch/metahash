import 'dart:convert';
import 'dart:typed_data';

import 'bytes.dart';

/// A byte sequence interned by [Pool] within the current Dart isolate.
final class InternedSymbol implements Comparable<InternedSymbol> {
  InternedSymbol._(Uint8List bytes) : bytes = bytes.asUnmodifiableView();

  final Uint8List bytes;

  String get text => decodeUtf8(bytes);

  @override
  int compareTo(InternedSymbol other) {
    final length = bytes.length < other.bytes.length
        ? bytes.length
        : other.bytes.length;
    for (var i = 0; i < length; i++) {
      final difference = bytes[i] - other.bytes[i];
      if (difference != 0) return difference;
    }
    return bytes.length.compareTo(other.bytes.length);
  }
}

/// Interns text and byte sequences by their bytes. Unused symbols can be collected.
abstract final class Pool {
  static final _symbols = <String, WeakReference<InternedSymbol>>{};
  static final _remove = Finalizer<String>((key) {
    if (_symbols[key]?.target == null) _symbols.remove(key);
  });

  static InternedSymbol internText(String value) =>
      internBytes(utf8.encode(value));

  static InternedSymbol internBytes(List<int> value) {
    for (final byte in value) {
      RangeError.checkValueInInterval(byte, 0, 255, 'byte');
    }
    final key = String.fromCharCodes(value);
    final found = _symbols[key]?.target;
    if (found != null) return found;
    final symbol = InternedSymbol._(Uint8List.fromList(value));
    _symbols[key] = WeakReference(symbol);
    _remove.attach(symbol, key);
    return symbol;
  }
}
