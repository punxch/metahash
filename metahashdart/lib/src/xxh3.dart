import 'dart:typed_data';

// Scalar XXH3-128 with the default seed and secret. See LICENSE-xxh3.
final _prime32_1 = BigInt.from(0x9e3779b1);
final _prime32_2 = BigInt.from(0x85ebca77);
final _prime32_3 = BigInt.from(0xc2b2ae3d);
final _prime64_1 = BigInt.parse('9e3779b185ebca87', radix: 16);
final _prime64_2 = BigInt.parse('c2b2ae3d27d4eb4f', radix: 16);
final _prime64_3 = BigInt.parse('165667b19e3779f9', radix: 16);
final _prime64_4 = BigInt.parse('85ebca77c2b2ae63', radix: 16);
final _prime64_5 = BigInt.parse('27d4eb2f165667c5', radix: 16);
final _primeMx1 = BigInt.parse('165667919e3779f9', radix: 16);
final _primeMx2 = BigInt.parse('9fb21c651e98df25', radix: 16);
final _mask32 = (BigInt.one << 32) - BigInt.one;

const _secretHex =
    'b8fe6c3923a44bbe7c01812cf721ad1c'
    'ded46de9839097db7240a4a4b7b3671f'
    'cb79e64eccc0e578825ad07dccff7221'
    'b8084674f743248ee03590e6813a264c'
    '3c2852bb91c300cb88d0658b1b532ea3'
    '71644897a20df94e3819ef46a9deacd8'
    'a8fa763fe39c343ff9dcbbc7c70b4f1d'
    '8a51e04bcdb45931c89f7ec9d9787364'
    'eac5ac8334d3ebc3c581a0fffa1363eb'
    '170ddd51b7f0da49d316552629d4689e'
    '2b16be587d47a1fc8ff8b8d17ad031ce'
    '45cb3a8f95160428afd7fbcabb4b407e';

final _secret = ByteData.sublistView(
  Uint8List.fromList([
    for (var i = 0; i < _secretHex.length; i += 2)
      int.parse(_secretHex.substring(i, i + 2), radix: 16),
  ]),
);

/// Computes the unsigned XXH3-128 digest with the default seed.
BigInt xxh3_128(Uint8List bytes) {
  final input = ByteData.sublistView(bytes);
  final length = bytes.length;
  final (low, high) = switch (length) {
    0 => (_avalanche64(_key(64) ^ _key(72)), _avalanche64(_key(80) ^ _key(88))),
    <= 3 => _oneToThree(bytes),
    <= 8 => _fourToEight(input, length),
    <= 16 => _nineToSixteen(input, length),
    <= 240 => _medium(input, length),
    _ => _long(input, length),
  };
  return (high << 64) | low;
}

BigInt _read64(ByteData data, int offset) =>
    BigInt.from(data.getUint32(offset, Endian.little)) |
    (BigInt.from(data.getUint32(offset + 4, Endian.little)) << 32);

BigInt _key(int offset) => _read64(_secret, offset);

BigInt _swapBytes(BigInt value, int width) {
  var reversed = BigInt.zero;
  final byteMask = BigInt.from(255);
  for (var i = 0; i < width; i++) {
    reversed = (reversed << 8) | (value & byteMask);
    value >>= 8;
  }
  return reversed;
}

BigInt _avalanche64(BigInt value) {
  value = ((value ^ (value >> 33)) * _prime64_2).toUnsigned(64);
  value = ((value ^ (value >> 29)) * _prime64_3).toUnsigned(64);
  return value ^ (value >> 32);
}

BigInt _avalanche(BigInt value) {
  value = ((value ^ (value >> 37)) * _primeMx1).toUnsigned(64);
  return value ^ (value >> 32);
}

(BigInt, BigInt) _oneToThree(Uint8List bytes) {
  final length = bytes.length;
  final packed = BigInt.from(
    bytes.last |
        (length << 8) |
        (bytes.first << 16) |
        (bytes[length ~/ 2] << 24),
  ).toUnsigned(32);
  final swapped = _swapBytes(packed, 4);
  final rotated = ((swapped << 13) | (swapped >> 19)) & _mask32;
  final lowKey = BigInt.from(
    _secret.getUint32(0, Endian.little) ^ _secret.getUint32(4, Endian.little),
  ).toUnsigned(32);
  final highKey = BigInt.from(
    _secret.getUint32(8, Endian.little) ^ _secret.getUint32(12, Endian.little),
  ).toUnsigned(32);
  return (_avalanche64(packed ^ lowKey), _avalanche64(rotated ^ highKey));
}

