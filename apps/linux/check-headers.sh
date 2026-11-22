#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Nino contributors
# Denetim: apps/linux altındaki her kaynak dosyada lisans ve telif satırı var mı, eski koda bağımlılık ya da
# eski projenin adı var mı. Sorun yoksa çıkış 0.
set -e
cd "$(dirname "$0")"
status=0
for file in $(git ls-files --cached --others --exclude-standard | grep -E '\.(cs|csproj|props|slnx|html|sh|yml|md|py)$|Dockerfile$|\.gitignore$'); do
  grep -q "SPDX-License-Identifier: AGPL-3.0-only" "$file" || { echo "lisans satırı yok: $file"; status=1; }
  grep -q "Copyright (C) 2026 Nino contributors" "$file" || { echo "telif satırı yok: $file"; status=1; }
done
# src/Nino.Linux'tan depo köküne 4 basamak: oradaki eski linux/ ve windows/ yasak; apps/windows (yeni çekirdek) serbest.
if grep -rnE '(\.\.[/\\]){4}(linux|windows)[/\\]' --include='*.csproj' --include='*.props' . ; then
  echo "eski linux/ ya da windows/ klasörüne bağımlılık var"; status=1
fi
if grep -rniE "$(printf 'c%sch' 'ou')" . --exclude-dir=bin --exclude-dir=obj; then
  echo "eski projenin adı geçiyor"; status=1
fi
python3 ./copy-audit.py || { echo "eski koddan kalan satır ya da metin var"; status=1; }
python3 ./text-audit.py >/dev/null 2>&1 || { python3 ./text-audit.py; echo "kullanıcı metni eski metinlerle örtüşüyor"; status=1; }
exit $status
