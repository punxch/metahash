import 'dart:convert';
import 'dart:typed_data';

import 'bytes.dart';
import 'location.dart';
import 'path.dart';

// Variant order is part of Rust's derived Hash representation.
enum SchemeKind { regular, search, archive, sftp }

final class Scheme {
  const Scheme.regular() : this._(SchemeKind.regular, null);
  const Scheme.search(String domain) : this._(SchemeKind.search, domain);
  const Scheme.archive(String domain) : this._(SchemeKind.archive, domain);
  const Scheme.sftp(String domain) : this._(SchemeKind.sftp, domain);
  const Scheme._(this.kind, this.domain);

  final SchemeKind kind;
  final String? domain;

  bool get isVirtual => kind == SchemeKind.archive || kind == SchemeKind.sftp;

  bool covariant(Scheme other) =>
      (!isVirtual && !other.isVirtual) || this == other;

  static SchemeKind parseKind(String text) => switch (text) {
    'regular' => SchemeKind.regular,
    'search' => SchemeKind.search,
    'archive' => SchemeKind.archive,
    'sftp' => SchemeKind.sftp,
    _ => throw FormatException('Could not parse protocol from URL', text),
  };

  @override
  bool operator ==(Object other) =>
      other is Scheme && other.kind == kind && other.domain == domain;

  @override
  int get hashCode => Object.hash(kind, domain);
}

/// An immutable metahash URL. Regular and search URLs refer to local paths.
final class Url {
  const Url(this.loc, [this.scheme = const Scheme.regular()]);
  Url.regular(MetaPath path) : this(Loc(path));

  factory Url.parse(String text, {PathStyle style = PathStyle.posix}) =>
      Url.parseBytes(MetaPath(text, style: style).bytes, style: style);

  /// Parses the schemes and URI/URN component counts used by metahash URLs.
  factory Url.parseBytes(List<int> bytes, {PathStyle style = PathStyle.posix}) {
    final marker = _protocolEnd(bytes);
    if (marker == -1)
      return Url.regular(MetaPath.fromBytes(bytes, style: style));
    final escaped = marker > 0 && bytes[marker - 1] == 126;
    final kind = Scheme.parseKind(
      decodeUtf8(bytes.sublist(0, escaped ? marker - 1 : marker)),
    );
    var start = marker + 3;
    if (kind == SchemeKind.regular) {
      final rest = bytes.sublist(start);
      return Url.regular(
        MetaPath.fromBytes(escaped ? _percentDecode(rest) : rest, style: style),
      );
    }

    final slash = bytes.indexOf(47, start);
    final end = slash == -1 ? bytes.length : slash;
    final authority = bytes.sublist(start, end);
    start = slash == -1 ? end : end + 1;
    final (domain, uri, urn) = _parseAuthority(authority);
    final scheme = switch (kind) {
      SchemeKind.search => Scheme.search(domain),
      SchemeKind.archive => Scheme.archive(domain),
      SchemeKind.sftp => Scheme.sftp(domain),
      SchemeKind.regular => const Scheme.regular(),
    };
    final rest = bytes.sublist(start);
    final path = MetaPath.fromBytes(
      escaped ? _percentDecode(rest) : rest,
      style: style,
    );
    final uriCount = uri ?? (kind == SchemeKind.sftp && !path.isEmpty ? 1 : 0);
    final urnCount =
        urn ?? (kind == SchemeKind.sftp && path.name != null ? 1 : 0);
    if (kind == SchemeKind.search && uriCount != urnCount) {
      throw const FormatException(
        'Search scheme requires URI and URN to be equal',
      );
    }
    return Url(Loc.withComponents(path, uriCount, urnCount), scheme);
  }

  final Loc loc;
  final Scheme scheme;

  bool get isRegular => scheme.kind == SchemeKind.regular;
  bool get isSearch => scheme.kind == SchemeKind.search;
  bool get isArchive => scheme.kind == SchemeKind.archive;
  bool get isAbsolute => scheme.isVirtual ? hasRoot : loc.path.isAbsolute;
  bool get hasRoot => loc.path.hasRoot;
  bool get hasBase => loc.hasBase;
  bool get hasTrail => loc.hasTrail;
  UriPath get uri => loc.uri;
  Urn get urn => loc.urn;
  MetaPath? get name => loc.name;
  MetaPath? get stem => loc.stem;
  MetaPath? get extension => loc.extension;
  MetaPath? get asPath => scheme.isVirtual ? null : loc.path;

