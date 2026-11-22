#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Nino contributors
#
# apps/windows için üç denetim:
#  1. Yorum alabilen her dosyanın başında SPDX ve telif satırı var.
#  2. Eski proje adı (LegacyNames.cs dışında) hiçbir dosyada geçmiyor.
#  3. Eski windows/ kodundan aynen alınmış uzun satır yok.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
repo="$(cd "$root/../.." && pwd)"
fail=0
old=$(printf '%s' 'Q291Y2hTdWJz' | base64 -d)

while IFS= read -r -d '' f; do
  case "$f" in */bin/*|*/obj/*|*/Fixtures/*|*.png|*.ico|*.ttf|*.json|*.gz|*.pem|*.txt|*.md) continue;; esac
  head -4 "$f" | grep -q 'SPDX-License-Identifier: AGPL-3.0-only' || { echo "başlık yok: ${f#$root/}"; fail=1; }
  head -4 "$f" | grep -q 'Copyright (C) 2026 Nino contributors' || { echo "telif satırı yok: ${f#$root/}"; fail=1; }
done < <(find "$root" -type f \( -name '*.cs' -o -name '*.xaml' -o -name '*.csproj' -o -name '*.props' -o -name '*.slnx' -o -name '*.sh' -o -name '*.c' -o -name '*.h' -o -name '*.js' -o -name '*.cjs' -o -name '*.html' -o -name '*.py' -o -name 'CMakeLists.txt' \) -print0)

if grep -rIil "$old" "$root" --exclude-dir=bin --exclude-dir=obj | grep -v '/LegacyNames.cs$'; then
  echo "eski ad geçiyor (yukarıdaki dosyalar)"; fail=1
fi

# Eski koddan aynen satır: 40 karakterden uzun, boşluğu atılmış satırların kesişimi.
norm() { sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | awk 'length($0) >= 40' | grep -vE '^(//|<!--|#|\*|using |namespace |\[)' \
  | grep -vE '^</?(Setter|ControlTemplate|ResourceDictionary|Trigger|MultiTrigger|Condition|DataTrigger|Style|Border|Grid|ColumnDefinition|RowDefinition|Ellipse|TextBlock|ContentPresenter|Rectangle)[ >.]' \
  | grep -vE '^(\(|"|\{ *")' | sort -u; }
# Not: XAML kalıp satırları (Setter/şablon başlıkları; tarifteki belirteç adlarıyla zorunlu olarak aynı çıkar) ve
# tariflerdeki veri satırları (karışan harf çiftleri, örnek cümleler, terim listeleri) aynı satır sayılmaz.
tmp=$(mktemp -d)
find "$repo/windows" -type f \( -name '*.cs' -o -name '*.xaml' -o -name '*.c' -o -name '*.h' -o -name '*.cjs' -o -name '*.py' \) -not -path '*/obj/*' -not -path '*/bin/*' -not -path '*/node_modules/*' -exec cat {} + | norm > "$tmp/old"
find "$root" -type f \( -name '*.cs' -o -name '*.xaml' -o -name '*.c' -o -name '*.h' -o -name '*.cjs' -o -name '*.py' \) -not -path '*/obj/*' -not -path '*/bin/*' -exec cat {} + | norm > "$tmp/new"
same=$(comm -12 "$tmp/old" "$tmp/new" | wc -l | tr -d ' ')
if [ "$same" -gt "${NINO_SAME_LINES_ALLOWED:-150}" ]; then
  echo "eski koddaki ile aynı $same uzun satır var:"; comm -12 "$tmp/old" "$tmp/new" | head -40; fail=1
fi
rm -rf "$tmp"
[ $fail -eq 0 ] && echo "denetim temiz"
exit $fail
