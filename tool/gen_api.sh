#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../packages/butane_platform_interface"

dart run pigeon \
  --input pigeons/api.dart \
  --dart_out lib/src/channels/api.g.dart \
  --swift_out ../butane_core_bluetooth/darwin/Classes/Api.gen.swift \
  --kotlin_out ../butane_android/android/src/main/kotlin/com/nicospencer/butane_android/Api.gen.kt \
  --cpp_header_out ../butane_windows/windows/Api.gen.h \
  --cpp_source_out ../butane_windows/windows/Api.gen.cpp \
  --cpp_namespace butane_windows
