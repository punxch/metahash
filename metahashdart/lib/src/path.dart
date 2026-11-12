import 'dart:convert';
import 'dart:typed_data';

enum PathStyle { posix, windows }

enum PathComponentKind { prefix, root, current, parent, normal }

// Prefix variant order is part of Rust's derived Hash representation.
enum WindowsPrefixKind {
  verbatim,
  verbatimUnc,
  verbatimDisk,
  device,
  unc,
  disk,
}

final class WindowsPrefix {
  WindowsPrefix._(this.kind, this._end, {this.drive, this.first, this.second});

  final WindowsPrefixKind kind;
  final int? drive;
  final Uint8List? first;
  final Uint8List? second;
  final int _end;

  bool get isVerbatim => kind.index <= WindowsPrefixKind.verbatimDisk.index;
}

final class PathComponent {
  PathComponent._(this.kind, this.bytes, this._start, this._end, [this.prefix]);

  final PathComponentKind kind;
  final Uint8List bytes;
  final int _start;
  final int _end;
  final WindowsPrefix? prefix;

  @override
  bool operator ==(Object other) {
    if (other is! PathComponent || other.kind != kind) return false;
    final p = prefix;
    final q = other.prefix;
    if (p != null && q != null) {
      return p.kind == q.kind &&
          p.drive == q.drive &&
          _sameBytes(p.first, q.first) &&
          _sameBytes(p.second, q.second);
    }
    return kind == PathComponentKind.root || _sameBytes(bytes, other.bytes);
  }

  @override
  int get hashCode {
    final p = prefix;
    if (p != null) {
      return Object.hash(
        kind,
        p.kind,
        p.drive,
        Object.hashAll(p.first ?? const []),
        Object.hashAll(p.second ?? const []),
      );
    }
    return kind == PathComponentKind.root
        ? kind.hashCode
        : Object.hash(kind, Object.hashAll(bytes));
  }
}

