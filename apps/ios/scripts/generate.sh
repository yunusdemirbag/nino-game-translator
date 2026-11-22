#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Nino contributors
# Xcode projesini üretir. NINO_CORE verilmezse deponun core/ klasörü, o yoksa ~/Desktop/NinoCore kullanılır.
set -e
cd "$(dirname "$0")/.."
if [ -z "${NINO_CORE:-}" ]; then
  if [ -f ../../core/Package.swift ]; then NINO_CORE="$(cd ../../core && pwd)"; else NINO_CORE="$HOME/Desktop/NinoCore"; fi
fi
export NINO_CORE
[ -f "$NINO_CORE/Package.swift" ] || { echo "NinoCore bulunamadı: $NINO_CORE" >&2; exit 1; }
xcodegen generate
