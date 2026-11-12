import 'dart:io';

import '../lib/metahash.dart';
import 'hash_test.dart' show expectEqual;

void main(List<String> args) {
  if (args.length > 1)
    throw ArgumentError('Usage: native_test.dart [RUST_BINARY]');
  final rust = args.isEmpty ? null : File(args.single).absolute.path;
  final cli = File.fromUri(
    Platform.script.resolve('../bin/metahash.dart'),
  ).absolute.path;
  final root = Directory.systemTemp.createTempSync('metahashdart-');
  final separator = Platform.pathSeparator;
  final base = root.absolute.path;
  final file = File('$base${separator}metadata.txt')
    ..writeAsStringSync('metadata');
  final oddName = File('$base${separator}中文 🎯 [a].txt')..createSync();
  final dashedName = File('$base${separator}-dash')..createSync();
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

  var comparisons = 0;
  ProcessResult dart(List<String> options) => Process.runSync(
    Platform.resolvedExecutable,
    [cli, ...options],
    workingDirectory: base,
  );
  String success(ProcessResult result, List<String> options) {
    if (result.exitCode != 0) {
      throw StateError('$options exited ${result.exitCode}: ${result.stderr}');
    }
    final output = (result.stdout as String).trim();
    if (!RegExp(r'^[0-9a-f]{1,32}$').hasMatch(output)) {
      throw StateError('$options emitted an invalid hash: $output');
    }
    return output;
  }

  String compare(List<String> options) {
    final actual = success(dart(options), options);
    if (rust != null) {
      final expected = success(
        Process.runSync(rust, options, workingDirectory: base),
        options,
      );
      expectEqual(actual, expected, 'Rust CLI $options');
      comparisons++;
    }
    return actual;
  }

  try {
    final baseline = compare(['metadata.txt']);
    expectEqual(compare([file.path]), baseline, 'Absolute path');
    expectEqual(
      compare(['sub${separator}..${separator}metadata.txt']),
      baseline,
      'Dot-dot path',
    );
    expectEqual(
      compare(['--skip', '0', 'metadata.txt']),
      baseline,
      'Explicit zero',
    );
    expectEqual(
      compare(['metadata.txt', '--skip=+1']),
      compare(['--skip', '1', file.path]),
      'Skip option forms',
    );
    final maxSkip =
        ((BigInt.one << (RustHashTarget.host.wordBytes * 8)) - BigInt.one)
            .toString();
    compare([file.path, '--skip', maxSkip]);
    compare([oddName.path]);
    compare(['--', '-dash']);
    compare([directory.path]);
    compare(['.']);
    compare([deepFile]);
    if (Platform.isWindows) {
      expectEqual(
        compare(['\\\\?\\${file.path}']),
        baseline,
        'Verbatim disk simplification',
      );
      expectEqual(
        compare(['METADATA.TXT']),
        baseline,
        'Canonical file name case',
      );
    }
    if (linked) {
      expectEqual(
        compare([alias.path]),
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
    if (compare([file.path]) == baseline)
      throw StateError('Changing mtime did not change the hash');

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
    expectEqual(dashedName.existsSync(), true, 'Leading-hyphen test file');
    stdout.writeln(
      'Native metadata and CLI checks passed. $comparisons Rust CLI comparisons.'
      '${linked ? ' Symbolic link checked.' : ' Symbolic links unavailable.'}',
    );
  } finally {
    if (Platform.isWindows) {
      File(deepFile).deleteSync();
      Directory(File(deepFile).parent.path).deleteSync();
    }
    root.deleteSync(recursive: true);
  }
}
