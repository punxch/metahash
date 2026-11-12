import 'dart:io';
import 'dart:typed_data';

import '../lib/metahash.dart';

void main() {
  // Generated with the Rust project's streaming XxHash3_128 (twox-hash 2.1.5).
  final fixture = File.fromUri(Platform.script.resolve('fixtures/xxh3.txt'));
  final cases = fixture.readAsLinesSync();
  for (final row in cases) {
    final [size, expected] = row.split(' ');
    final length = int.parse(size);
    final buffer = Uint8List(length + 6);
    for (var i = 0; i < length; i++) {
      buffer[i + 3] = (i * 37 + i ~/ 7 + 193) & 255;
    }
    final input = Uint8List.sublistView(buffer, 3, length + 3);
    final actual = xxh3_128(input).toRadixString(16).padLeft(32, '0');
    if (actual != expected) {
      throw StateError('XXH3-128 at length $length: $actual != $expected');
    }
  }
  stdout.writeln('${cases.length} Rust XXH3-128 vectors matched.');
}
