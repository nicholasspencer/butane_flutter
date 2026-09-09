#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../packages/butane_platform_interface"

portable_input="$(mktemp "${TMPDIR:-/tmp}/butane_api_portable.XXXXXX")"
cpp_input="$(mktemp "${TMPDIR:-/tmp}/butane_api_cpp.XXXXXX")"
trap 'rm -f "$portable_input" "$cpp_input"' EXIT

perl -0pe 's/\@ConfigurePigeon\(\s*PigeonOptions\(.*?\),\s*\)\s*(?=enum ClientState)//s' \
  pigeons/api.dart > "$portable_input"
# C++ reserves `result` for the async reply callback, so avoid that collision
# only in its flattened generator input.
perl -0pe 's/sealed class (?:Session|AttributeData) \{\}\s*//g; s/class (ClientSession|PeripheralSession|PeripheralManagerSession) extends Session/class $1/g; s/class (Service|Characteristic|Descriptor) extends AttributeData/class $1/g; s/required AttResult result/required AttResult requestResult/g' \
  pigeons/api.dart > "$cpp_input"

dart run pigeon \
  --input "$portable_input" \
  --dart_out lib/src/channels/api.g.dart \
  --swift_out ../butane_core_bluetooth/darwin/Classes/Api.gen.swift \
  --kotlin_out ../butane_android/android/src/main/kotlin/com/nicospencer/butane_android/Api.gen.kt

dart format lib/src/channels/api.g.dart

dart run pigeon \
  --input "$cpp_input" \
  --cpp_header_out ../butane_windows/windows/Api.gen.h \
  --cpp_source_out ../butane_windows/windows/Api.gen.cpp \
  --cpp_namespace butane_windows

# Pigeon 26's C++ output needs a forward declaration for this later value type,
# and its ConnectionState method otherwise hides the enum in callback types.
perl -0pi -e 's/(?=class Characteristic \{)/class CharacteristicProperty;\n\n/; s/ErrorOr<ConnectionState>/ErrorOr<::butane_windows::ConnectionState>/g' \
  ../butane_windows/windows/Api.gen.h \
  ../butane_windows/windows/Api.gen.cpp
