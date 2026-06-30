part of '../porcelain.dart';

class MacAddress {
  const MacAddress(this._bytes);

  final Uint8List _bytes;

  factory MacAddress.fromString(String macString) {
    // Remove any delimiter characters (e.g., colons or dashes) and convert to uppercase
    macString = macString.replaceAll(RegExp(r'[:-]'), '').toUpperCase();

    if (macString.length != 12 || macString.contains(RegExp(r'[^0-9A-F]'))) {
      throw FormatException('Invalid MAC address format: $macString');
    }

    final List<int> byteValues = [];

    for (var i = 0; i < 12; i += 2) {
      final hexByte = macString.substring(i, i + 2);
      final byteValue = int.parse(hexByte, radix: 16);
      byteValues.add(byteValue);
    }

    final bytes = Uint8List.fromList(byteValues);
    return MacAddress(bytes);
  }

  @override
  String toString() {
    final hexBytes =
        _bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0'));
    return hexBytes.join(':');
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is MacAddress && _listEquals(other._bytes, _bytes);
  }

  @override
  int get hashCode => _bytes.hashCode;

  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;

    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }

    return true;
  }
}
