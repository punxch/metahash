# metahashdart

用 Dart 实现 Rust metahash 的 XXH3-128、路径、URL 和元数据哈希。CLI 通过 `dart:ffi` 读取系统文件元数据，无需第三方 Dart 包、额外原生组件或元数据输入。

## 使用

在项目目录运行以下命令。输出为与 Rust CLI 相同格式的小写十六进制哈希。

```sh
dart run bin/metahash.dart path/to/file --skip 42
dart compile exe bin/metahash.dart
```

支持文件、目录和指向它们的符号链接。`--skip` 默认为 0，范围与 Rust 目标平台的 `usize` 一致。

```dart
import 'package:metahashdart/metahash.dart';

void main() {
  final file = MetaFile.fromPath('path/to/file');
  print(file.hashHex(skip: BigInt.from(42)));
}
```

`MetaFile.fromPath` 解析规范路径并读取元数据。`MetaFile.fromUrl` 保留传入的本地 URL。`MetaFile.fromOsPath` 接受原始路径字节，可用于 POSIX 上的非 UTF-8 路径。Dart 的不可变值类型统一表示 Rust 的借用和拥有形式。

## 兼容性

- Windows 通过 Win32 文件句柄读取大小、创建和修改时间，保留 FILETIME 的 100 纳秒精度。
- Linux 使用 `statx` 读取纳秒级元数据，并在 x64 和 arm64 上支持 `stat64` 回退。macOS x64 和 arm64 使用 Darwin 的 64 位 inode 布局。
- Rust 的路径和时间编码依赖操作系统、指针宽度和字节序。文件 API 默认使用当前平台的布局。
- Windows x64 已与 Rust 实跑对照。Ubuntu 24.04 的 x64 和 arm64 各通过 20 组，macOS 15 的 x64 和 arm64 各通过 19 组。每组的原生元数据字段和最终哈希均与 Rust 一致。 [Linux 和 macOS 验证记录](https://github.com/punxch/metahash/actions/runs/43168845719)

## 验证

```sh
dart analyze
dart run test/xxh3_test.dart
dart run test/hash_test.dart
dart run test/url_test.dart
dart run test/support_types_test.dart
```

在仓库根目录构建 Rust CLI 和元数据参考程序，再从 Dart 项目目录运行原生对照。Windows 下使用相应的 `.exe` 路径。

```sh
cargo build --bin metahash --example native_reference
cd metahashdart
dart run test/native_test.dart ../target/debug/metahash ../target/debug/examples/native_reference
```

测试让两种实现读取同一批临时文件、目录和符号链接，逐项比较规范路径字节、文件大小、创建时间、状态变更时间、修改时间和最终哈希。只传第一个参数时对照两个 CLI 的哈希。省略两个参数时运行 Dart 自检。