bool _sameBytes(List<int>? a, List<int>? b) {
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// A path with Rust-style components and access to the original OS bytes.
///
/// On Windows the bytes use WTF-8. On POSIX paths may contain arbitrary bytes.
final class MetaPath {
  factory MetaPath(String path, {PathStyle style = PathStyle.posix}) =>
      MetaPath._(
        style == PathStyle.windows
            ? _encodeWtf8(path)
            : Uint8List.fromList(utf8.encode(path)),
        style,
      );

  factory MetaPath.fromBytes(
    List<int> bytes, {
    PathStyle style = PathStyle.posix,
  }) {
    for (final byte in bytes) {
      RangeError.checkValueInInterval(byte, 0, 255, 'byte');
    }
    return MetaPath._(Uint8List.fromList(bytes), style);
  }

  MetaPath._(Uint8List bytes, this.style) : bytes = bytes.asUnmodifiableView();

  final PathStyle style;
  final Uint8List bytes;
  late final WindowsPrefix? windowsPrefix = style == PathStyle.windows
      ? _parsePrefix()
      : null;
  late final List<PathComponent> components = List.unmodifiable(
    _parseComponents(),
  );
  int get bodyStart => windowsPrefix?._end ?? 0;
  bool get _physicalRoot =>
      bodyStart < bytes.length && _isSeparator(bytes[bodyStart]);
  bool get hasRoot =>
      _physicalRoot ||
      (windowsPrefix != null && windowsPrefix!.kind != WindowsPrefixKind.disk);
  bool get isAbsolute =>
      hasRoot && (style == PathStyle.posix || windowsPrefix != null);
  bool get isEmpty => bytes.isEmpty;

  bool isHashSeparator(int byte) {
    return windowsPrefix?.isVerbatim == true ? byte == 92 : _isSeparator(byte);
  }

  bool _isSeparator(int byte) =>
      byte == 47 || (style == PathStyle.windows && byte == 92);

  Uint8List _slice(int start, int end) =>
      Uint8List.sublistView(bytes, start, end).asUnmodifiableView();

  MetaPath slice(int start, [int? end]) =>
      MetaPath._(_slice(start, end ?? bytes.length), style);

  PathComponent? get _last => components.isEmpty ? null : components.last;
  MetaPath? get name => _last?.kind == PathComponentKind.normal
      ? slice(_last!._start, _last!._end)
      : null;

  MetaPath? get stem {
    final name = this.name;
    if (name == null) return null;
    final dot = name.bytes.lastIndexOf(46);
    return dot > 0 ? name.slice(0, dot) : name;
  }

  MetaPath? get extension {
    final name = this.name;
    if (name == null) return null;
    final dot = name.bytes.lastIndexOf(46);
    return dot > 0 ? name.slice(dot + 1) : null;
  }

  MetaPath? get parent {
    final last = _last;
    if (last == null ||
        last.kind == PathComponentKind.root ||
        last.kind == PathComponentKind.prefix) {
      return null;
    }
    return slice(
      0,
      components.length < 2 ? 0 : components[components.length - 2]._end,
    );
  }

  MetaPath trimAfterName() {
    final last = _last;
    return last?.kind == PathComponentKind.normal ? slice(0, last!._end) : this;
  }

  bool startsWith(MetaPath base) => _matches(base, 0);

  bool endsWith(MetaPath child) =>
      _matches(child, components.length - child.components.length);

  bool _matches(MetaPath other, int offset) {
    if (style != other.style ||
        offset < 0 ||
        components.length < offset + other.components.length) {
      return false;
    }
    for (var i = 0; i < other.components.length; i++) {
      if (components[i + offset] != other.components[i]) return false;
    }
    return true;
  }

  MetaPath? stripPrefix(MetaPath base) =>
      startsWith(base) ? _suffixAfter(base.components.length) : null;

  MetaPath lastComponents(int count) {
    RangeError.checkValueInInterval(count, 0, components.length, 'count');
    return _suffixAfter(components.length - count);
  }

  MetaPath _suffixAfter(int count) {
    if (count == components.length) return slice(0, 0);
    final start = components[count];
    final end = components.last._end;
    return slice(start._start, end);
  }

  MetaPath join(MetaPath child) {
    if (style != child.style) throw ArgumentError('Path styles must match');
    if (child.isAbsolute || child.windowsPrefix != null || isEmpty) {
      return child;
    }
    if (windowsPrefix?.isVerbatim == true && !child.isEmpty) {
      return _joinVerbatim(child);
    }
    if (child.hasRoot) return _concatenate(slice(0, bodyStart), child);
    final driveOnly =
        bodyStart == bytes.length &&
        windowsPrefix?.kind == WindowsPrefixKind.disk;
    final separator = !driveOnly && !_isSeparator(bytes.last);
    return _concatenate(this, child, separator: separator);
  }

  MetaPath _joinVerbatim(MetaPath child) {
    final joined = components.toList();
    for (final component in child.components) {
      switch (component.kind) {
        case PathComponentKind.root:
          joined.removeRange(1, joined.length);
          joined.add(component);
        case PathComponentKind.current:
          break;
        case PathComponentKind.parent:
          if (joined.last.kind == PathComponentKind.normal) joined.removeLast();
        default:
          joined.add(component);
      }
    }
    final bytes = BytesBuilder(copy: false);
    var needsSeparator = false;
    for (final component in joined) {
      final root = component.kind == PathComponentKind.root;
      if (root || needsSeparator) bytes.addByte(92);
      if (!root) bytes.add(component.bytes);
      needsSeparator = !root;
    }
    return MetaPath._(bytes.takeBytes(), style);
  }

  MetaPath _concatenate(MetaPath a, MetaPath b, {bool separator = false}) =>
      MetaPath._(
        Uint8List.fromList([
          ...a.bytes,
          if (separator) style == PathStyle.windows ? 92 : 47,
          ...b.bytes,
        ]),
        style,
      );

  Iterable<PathComponent> _parseComponents() sync* {
    final prefix = windowsPrefix;
    if (prefix != null) {
      yield PathComponent._(
        PathComponentKind.prefix,
        _slice(0, bodyStart),
        0,
        bodyStart,
        prefix,
      );
    }
    var start = bodyStart;
    if (_physicalRoot || (hasRoot && !(prefix?.isVerbatim ?? false))) {
      final end = _physicalRoot ? start + 1 : start;
      yield PathComponent._(
        PathComponentKind.root,
        _slice(start, end),
        start,
        end,
      );
      start = end;
    }

    while (start < bytes.length) {
      var end = start;
      while (end < bytes.length && !isHashSeparator(bytes[end])) {
        end++;
      }
      if (end > start) {
        final dot = bytes[start] == 46 && end == start + 1;
        final dotDot =
            end == start + 2 && bytes[start] == 46 && bytes[start + 1] == 46;
        if (!dot ||
            (!hasRoot && start == bodyStart) ||
            (prefix?.isVerbatim ?? false)) {
          final kind = dot
              ? PathComponentKind.current
              : dotDot
              ? PathComponentKind.parent
              : PathComponentKind.normal;
          yield PathComponent._(kind, _slice(start, end), start, end);
        }
      }
      start = end + 1;
    }
  }

  WindowsPrefix? _parsePrefix() {
    bool sep(int byte) => byte == 47 || byte == 92;
    int? driveAt(int start) {
      if (bytes.length < start + 2 || bytes[start + 1] != 58) return null;
      final upper = bytes[start] & ~32;
      return upper >= 65 && upper <= 90 ? upper : null;
    }

    int endOf(int start, {required bool verbatim}) {
      var end = start;
      while (end < bytes.length &&
          !(verbatim ? bytes[end] == 92 : sep(bytes[end]))) {
        end++;
      }
      return end;
    }

    if (bytes.length < 2 || !sep(bytes[0]) || !sep(bytes[1])) {
      final drive = driveAt(0);
      return drive == null
          ? null
          : WindowsPrefix._(WindowsPrefixKind.disk, 2, drive: drive);
    }

    final verbatim =
        bytes.length >= 4 &&
        bytes[0] == 92 &&
        bytes[1] == 92 &&
        bytes[2] == 63 &&
        bytes[3] == 92;
    final device = bytes.length >= 4 && bytes[2] == 46 && sep(bytes[3]);
    final verbatimUnc =
        verbatim &&
        bytes.length >= 8 &&
        bytes[4] == 85 &&
        bytes[5] == 78 &&
        bytes[6] == 67 &&
        sep(bytes[7]);
    if (verbatim && !verbatimUnc) {
      final drive = driveAt(4);
      if (drive != null && (bytes.length == 6 || sep(bytes[6]))) {
        return WindowsPrefix._(WindowsPrefixKind.verbatimDisk, 6, drive: drive);
      }
      final end = endOf(4, verbatim: true);
      return WindowsPrefix._(
        WindowsPrefixKind.verbatim,
        end,
        first: _slice(4, end),
      );
    }
    if (device) {
      final end = endOf(4, verbatim: false);
      return WindowsPrefix._(
        WindowsPrefixKind.device,
        end,
        first: _slice(4, end),
      );
    }
    final serverStart = verbatimUnc ? 8 : 2;
    final serverEnd = endOf(serverStart, verbatim: verbatim);
    final shareStart = serverEnd == bytes.length ? serverEnd : serverEnd + 1;
    final shareEnd = endOf(shareStart, verbatim: verbatim);
    if (!verbatim && (serverEnd == serverStart || shareEnd == shareStart))
      return null;
    return WindowsPrefix._(
      verbatimUnc ? WindowsPrefixKind.verbatimUnc : WindowsPrefixKind.unc,
      shareEnd == shareStart ? serverEnd : shareEnd,
      first: _slice(serverStart, serverEnd),
      second: _slice(shareStart, shareEnd),
    );
  }

  /// Decodes a Unicode path, replacing invalid POSIX sequences by default.
  String text({bool allowMalformed = true}) => style == PathStyle.windows
      ? _decodeWtf8(bytes, allowMalformed: allowMalformed)
      : _decodeUtf8(bytes, allowMalformed: allowMalformed);

  @override
  String toString() => text();

  @override
  bool operator ==(Object other) =>
      other is MetaPath &&
      components.length == other.components.length &&
      startsWith(other);

  @override
  int get hashCode => Object.hash(style, Object.hashAll(components));
}

Uint8List _encodeWtf8(String text) {
  final bytes = BytesBuilder(copy: false);
  var start = 0;
  final units = text.codeUnits;
  for (var i = 0; i < units.length; i++) {
    final unit = units[i];
    if (unit < 0xd800 || unit > 0xdfff) continue;
    if (unit < 0xdc00 &&
        i + 1 < units.length &&
        units[i + 1] >= 0xdc00 &&
        units[i + 1] <= 0xdfff) {
      i++;
      continue;
    }
    bytes.add(utf8.encode(text.substring(start, i)));
    bytes.add([
      0xe0 | unit >> 12,
      0x80 | ((unit >> 6) & 63),
      0x80 | (unit & 63),
    ]);
    start = i + 1;
  }
  bytes.add(utf8.encode(text.substring(start)));
  return bytes.takeBytes();
}

String _decodeWtf8(Uint8List bytes, {required bool allowMalformed}) {
  final text = StringBuffer();
  var start = 0;
  for (var i = 0; i + 2 < bytes.length; i++) {
    final second = bytes[i + 1];
    final third = bytes[i + 2];
    if (bytes[i] != 0xed ||
        second < 0xa0 ||
        second > 0xbf ||
        third < 0x80 ||
        third > 0xbf)
      continue;
    text.write(
      _decodeUtf8(
        Uint8List.sublistView(bytes, start, i),
        allowMalformed: allowMalformed,
      ),
    );
    text.writeCharCode(0xd000 | ((second & 63) << 6) | (third & 63));
    i += 2;
    start = i + 1;
  }
  text.write(
    _decodeUtf8(
      Uint8List.sublistView(bytes, start),
      allowMalformed: allowMalformed,
    ),
  );
  return text.toString();
}

String _decodeUtf8(Uint8List bytes, {required bool allowMalformed}) {
  final decoded = utf8.decode(bytes, allowMalformed: allowMalformed);
  // Dart's UTF-8 decoder consumes a leading BOM. Paths treat it as a character.
  final hasBom =
      bytes.length >= 3 &&
      bytes[0] == 0xef &&
      bytes[1] == 0xbb &&
      bytes[2] == 0xbf;
  return hasBom ? '\uFEFF$decoded' : decoded;
}
