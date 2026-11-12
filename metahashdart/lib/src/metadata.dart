final _fileTimeEpoch = BigInt.from(11644473600);
final _fileTimeTicksPerSecond = BigInt.from(10000000);
final _minSeconds = -(BigInt.one << 63);
final _maxSeconds = (BigInt.one << 63) - BigInt.one;
final _maxUint64 = (BigInt.one << 64) - BigInt.one;

/// A timestamp as signed Unix seconds and a nonnegative nanosecond fraction.
final class MetaTimestamp {
  MetaTimestamp(this.seconds, this.nanoseconds) {
    if (seconds < _minSeconds || seconds > _maxSeconds) {
      throw ArgumentError.value(
        seconds,
        'seconds',
        'Expected a signed 64-bit integer',
      );
    }
    RangeError.checkValueInInterval(nanoseconds, 0, 999999999, 'nanoseconds');
  }

  factory MetaTimestamp.fromWindowsFileTime(BigInt ticks) {
    if (ticks < BigInt.zero || ticks > _maxUint64) {
      throw ArgumentError.value(
        ticks,
        'ticks',
        'Expected an unsigned FILETIME',
      );
    }
    return MetaTimestamp(
      ticks ~/ _fileTimeTicksPerSecond - _fileTimeEpoch,
      (ticks % _fileTimeTicksPerSecond).toInt() * 100,
    );
  }

  final BigInt seconds;
  final int nanoseconds;

  BigInt toWindowsFileTime() {
    final ticks =
        (seconds + _fileTimeEpoch) * _fileTimeTicksPerSecond +
        BigInt.from(nanoseconds ~/ 100);
    if (nanoseconds % 100 != 0 || ticks < BigInt.zero || ticks > _maxUint64) {
      throw ArgumentError(
        'Timestamp cannot be represented as a Windows FILETIME',
      );
    }
    return ticks;
  }
}

/// The exact file metadata hashed by Rust metahash.
final class Cha {
  Cha({
    required this.len,
    required this.btime,
    required this.ctime,
    required this.mtime,
  }) {
    if (len < BigInt.zero || len > _maxUint64) {
      throw ArgumentError.value(
        len,
        'len',
        'Expected an unsigned 64-bit integer',
      );
    }
  }

  final BigInt len;
  final MetaTimestamp? btime;
  final MetaTimestamp? ctime;
  final MetaTimestamp? mtime;
}
