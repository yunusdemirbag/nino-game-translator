#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Nino contributors
# Nino Linux imajını derler (depo kökünden ya da herhangi bir yerden):
#   ./apps/linux/build.sh            → nino-linux imajı
#   docker compose -f apps/linux/compose.yml up -d
set -e
cd "$(dirname "$0")/../.."
# chiaki-ng v1.10.1 kaynağı (resmî depodan, alt modülleriyle); NinoCore'un Remote Play kaynaklarıyla aynı yer.
chiaki=core/NinoRemotePlay/Vendor/chiaki-ng
[ -d "$chiaki/.git" ] || git clone -q --depth 1 --branch v1.10.1 --recurse-submodules --shallow-submodules \
  https://github.com/streetpea/chiaki-ng.git "$chiaki"
docker build -f apps/linux/Dockerfile -t nino-linux "$@" .
