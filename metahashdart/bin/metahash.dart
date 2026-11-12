import 'dart:io';

import '../lib/metahash.dart';

const _usage = 'Usage: metahash [OPTIONS] <FILE>';
const _help = '''$_usage

Arguments:
  <FILE>  File path to calculate metadata hash

Options:
      --skip <SKIP>  Skip value for hash calculation [default: 0]
  -h, --help         Print help
  -V, --version      Print version
''';

void main(List<String> args) {
  try {
    final (path, skip) = _parseArgs(args);
    if (path == null) return;
    stdout.writeln(MetaFile.fromPath(path).hashHex(skip: skip));
  } on FormatException catch (error) {
    stderr.writeln('error: ${error.message}\n\n$_usage');
    exitCode = 2;
  } on FileSystemException catch (error) {
    stderr.writeln('Error: $error');
    exitCode = 1;
  } on ArgumentError catch (error) {
    stderr.writeln('Error: ${error.message}');
    exitCode = 1;
  } on UnsupportedError catch (error) {
    stderr.writeln('Error: ${error.message}');
    exitCode = 1;
  }
}

final _unsignedDecimal = RegExp(r'^\+?[0-9]+$');

(String?, BigInt?) _parseArgs(List<String> args) {
  String? file;
  BigInt? skip;
  var positionalOnly = false;
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (!positionalOnly) {
      if (arg == '--') {
        positionalOnly = true;
        continue;
      }
      if (arg == '--help' || arg == '-h') {
        stdout.write(_help);
        return (null, null);
      }
      if (arg == '--version' || arg == '-V') {
        stdout.writeln('metahash 0.1.0');
        return (null, null);
      }
      if (arg == '--skip' || arg.startsWith('--skip=')) {
        if (skip != null)
          throw const FormatException('--skip cannot be used multiple times');
        if (arg == '--skip' && i + 1 == args.length) {
          throw const FormatException('--skip requires a value');
        }
        final text = arg == '--skip' ? args[++i] : arg.substring(7);
        if (!_unsignedDecimal.hasMatch(text)) {
          throw FormatException('invalid unsigned integer for --skip: $text');
        }
        skip = BigInt.parse(text);
        if (skip.bitLength > RustHashTarget.host.wordBytes * 8) {
          throw FormatException('value is too large for --skip: $text');
        }
        continue;
      }
      if (arg.startsWith('-') && arg != '-') {
        throw FormatException('unexpected argument: $arg');
      }
    }
    if (file != null) throw FormatException('unexpected argument: $arg');
    file = arg;
  }
  if (file == null)
    throw const FormatException('the required <FILE> argument is missing');
  return (file, skip);
}