  Url intoRegular() => Url.regular(loc.path);

  Urn? stripPrefix(Url base) {
    final prefix = loc.stripPrefix(base.loc.path);
    if (prefix == null) return null;
    if (scheme.covariant(base.scheme)) return Urn(prefix);
    if ((isArchive && uri.isEmpty && !base.scheme.isVirtual) ||
        (base.isArchive && base.uri.isEmpty && !scheme.isVirtual)) {
      return Urn(prefix);
    }
    return null;
  }

  Url? get base => loc.hasBase ? Url(Loc(loc.base.path), scheme) : null;

  Url? get parent {
    final path = loc.parent;
    if (path == null) return null;
    return switch (scheme.kind) {
      SchemeKind.regular => Url.regular(path),
      SchemeKind.search ||
      SchemeKind.archive when uri.isEmpty => Url.regular(path),
      SchemeKind.search => Url(
        Loc.withBase(path, loc.base.path, loc.base.path),
        scheme,
      ),
      SchemeKind.archive when uri.nth(1) == null => Url(
        Loc.zeroed(path),
        scheme,
      ),
      SchemeKind.archive => Url(Loc.floated(path, loc.base.path), scheme),
      SchemeKind.sftp => Url(Loc(path), scheme),
    };
  }

  Url join(MetaPath child) {
    final path = loc.path.join(child);
    final next = switch (scheme.kind) {
      SchemeKind.regular || SchemeKind.sftp => Loc(path),
      SchemeKind.search => Loc.withBase(path, loc.base.path, loc.base.path),
      SchemeKind.archive => Loc.floated(path, loc.base.path),
    };
    return Url(next, scheme);
  }

  bool startsWith(Url base) =>
      scheme.covariant(base.scheme) && loc.path.startsWith(base.loc.path);

  bool endsWith(Url child) =>
      scheme.covariant(child.scheme) && loc.path.endsWith(child.loc.path);

  bool covariant(Url other) =>
      scheme.covariant(other.scheme) && loc == other.loc;

  (Url, Urn)? get pair {
    final parent = this.parent;
    return parent == null ? null : (parent, urn);
  }

  @override
  bool operator ==(Object other) =>
      other is Url &&
      other.loc == loc &&
      other.scheme == scheme &&
      other.loc.uriLength == loc.uriLength &&
      other.loc.urnLength == loc.urnLength;

  @override
  int get hashCode => Object.hash(loc, scheme, loc.uriLength, loc.urnLength);
}

int _protocolEnd(List<int> bytes) {
  for (var i = 0; i + 2 < bytes.length; i++) {
    if (bytes[i] == 58 && bytes[i + 1] == 47 && bytes[i + 2] == 47) return i;
  }
  return -1;
}

(String, int?, int?) _parseAuthority(List<int> bytes) {
  final last = bytes.lastIndexOf(58);
  final previous = last <= 0 ? -1 : bytes.lastIndexOf(58, last - 1);
  int? count(int start, int end) {
    if (start == end) return null;
    final text = ascii.decode(bytes.sublist(start, end));
    if (!RegExp(r'^\+?[0-9]+$').hasMatch(text)) {
      throw FormatException('Invalid URI or URN component count', text);
    }
    return int.parse(text);
  }

  final domainEnd = previous != -1
      ? previous
      : last != -1
      ? last
      : bytes.length;
  final domain = decodeUtf8(_percentDecode(bytes.sublist(0, domainEnd)));
  if (last == -1) return (domain, null, null);
  final finalCount = count(last + 1, bytes.length);
  if (previous == -1) return (domain, finalCount, null);
  return (domain, count(previous + 1, last), finalCount);
}

Uint8List _percentDecode(List<int> bytes) {
  final output = BytesBuilder(copy: false);
  int digit(int b) {
    if (b >= 48 && b <= 57) return b - 48;
    final lower = b | 32;
    return lower >= 97 && lower <= 102 ? lower - 87 : -1;
  }

  for (var i = 0; i < bytes.length; i++) {
    if (bytes[i] == 37 && i + 2 < bytes.length) {
      final a = digit(bytes[i + 1]);
      final b = digit(bytes[i + 2]);
      if (a >= 0 && b >= 0) {
        output.addByte(a * 16 + b);
        i += 2;
        continue;
      }
    }
    output.addByte(bytes[i]);
  }
  return output.takeBytes();
}
