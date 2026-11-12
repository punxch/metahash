import 'dart:io';

import '../lib/metahash.dart';
import 'hash_test.dart' show expectEqual;

void main(List<String> args) {
  if (args.length > 2) {
    throw ArgumentError(
      'Usage: native_test.dart [RUST_BINARY [RUST_METADATA_REFERENCE]]',
    );
  }
  final rust = args.isEmpty ? null : File(args[0]).absolute.path;
  final reference = args.length < 2 ? null : File(args[1]).absolute.path;
  final cli = File.fromUri(
    Platform.script.resolve('../bin/metahash.dart'),
  ).absolute.path;
  final root = Directory.systemTemp.createTempSync('metahashdart-');
  final previous = Directory.current;
  final base = root.absolute.path;
  try {
    Directory.current = base;
    _checkFixtures(base, cli, rust, reference);
  } finally {
    Directory.current = previous;
    final cleanup = Platform.isWindows ? Directory('\\\\?\\$base') : root;
    cleanup.deleteSync(recursive: true);
  }
}

void _checkFixtures(String base, String cli, String? rust, String? reference) {
  final separator = Platform.pathSeparator;
  final file = File('$base${separator}metadata.txt')
    ..writeAsStringSync('metadata');
  final oddName = File('$base${separator}中文 🎯 [a].txt')..createSync();
  File('$base${separator}-dash').createSync();
  final directory = Directory('$base${separator}sub')..createSync();
  final deepFile = [
    if (Platform.isWindows) '\\\\?\\$base' else base,
    for (var i = 0; i < 4; i++) 'segment-$i-${'x' * 65}',
    'metadata.txt',
  ].join(separator);
  File(deepFile).createSync(recursive: true);
  final alias = Link('$base${separator}alias');
  var linked = false;
  try {
    alias.createSync(file.path);
    linked = true;
  } on FileSystemException {
    if (!Platform.isWindows) rethrow;
  }

  var hashComparisons = 0;
  var metadataComparisons = 0;
  ProcessResult dart(List<String> options) => Process.runSync(
        Platform.resolvedExecutable,
        [cli, ...options],
        workingDirectory: base,
      );
  String success(ProcessResult result, List<String> options) {
    if (result.exitCode != 0) {
      throw StateError('$options exited ${result.exitCode}: ${result.stderr}');
    }
    return (result.stdout as String).trim();
  }

  String hashOutput(ProcessResult result, List<String> options) {
    final output = success(result, options);
    if (!RegExp(r'^[0-9a-f]{1,32}$').hasMatch(output)) {
      throw StateError('$options emitted an invalid hash: $output');
    }
    return output;
  }

  String compare(String path, [List<String>? arguments]) {
    final options = arguments ?? [path];
    final actual = hashOutput(dart(options), options);
    if (rust != null) {
      final expected = hashOutput(
        Process.runSync(rust, options, workingDirectory: base),
        options,
      );
      expectEqual(actual, expected, 'Rust CLI $options');
      hashComparisons++;
    }
    if (reference != null) {
      final expected = success(
        Process.runSync(reference, [path], workingDirectory: base),
        [path],
      ).split('\t');
      if (expected.length != 5) {
        throw StateError(
            'Invalid Rust metadata reference for $path: $expected');
      }
      final actual = _metadataFields(MetaFile.fromPath(path));
      for (final (index, field) in actual.entries.indexed) {
        expectEqual(
            field.value, expected[index], 'Rust ${field.key} for $path');
      }
      metadataComparisons++;
    }
    return actual;
  }

  final baseline = compare('metadata.txt');
  expectEqual(compare(file.path), baseline, 'Absolute path');
  expectEqual(
    compare('sub${separator}..${separator}metadata.txt'),
    baseline,
    'Dot-dot path',
  );
  expectEqual(
    compare('metadata.txt', ['--skip', '0', 'metadata.txt']),
    baseline,
    'Explicit zero',
  );
  expectEqual(
    compare('metadata.txt', ['metadata.txt', '--skip=+1']),
    compare(file.path, ['--skip', '1', file.path]),
    'Skip option forms',
  );
  final maxSkip =
      ((BigInt.one << (RustHashTarget.host.wordBytes * 8)) - BigInt.one)
          .toString();
  compare(file.path, [file.path, '--skip', maxSkip]);
  compare(oddName.path);
  compare('-dash', ['--', '-dash']);
  compare(directory.path);
  compare('.');
  compare(deepFile);
  if (Platform.isWindows) {
    expectEqual(
      compare('\\\\?\\${file.path}'),
      baseline,
      'Verbatim disk simplification',
    );
    expectEqual(
      compare('METADATA.TXT'),
      baseline,
      'Canonical file name case',
    );
  }
  if (linked) {
    expectEqual(
      compare(alias.path),
      baseline,
      'Symbolic link canonicalization',
    );
  }

  final metadata = MetaFile.fromPath(file.path);
  expectEqual(metadata.cha.len, BigInt.from(8), 'Size from OS');
  expectEqual(metadata.hashHex(), baseline, 'Library and CLI hash');
  expectEqual(
    metadata.cha.ctime == null,
    Platform.isWindows,
    'OS change time',
  );
  final originalMtime = metadata.cha.mtime!;
  file.setLastModifiedSync(DateTime.utc(2000, 1, 2, 3, 4, 5, 678));
  final newMtime = MetaFile.fromPath(file.path).cha.mtime!;
  if (newMtime.seconds == originalMtime.seconds)
    throw StateError('Modification time did not update');
  if (compare(file.path) == baseline)
    throw StateError('Changing mtime did not change the hash');

  if (!Platform.isWindows) {
    const largeSize = 0x100000003;
    final sparse = File('sparse').openSync(mode: FileMode.write);
    try {
      sparse.truncateSync(largeSize);
    } finally {
      sparse.closeSync();
    }
    compare('sparse');
    expectEqual(MetaFile.fromPath('sparse').cha.len, BigInt.from(largeSize),
        'Sparse file size');
    expectEqual(compare('absent/../metadata.txt'), compare(file.path),
        'Lexical fallback');
    if (Platform.isLinux && Directory('/proc').existsSync()) {
      compare('/proc');
      expectEqual(MetaFile.fromPath('/proc').cha.btime, null,
          'Missing procfs birth time');
    }
  }
  if (reference != null) {
    for (final side in ['positive', 'negative']) {
      final options = ['--set-mtime', file.path, side];
      success(
          Process.runSync(reference, options, workingDirectory: base), options);
      compare(file.path);
      if (side == 'positive') {
        final expected = Platform.isWindows ? 123456700 : 123456789;
        final actual = MetaFile.fromPath(file.path).cha.mtime!;
        expectEqual(
            actual.seconds, BigInt.from(1700000000), 'Native mtime seconds');
        expectEqual(actual.nanoseconds, expected, 'Native mtime nanoseconds');
      }
    }
  }

  expectEqual(dart(['--help']).exitCode, 0, 'Help status');
  expectEqual(
    (dart(['--version']).stdout as String).trim(),
    'metahash 0.1.0',
    'Version',
  );
  expectEqual(dart(['--skip', '-1', file.path]).exitCode, 2, 'Negative skip');
  expectEqual(
    dart(['--skip', '18446744073709551616', file.path]).exitCode,
    2,
    'Skip overflow',
  );
  expectEqual(
    dart(['--skip', '1', '--skip', '2', file.path]).exitCode,
    2,
    'Duplicate skip',
  );
  expectEqual(dart([]).exitCode, 2, 'Missing argument');
  expectEqual(dart(['missing']).exitCode, 1, 'Missing file');
  final localUrl = Url(
    Loc(MetaPath(file.path, style: RustHashTarget.host.pathStyle)),
    const Scheme.search('term'),
  );
  expectEqual(MetaFile.fromUrl(localUrl).url, localUrl, 'Local search URL');
  stdout.writeln(
    'Native metadata and CLI checks passed. '
    '$hashComparisons Rust CLI hash comparisons. '
    '$metadataComparisons Rust metadata comparisons.'
    '${linked ? ' Symbolic link checked.' : ' Symbolic links unavailable.'}',
  );
}

Map<String, String> _metadataFields(MetaFile file) {
  String time(MetaTimestamp? timestamp) =>
      timestamp == null ? '-' : '${timestamp.seconds}:${timestamp.nanoseconds}';
  return {
    'canonical path bytes': file.url.loc.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join(),
    'len': file.cha.len.toString(),
    'btime': time(file.cha.btime),
    'ctime': time(file.cha.ctime),
    'mtime': time(file.cha.mtime),
  };
}
