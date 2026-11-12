import 'dart:io';

import '../lib/metahash.dart';
import 'hash_test.dart' show expectEqual;

void main() {
  final path = MetaPath('/dir//./sub/中文.tar.gz/./');
  final regular = Url.regular(path);
  expectEqual(regular.name?.text(), '中文.tar.gz', 'Name');
  expectEqual(regular.stem?.text(), '中文.tar', 'Stem');
  expectEqual(regular.extension?.text(), 'gz', 'Extension');
  expectEqual(
    regular.loc.path.text(),
    '/dir//./sub/中文.tar.gz',
    'Trimmed location',
  );
  expectEqual(regular.loc.base.path.text(), '/dir//./sub/', 'Regular base');
  expectEqual(regular.parent?.loc.path, MetaPath('/dir/sub'), 'Regular parent');

  final search = Url.parse('search://term%20one:2:2//dir/sub/中文.tar.gz');
  expectEqual(search.scheme.domain, 'term one', 'Search domain');
  expectEqual(search.uri.count, 2, 'Search URI length');
  expectEqual(search.parent?.uri.path.text(), 'sub', 'Search parent URI');
  expectEqual(search.parent?.parent?.uri.isEmpty, true, 'Search root');
  expectEqual(
    search.parent?.parent?.parent?.isRegular,
    true,
    'Parent outside search',
  );
  expectEqual(regular.covariant(search), true, 'Local covariance');
  expectEqual(
    search.stripPrefix(Url.regular(MetaPath('/dir')))?.count,
    2,
    'Strip local prefix',
  );
  expectEqual(search.join(MetaPath('entry')).uri.count, 3, 'Search join');

  final archive = Url.parse('archive://zip:2:1//dir/archive.zip/inside/entry');
  final root = archive.parent?.parent;
  expectEqual(archive.asPath, null, 'Virtual path');
  expectEqual(archive.parent?.urn.path.text(), 'inside', 'Archive parent');
  expectEqual(root?.isArchive, true, 'Archive root scheme');
  expectEqual(root?.uri.isEmpty, true, 'Archive root URI');
  expectEqual(root?.parent?.isRegular, true, 'Parent outside archive');
  expectEqual(
    root?.stripPrefix(Url.regular(MetaPath('/dir')))?.path.text(),
    'archive.zip',
    'Archive root is a local prefix match',
  );
  expectEqual(
    archive.stripPrefix(Url.regular(MetaPath('/dir'))),
    null,
    'Archive entries are virtual prefix matches',
  );
  expectEqual(
    archive.startsWith(Url.parse('archive://tar//dir')),
    false,
    'Archive domains must match',
  );

  final remote = Url.parse('sftp~://example.test//home/%E4%B8%AD');
  expectEqual(remote.uri.path.text(), '中', 'Escaped remote path');
  expectEqual(remote.pair?.$1.scheme, remote.scheme, 'Remote parent scheme');
  expectEqual(remote.pair?.$2.path.text(), '中', 'Remote pair URN');
  expectEqual(
    remote.covariant(Url.regular(remote.loc.path)),
    false,
    'Remote covariance',
  );
  expectEqual(
    Urn(MetaPath('/tmp/.env')).isHidden,
    true,
    'Hidden POSIX basename',
  );

  MetaPath windows(String text) => MetaPath(text, style: PathStyle.windows);
  expectEqual(
    windows(r'c:/Dir\.\File'),
    windows(r'C:\Dir\File'),
    'Drive and separators',
  );
  expectEqual(
    windows(r'C:\a').join(windows(r'\b')).text(),
    r'C:\b',
    'Rooted Windows join',
  );
  expectEqual(
    windows(r'\\?\c:\a\b').join(windows(r'..\c')).text(),
    r'\\?\c:\a\c',
    'Verbatim Windows join',
  );
  expectEqual(windows('\uFEFFa').text(), '\uFEFFa', 'BOM in a basename');
  final unpaired = String.fromCharCode(0xd800);
  expectEqual(windows(unpaired).bytes.join(','), '237,160,128', 'WTF-8 bytes');
  expectEqual(windows(unpaired).text(), unpaired, 'WTF-8 round trip');
  expectEqual(
    MetaPath.fromBytes([47, 255]).name?.bytes.single,
    255,
    'Raw POSIX path',
  );

  stdout.writeln('Path, location, scheme and URL checks passed.');
}
