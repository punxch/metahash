import 'dart:typed_data';

import 'path.dart';

/// The path and its URI and URN suffix lengths, measured in OS bytes.
final class Loc {
  factory Loc(MetaPath path) {
    final trimmed = path.trimAfterName();
    final name = trimmed.name;
    final length = name?.bytes.length;
    return Loc._(trimmed, length ?? trimmed.bytes.length, length ?? 0);
  }

  factory Loc.withBase(MetaPath path, MetaPath base, MetaPath trail) {
    final loc = Loc(path);
    return Loc._(
      loc.path,
      _relativeLength(loc.path, base),
      _relativeLength(loc.path, trail),
    );
  }

  factory Loc.withComponents(MetaPath path, int uri, int urn) {
    if (urn < 0 || uri < urn) {
      throw ArgumentError('URI and URN must satisfy 0 <= URN <= URI');
    }
    final loc = Loc(path);
    return Loc._(
      loc.path,
      loc.path.lastComponents(uri).bytes.length,
      loc.path.lastComponents(urn).bytes.length,
    );
  }

  factory Loc.zeroed(MetaPath path) => Loc._(path.trimAfterName(), 0, 0);

  factory Loc.floated(MetaPath path, MetaPath base) {
    final loc = Loc(path);
    return Loc._(loc.path, _relativeLength(loc.path, base), loc.urnLength);
  }

  const Loc._(this.path, this.uriLength, this.urnLength);

  final MetaPath path;
  final int uriLength;
  final int urnLength;

  Uint8List get bytes => path.bytes;
  int get _baseEnd => bytes.length - uriLength;
  int get _trailEnd => bytes.length - urnLength;
  UriPath get uri => UriPath(path.slice(_baseEnd));
  Urn get urn => Urn(path.slice(_trailEnd));
  Urn get base => Urn(path.slice(0, _baseEnd));
  Urn get trail => Urn(path.slice(0, _trailEnd));
  bool get hasBase => _baseEnd != 0;
  bool get hasTrail => _trailEnd != 0;
  MetaPath? get name => path.name;
  MetaPath? get stem => path.stem;
  MetaPath? get extension => path.extension;
  MetaPath? get parent => path.parent;
  (MetaPath, MetaPath, MetaPath) get triple =>
      (base.path, path.slice(_baseEnd, _trailEnd), urn.path);

  MetaPath? stripPrefix(MetaPath base) => path.stripPrefix(base);

  static int _relativeLength(MetaPath path, MetaPath base) =>
      path.stripPrefix(base)?.bytes.length ??
      (throw ArgumentError('Location must start with the given base or trail'));

  @override
  bool operator ==(Object other) => other is Loc && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

final class UriPath {
  const UriPath(this.path);

  final MetaPath path;
  int get count => path.components.length;
  bool get isEmpty => path.isEmpty;

  PathComponent? nth(int index) =>
      index >= 0 && index < count ? path.components[index] : null;

  @override
  bool operator ==(Object other) => other is UriPath && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

final class Urn {
  const Urn(this.path);

  final MetaPath path;
  MetaPath? get name => path.name;
  int get count => path.components.length;
  Uint8List get encodedBytes => path.bytes;
  bool get isHidden => path.style == PathStyle.posix && name?.bytes.first == 46;

  @override
  bool operator ==(Object other) => other is Urn && other.path == path;

  @override
  int get hashCode => path.hashCode;
}
