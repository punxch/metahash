import 'dart:io';

import '../lib/metahash.dart';

void main() {
  final cases = File.fromUri(
    Platform.script.resolve('fixtures/windows_hash.tsv'),
  ).readAsLinesSync();
  for (final row in cases) {
    final [kind, path, skipText, expectedInput, expectedHash] = row.split('\t');
    final skip = BigInt.parse(skipText);
    final scheme = switch (kind) {
      'search' => const Scheme.search('a 🎯'),
      'archive' => const Scheme.archive(''),
      'sftp' => const Scheme.sftp('host'),
      'regular' => const Scheme.regular(),
      _ => throw StateError('Unexpected scheme $kind'),
    };
    final file = MetaFile(
      Url(Loc(MetaPath(path, style: PathStyle.windows)), scheme),
      Cha(
        len: skip,
        btime: MetaTimestamp(BigInt.from(-3), 100),
        ctime: null,
        mtime: MetaTimestamp(BigInt.from(1700000000), 123456700),
      ),
    );
    final input = file.hashInput(skip: skip);
    final inputHex = input
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    expectEqual(inputHex, expectedInput, '$kind path "$path" input');
    expectEqual(
      file.hashHex(skip: skip),
      expectedHash,
      '$kind path "$path" hash',
    );
  }
  stdout.writeln('${cases.length} Rust Windows metadata hash vectors matched.');
}

void expectEqual(Object? actual, Object? expected, String label) {
  if (actual != expected)
    throw StateError('$label\nActual   $actual\nExpected $expected');
}
