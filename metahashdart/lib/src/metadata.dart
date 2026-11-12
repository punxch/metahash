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

  factory MetaTimestamp.fromJson(Map<String, Object?> json) => MetaTimestamp(
    _parseInteger(json['seconds'], 'seconds'),
    _parseNanoseconds(json['nanoseconds']),
  );

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

  Map<String, Object?> toJson() => {
    'seconds': seconds.toString(),
    'nanoseconds': nanoseconds,
  };
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

  factory Cha.fromJson(Map<String, Object?> json) {
    MetaTimestamp? time(String key) {
      if (!json.containsKey(key)) throw FormatException('Missing $key');
      final value = json[key];
      if (value == null) return null;
      if (value is! Map<String, Object?>) {
        throw FormatException('Expected $key to be a timestamp or null');
      }
      return MetaTimestamp.fromJson(value);
    }

    return Cha(
      len: _parseInteger(json['len'], 'len'),
      btime: time('btime'),
      ctime: time('ctime'),
      mtime: time('mtime'),
    );
  }

  final BigInt len;
  final MetaTimestamp? btime;
  final MetaTimestamp? ctime;
  final MetaTimestamp? mtime;

  Map<String, Object?> toJson() => {
    'len': len.toString(),
    'btime': btime?.toJson(),
    'ctime': ctime?.toJson(),
    'mtime': mtime?.toJson(),
  };
}

final _decimal = RegExp(r'^-?[0-9]+$');
final _maxJsonInteger = BigInt.from(9007199254740991);

BigInt _parseInteger(Object? value, String field) {
  if (value is String && _decimal.hasMatch(value)) return BigInt.parse(value);
  if (value is int) {
    final number = BigInt.from(value);
    if (number.abs() <= _maxJsonInteger) return number;
  }
  throw FormatException('Expected an exact decimal integer for $field');
}

int _parseNanoseconds(Object? value) {
  final nanos = _parseInteger(value, 'nanoseconds');
  if (nanos < BigInt.zero || nanos > BigInt.from(999999999)) {
    throw const FormatException('Nanoseconds must be in 0..999999999');
  }
  return nanos.toInt();
}
