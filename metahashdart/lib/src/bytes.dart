import 'dart:convert';

String decodeUtf8(List<int> bytes, {bool allowMalformed = false}) {
  final decoded = utf8.decode(bytes, allowMalformed: allowMalformed);
  // OS paths and Rust strings preserve U+FEFF as an ordinary character.
  final hasBom =
      bytes.length >= 3 &&
      bytes[0] == 0xef &&
      bytes[1] == 0xbb &&
      bytes[2] == 0xbf;
  return hasBom ? '\uFEFF$decoded' : decoded;
}
