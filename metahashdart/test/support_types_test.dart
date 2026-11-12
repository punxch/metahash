import 'dart:io';

import '../lib/metahash.dart';
import 'hash_test.dart' show expectEqual;

void main() {
  final name = Pool.internText('中文');
  expectEqual(
    identical(name, Pool.internBytes(name.bytes)),
    true,
    'Byte and string interning',
  );
  expectEqual(name.text, '中文', 'Symbol text');
  expectEqual(Pool.internText('\uFEFF').text, '\uFEFF', 'Symbol preserves BOM');
  expectEqual(
    Pool.internBytes([255]).compareTo(Pool.internBytes([0])) > 0,
    true,
    'Unsigned symbol order',
  );
  expectEqual(
    identical(Pool.internText(''), Pool.internBytes([])),
    true,
    'Empty symbol',
  );

  final cell = RoCell<int?>();
  expectEqual(cell.isInitialized, false, 'Uninitialized cell');
  expectStateError(() => cell.value);
  cell.init(null);
  expectEqual(cell.value, null, 'Stored null');
  expectStateError(
    () => cell.initWith(() => throw StateError('Initializer should not run')),
  );
  expectEqual(cell.take(), null, 'Take and reset');
  cell.initWith(() => 5);
  expectEqual(cell.value, 5, 'Reinitialize');
  expectEqual(RoCell.initialized(3).take(), 3, 'Initialized constructor');
  stdout.writeln('Interning and read-only cell checks passed.');
}

void expectStateError(Object? Function() call) {
  try {
    call();
  } on StateError {
    return;
  }
  throw StateError('Expected a StateError');
}
