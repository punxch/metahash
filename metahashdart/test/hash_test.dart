import 'dart:io';

import '../lib/metahash.dart';

void main() {
  checkWindows();
  checkPosixLayout();
}

void checkWindows() {
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

void checkPosixLayout() {
  // Generated with Rust Path::hash and the Unix Timespec field types
  // (i64 seconds and u32 nanoseconds), using the same Option discriminants.
  final cases = File.fromUri(
    Platform.script.resolve('fixtures/posix_layout.tsv'),
  ).readAsLinesSync();
  for (var i = 0; i < cases.length; i++) {
    final [path, input, hash] = cases[i].split('\t');
    final file = MetaFile(
      Url.regular(MetaPath(path)),
      Cha(
        len: BigInt.from(4000000000 + i),
        btime: i.isEven ? MetaTimestamp(-BigInt.one, 876543211) : null,
        ctime: MetaTimestamp(BigInt.from(1800000000), 123456789),
        mtime: i % 3 == 0 ? null : MetaTimestamp(BigInt.from(1700000000), 1),
      ),
    );
    final skip = BigInt.from(i * 9);
    final bytes = file.hashInput(skip: skip, target: RustHashTarget.unix64);
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    expectEqual(hex, input, 'POSIX path "$path" input');
    expectEqual(
      file.hashHex(skip: skip, target: RustHashTarget.unix64),
      hash,
      'POSIX path "$path" hash',
    );
  }
  stdout.writeln('${cases.length} Rust POSIX-layout hash vectors matched.');
}

void expectEqual(Object? actual, Object? expected, String label) {
  if (actual != expected)
    throw StateError('$label\nActual   $actual\nExpected $expected');
}