(BigInt, BigInt) _fourToEight(ByteData input, int length) {
  final packed =
      BigInt.from(input.getUint32(0, Endian.little)) |
      (BigInt.from(input.getUint32(length - 4, Endian.little)) << 32);
  final product =
      (packed ^ _key(16) ^ _key(24)) * (_prime64_1 + BigInt.from(length * 4));
  var low = product.toUnsigned(64);
  final high = ((product >> 64) + (low << 1)).toUnsigned(64);
  low ^= high >> 3;
  low = ((low ^ (low >> 35)) * _primeMx2).toUnsigned(64);
  return (low ^ (low >> 28), _avalanche(high));
}

(BigInt, BigInt) _nineToSixteen(ByteData input, int length) {
  final tail = _read64(input, length - 8);
  final product = (_read64(input, 0) ^ tail ^ _key(32) ^ _key(40)) * _prime64_1;
  final keyedTail = tail ^ _key(48) ^ _key(56);
  final high =
      ((product >> 64) +
              (keyedTail & ~_mask32) +
              (keyedTail & _mask32) * _prime32_2)
          .toUnsigned(64);
  final low =
      (product + (BigInt.from(length - 1) << 54)).toUnsigned(64) ^
      _swapBytes(high, 8);
  final mixed = ((high << 64) | low) * _prime64_2;
  return (
    _avalanche(mixed.toUnsigned(64)),
    _avalanche((mixed >> 64).toUnsigned(64)),
  );
}

BigInt _foldMultiply(BigInt a, BigInt b) {
  final product = a * b;
  return product.toUnsigned(64) ^ (product >> 64);
}

(BigInt, BigInt) _medium(ByteData input, int length) {
  final size = BigInt.from(length);
  var low = (size * _prime64_1).toUnsigned(64);
  var high = BigInt.zero;

  void mix(int front, int back, int keyOffset) {
    final a = _read64(input, front);
    final b = _read64(input, front + 8);
    final c = _read64(input, back);
    final d = _read64(input, back + 8);
    low =
        (low + _foldMultiply(a ^ _key(keyOffset), b ^ _key(keyOffset + 8)))
            .toUnsigned(64) ^
        (c + d).toUnsigned(64);
    high =
        (high +
                _foldMultiply(
                  c ^ _key(keyOffset + 16),
                  d ^ _key(keyOffset + 24),
                ))
            .toUnsigned(64) ^
        (a + b).toUnsigned(64);
  }

  if (length <= 128) {
    for (var i = (length - 1) ~/ 32; i >= 0; i--) {
      mix(i * 16, length - (i + 1) * 16, i * 32);
    }
  } else {
    for (var i = 0; i < 128; i += 32) {
      mix(i, i + 16, i);
    }
    low = _avalanche(low);
    high = _avalanche(high);
    for (var i = 128; i + 32 <= length; i += 32) {
      mix(i, i + 16, i - 128 + 3);
    }
    mix(length - 16, length - 32, 103);
  }
  return (
    _avalanche((low + high).toUnsigned(64)),
    (-_avalanche(
      (low * _prime64_1 + high * _prime64_4 + size * _prime64_2).toUnsigned(64),
    )).toUnsigned(64),
  );
}

(BigInt, BigInt) _long(ByteData input, int length) {
  final acc = [
    _prime32_3,
    _prime64_1,
    _prime64_2,
    _prime64_3,
    _prime64_4,
    _prime32_2,
    _prime64_5,
    _prime32_1,
  ];

  void accumulate(int offset, int keyOffset) {
    for (var lane = 0; lane < acc.length; lane++) {
      final word = _read64(input, offset + lane * 8);
      final keyed = word ^ _key(keyOffset + lane * 8);
      acc[lane ^ 1] = (acc[lane ^ 1] + word).toUnsigned(64);
      acc[lane] = (acc[lane] + (keyed & _mask32) * (keyed >> 32)).toUnsigned(
        64,
      );
    }
  }

  const stripeSize = 64;
  const stripesPerBlock = 16;
  final stripes = (length - 1) ~/ stripeSize;
  for (var stripe = 0; stripe < stripes; stripe++) {
    final index = stripe % stripesPerBlock;
    accumulate(stripe * stripeSize, index * 8);
    if (index == stripesPerBlock - 1) {
      for (var lane = 0; lane < acc.length; lane++) {
        final value = acc[lane];
        acc[lane] =
            ((value ^ (value >> 47) ^ _key(128 + lane * 8)) * _prime32_1)
                .toUnsigned(64);
      }
    }
  }
  accumulate(length - stripeSize, 121);

  BigInt merge(BigInt initial, int keyOffset) {
    var sum = initial;
    for (var lane = 0; lane < acc.length; lane += 2) {
      sum += _foldMultiply(
        acc[lane] ^ _key(keyOffset + lane * 8),
        acc[lane + 1] ^ _key(keyOffset + (lane + 1) * 8),
      );
    }
    return _avalanche(sum.toUnsigned(64));
  }

  final size = BigInt.from(length);
  return (merge(size * _prime64_1, 11), merge(~(size * _prime64_2), 117));
}
