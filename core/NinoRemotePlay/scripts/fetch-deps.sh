#!/bin/zsh
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Nino contributors
#
# Remote Play için gereken üçüncü taraf kaynakları resmî depolarından,
# sabit sürümleriyle Vendor/ altına indirir. Var olanı yeniden indirmez.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Vendor

fetch() { # ad depo etiket
  local name=$1 repo=$2 tag=$3
  if [[ -d Vendor/$name/.git ]]; then
    echo "$name: zaten var ($(git -C Vendor/$name describe --tags 2>/dev/null || git -C Vendor/$name rev-parse --short HEAD))"
    return
  fi
  echo "$name: $tag indiriliyor"
  git clone -q --depth 1 --branch $tag --recurse-submodules --shallow-submodules $repo Vendor/$name
}

fetch chiaki-ng https://github.com/streetpea/chiaki-ng.git v1.10.1
fetch openssl   https://github.com/openssl/openssl.git    openssl-3.5.9
fetch json-c    https://github.com/json-c/json-c.git      json-c-0.19-20260627
fetch libevent  https://github.com/libevent/libevent.git  release-2.1.13-stable
fetch miniupnp  https://github.com/miniupnp/miniupnp.git  miniupnpc_2_3_5

echo
for d in Vendor/*/; do
  printf "%-12s %s\n" "$(basename $d)" "$(git -C $d rev-parse HEAD)"
done
