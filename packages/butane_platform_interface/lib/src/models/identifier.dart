part of '../interface.dart';

sealed class Identifier {
  const Identifier(this.value);

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

class UuidIdentifier extends Identifier {
  const UuidIdentifier(String super.value);
}

class StringIdentifier extends Identifier {
  const StringIdentifier(String super.value);
}

class MacAddressIdentifier extends Identifier {
  const MacAddressIdentifier(MacAddress super.value);
}
