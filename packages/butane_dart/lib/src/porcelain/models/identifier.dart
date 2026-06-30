part of '../porcelain.dart';

sealed class Identifier {
  const Identifier(this.value);

  factory Identifier.parse(String value) {
    return StringIdentifier(value);
  }

  final Object value;

  @override
  String toString() => value.toString();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Identifier &&
          runtimeType == other.runtimeType &&
          value == other.value;

  @override
  int get hashCode => value.hashCode;
}

extension Identifiers on Iterable<Identifier> {
  Iterable<String> toStrings() => map((e) => e.value as String);
}

class UuidIdentifier extends Identifier {
  const UuidIdentifier(String super.value);
}

class StringIdentifier extends Identifier {
  const StringIdentifier(String super.value);
}

class MacAddressIdentifier extends Identifier {
  const MacAddressIdentifier(MacAddress super.value);
}
