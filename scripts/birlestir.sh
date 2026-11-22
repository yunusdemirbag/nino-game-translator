#!/usr/bin/env bash
# Nino 4.5: yeni uygulama dallarını bu dala (nino-4.5-hazir) birleştirir.
# Tekrar çalıştırılabilir: dallara yeni commit geldikçe yeniden çalıştırın; yalnız yeni commit'ler alınır.
# Kullanım: scripts/birlestir.sh            (tüm dallar)
#           scripts/birlestir.sh mac ios    (yalnız adı geçenler; desen: claude/<ad>-*)
# Bilinen çakışmalar kendiliğinden çözülür:
#   .gitignore, .gitattributes  -> iki tarafın satırları birleşir (union)
#   .claude/launch.json         -> iki taraftaki yapılandırmalar ada göre birleşir
# Başka bir çakışmada betik durur; elle çözüp `git commit` deyin ve betiği yeniden çalıştırın.
# Not: bu dalda kaldırılan eski klasörlere (mac/, windows/, tv-webos/, server/, eski docs/ vb.) bir dal yeniden
#   dokunursa "silindi/değişti" çakışması çıkar; o dosya yeni depoda yok, `git rm <dosya>` ile çözün. site/ ve store/
#   bu dalda yeniden yazıldı; bir dalın oradaki değişikliği elle uyarlanmalı.
# Son adım: ~/Desktop/NinoCore deposunun son commit'i core/ klasörüne kopyalanır (NINO_CORE_REPO ile değişir).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# Sıra önemli: linux, windows dalını içerir; yardimci, olcum ve havuz-paketler dallarını içerir
# (nino-pool migration sırası 0016 olaylar → 0017 paketler → 0018 tv bağları → 0019 teşhis → yardımcı).
DEFAULT=(yeni-mac yeni-ios yeni-android yeni-windows yeni-linux yeni-tv-web yeni-androidtv havuz-paketler olcum yardimci)
if [ $# -gt 0 ]; then NAMES=("$@"); else NAMES=("${DEFAULT[@]}"); fi

[ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "Çalışma ağacı temiz değil; önce commit atın." >&2; exit 1; }

resolve_branch() {
  local n=$1 b
  b=$(git for-each-ref --format='%(refname:short)' "refs/heads/claude/$n" "refs/heads/claude/$n-*" | grep -v -- '-hazir' | head -1)
  [ -n "$b" ] || { echo "Dal bulunamadı: claude/$n(-*)" >&2; return 1; }
  echo "$b"
}

union_file() {  # $1 = yol
  local f=$1 t; t=$(mktemp -d)
  git show ":1:$f" >"$t/base" 2>/dev/null || : >"$t/base"
  git show ":2:$f" >"$t/ours"; git show ":3:$f" >"$t/theirs"
  git merge-file --union -p "$t/ours" "$t/base" "$t/theirs" >"$f"
  rm -rf "$t"; git add "$f"
}

merge_launch() {  # .claude/launch.json: yapılandırmaları ada göre birleştir
  local f=.claude/launch.json t; t=$(mktemp -d)
  git show ":2:$f" >"$t/ours"; git show ":3:$f" >"$t/theirs"
  python3 - "$t/ours" "$t/theirs" >"$f" <<'PY'
import json,sys
a=json.load(open(sys.argv[1])); b=json.load(open(sys.argv[2]))
seen={c["name"] for c in a.get("configurations",[])}
for c in b.get("configurations",[]):
    if c["name"] not in seen: a.setdefault("configurations",[]).append(c); seen.add(c["name"])
print(json.dumps(a,indent=2,ensure_ascii=False))
PY
  rm -rf "$t"; git add "$f"
}

for n in "${NAMES[@]}"; do
  b=$(resolve_branch "$n")
  if git merge-base --is-ancestor "$b" HEAD; then echo "= $b: yeni commit yok"; continue; fi
  echo "+ $b: $(git rev-list --count HEAD.."$b") yeni commit"
  if git merge --no-ff --no-edit -m "Birleştir: $b" "$b" >/dev/null 2>&1; then continue; fi
  rest=()
  for f in $(git diff --name-only --diff-filter=U); do
    case "$f" in
      .gitignore|.gitattributes|*/.gitignore) union_file "$f" ;;
      .claude/launch.json) merge_launch ;;
      *) rest+=("$f") ;;
    esac
  done
  if [ ${#rest[@]} -gt 0 ] 2>/dev/null && [ -n "${rest[*]:-}" ]; then
    echo "Elle çözülmesi gereken çakışmalar ($b):" >&2; printf '  %s\n' "${rest[@]:-}" >&2; exit 2
  fi
  git commit --no-edit -q
done

# NinoCore (ayrı yerel depo) core/ klasörüne eşitlenir: yalnız izlenen dosyaları, son commit'i (Vendor indirilen kaynaktır, girmez).
NINO_CORE_REPO=${NINO_CORE_REPO:-$HOME/Desktop/NinoCore}
if [ -d "$NINO_CORE_REPO/.git" ]; then
  [ -z "$(git -C "$NINO_CORE_REPO" status --porcelain --untracked-files=no)" ] || echo "UYARI: NinoCore'da commit'lenmemiş değişiklik var; yalnız son commit alınır." >&2
  sha=$(git -C "$NINO_CORE_REPO" rev-parse --short HEAD)
  git ls-files -z core | xargs -0 git rm -q --cached --ignore-unmatch >/dev/null 2>&1 || true
  git ls-files -z core | xargs -0 rm -f 2>/dev/null || true
  find core -type f ! -path 'core/NinoRemotePlay/Vendor/*' ! -path 'core/NinoRemotePlay/.*' ! -path 'core/.build/*' -delete 2>/dev/null || true
  mkdir -p core && git -C "$NINO_CORE_REPO" archive HEAD | tar -x -C core
  git add -A core
  if git diff --cached --quiet -- core; then echo "= NinoCore $sha: değişiklik yok"
  else git commit -q -m "NinoCore $sha core/ klasörüne eşitlendi" && echo "+ NinoCore $sha eşitlendi"; fi
else
  echo "NinoCore deposu yok ($NINO_CORE_REPO); core/ olduğu gibi kaldı."
fi

# Denetim: nino-pool migration numaraları tekrarsız ve boşluksuz olmalı.
if [ -d nino-pool/migrations ]; then
  dup=$(ls nino-pool/migrations | sed -n 's/^\([0-9]\{4\}\)_.*/\1/p' | sort | uniq -d)
  [ -z "$dup" ] || { echo "UYARI: aynı numaralı migration: $dup" >&2; exit 3; }
  echo "Migration'lar: $(ls nino-pool/migrations | tail -4 | tr '\n' ' ')"
fi
echo "Bitti: $(git log --oneline -1)"
