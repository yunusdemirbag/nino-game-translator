#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Nino contributors
#
# Gerçek Tesseract ile okuma denemesi: depodaki GTA 6 kareleri (testdata/gta6/gta6-*.jpg) yeni
# sunucunun `--read-raw` komutuyla okunur ve eski sunucunun çıktısıyla (gta6-beklenen.txt) satır satır karşılaştırılır.
# Gerekenler: libtesseract + eng verisi; Mac'te `sips` (Linux'ta ffmpeg ile çevirin). Önce derleyin:
#   ~/.dotnet/dotnet build apps/linux/src/Nino.Linux
# Mac'te Homebrew'un Tesseract'ı kendiliğinden bulunur (brew install tesseract).
set -e
if [ -f /opt/homebrew/lib/libtesseract.dylib ]; then
  export NINO_TESSERACT_LIBRARY="${NINO_TESSERACT_LIBRARY:-/opt/homebrew/lib/libtesseract.dylib}"
  export TESSDATA_PREFIX="${TESSDATA_PREFIX:-/opt/homebrew/share/tessdata}"
fi
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
dll="$root/apps/linux/src/Nino.Linux/bin/Debug/net10.0/nino.dll"
dotnet="${DOTNET:-$HOME/.dotnet/dotnet}"
for jpg in "$root"/testdata/gta6/gta6-*.jpg; do
  name="$(basename "$jpg" .jpg)"
  if command -v sips >/dev/null; then
    sips -s format bmp "$jpg" --out "$work/$name.bmp" >/dev/null
    size="$(python3 -I "$here/tobgra.py" "$work/$name.bmp" "$work/$name.bgra")"
  else
    size="$(ffprobe -v error -show_entries stream=width,height -of csv=p=0:s=' ' "$jpg")"
    ffmpeg -v error -i "$jpg" -pix_fmt bgra -f rawvideo "$work/$name.bgra"
  fi
  NINO_DATA="$work/data" "$dotnet" "$dll" --read-raw "$work/$name.bgra" $size 2>/dev/null \
    | sed -n -e "s/^  okunan > /$name	satır	/p" -e "s/^  altyazı > /$name	altyazı	/p" >> "$work/yeni.txt"
done
grep -v '^#' "$here/gta6-beklenen.txt" > "$work/eski.txt"
if diff -u "$work/eski.txt" "$work/yeni.txt"; then
  echo "aynı: $(cut -f1 "$work/eski.txt" | sort -u | wc -l | tr -d ' ') kare"
else
  echo "FARK VAR"; exit 1
fi
