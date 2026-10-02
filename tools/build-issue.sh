#!/usr/bin/env bash
# Rebuild the on-site issue from an app export.
#
#   tools/build-issue.sh /path/to/exports/<issue>/publish/release-N
#
# Takes the exported pages and reader and produces:
#   issue/pages/NN.<hash>.webp  page images, web-sized
#   issue/reader.html           the exported reader, adapted for the site
#   images/issue-1-cover.<hash>.webp  the landing-page thumbnail
#
# Filenames carry a hash of their contents. Page numbering is reused between
# releases while the content behind it changes — release 8 turned 02 from a
# single page into a spread — and these files are served immutable for a year.
# Without the hash a returning browser keeps the old file and the reader slices
# it under the new rules, which put half of page 1 on the inside front cover.
# A new hash means a new URL, so nothing stale can be reused.
set -euo pipefail

SRC="${1:?usage: build-issue.sh <release-dir>}"
[ -d "$SRC/pages" ] || { echo "no pages/ in $SRC" >&2; exit 1; }
[ -f "$SRC/reader/index.html" ] || { echo "no reader/index.html in $SRC" >&2; exit 1; }
cd "$(dirname "$0")/.."

# Stale pages must go: a new release may have fewer of them, and old hashed
# names would otherwise linger forever.
rm -rf issue/pages && mkdir -p issue/pages
MAP=$(mktemp); echo '{' > "$MAP"

total=0
for f in "$SRC"/pages/*.jpg; do
  n=$(basename "$f" .jpg)
  w=$(sips -g pixelWidth "$f" | awk '/pixelWidth/{print $2}')
  # Spreads are two pages wide, singles one. Halving the target for singles
  # keeps every page the same height through the book.
  if [ "$w" -gt 2000 ]; then target=2000; else target=1000; fi
  tmp=$(mktemp -t page).webp
  cwebp -quiet -q 80 -resize "$target" 0 "$f" -o "$tmp"
  h=$(shasum -a 256 "$tmp" | cut -c1-8)
  out="$n.$h.webp"
  mv "$tmp" "issue/pages/$out"
  echo "  \"$n\": \"$out\"," >> "$MAP"
  kb=$(( $(stat -f%z "issue/pages/$out") / 1024 ))
  total=$(( total + kb ))
  printf '  %s  %spx -> %spx  %sKB  %s\n' "$n" "$w" "$target" "$kb" "$out"
done
echo '  "_":""}' >> "$MAP"
echo "  pages total: ${total}KB"

# The landing-page thumbnail is always the front cover, hashed for the same
# reason: it changes between releases but index.html references it by name.
rm -f images/issue-1-cover.*.webp images/issue-1-cover.webp
tmpc=$(mktemp -t cover).webp
cwebp -quiet -q 82 -resize 520 0 "$SRC/pages/01.jpg" -o "$tmpc"
ch=$(shasum -a 256 "$tmpc" | cut -c1-8)
mv "$tmpc" "images/issue-1-cover.$ch.webp"
echo "  cover: issue-1-cover.$ch.webp"

python3 - "$SRC/reader/index.html" "$MAP" "issue-1-cover.$ch.webp" <<'PY'
import sys, json, re
s = open(sys.argv[1], encoding='utf-8').read()
pagemap = json.load(open(sys.argv[2]))
cover = sys.argv[3]

# Point each manifest entry at its hashed WebP beside this file.
for n, out in pagemap.items():
    if n == '_':
        continue
    old = f'"../pages/{n}.jpg"'
    assert old in s, f'reader manifest has no entry for page {n}'
    s = s.replace(old, f'"pages/{out}"')
assert '../pages/' not in s, 'a page reference was left unhashed'

# index.html carries the cover thumbnail by name; keep it in step.
idx = open('index.html', encoding='utf-8').read()
idx2 = re.sub(r'images/issue-1-cover[^"]*\.webp', f'images/{cover}', idx)
assert idx2 != idx or f'images/{cover}' in idx, 'cover thumbnail reference not found in index.html'
open('index.html', 'w', encoding='utf-8').write(idx2)

# Repaint in the site palette.
for old, new in [
    ('background:#0d0d0f;color:#ddd', 'background:#14110E;color:#EFE9E0'),
    ('#flip .cover.bare{background:#0d0d0f}', '#flip .cover.bare{background:#14110E}'),
    ('background:#141417;border-top:1px solid #222', 'background:#1C1814;border-top:2px solid #322B22'),
    ('color:#999;font-size:13px', 'color:#A99E90;font-size:13px'),
    ('footer b{color:#eee}', 'footer b{color:#EFE9E0}'),
    ('border:1px solid #333;border-radius:6px;background:#222;color:#eee',
     'border:1px solid #322B22;border-radius:0;background:#241F19;color:#EFE9E0'),
    ('.turn:hover{background:#333}',
     '.turn:hover{background:#F07020;color:#14110E;border-color:#F07020}'),
]:
    assert old in s, f'reader template changed; no match for: {old[:48]}'
    s = s.replace(old, new)

# The seam fix (even-pixel sizing and the overlapped leaf halves) now ships in
# the export itself, as of release 7. The patch that used to live here is gone.

# Public title instead of the internal slug and release number.
import re
s = re.sub(r'<title>.*?</title>',
           '<title>Victoria Clarke and the Galton Conspiracy — Issue 1</title>', s, count=1)
s, n = re.subn(r'<b>[^<]*</b><span>Release \d+</span>',
               '<b>Victoria Clarke and the Galton Conspiracy</b><span>Issue 1</span>', s, count=1)
assert n == 1, 'reader footer markup changed; title/release line not found'

# Running in an iframe: let Escape close the overlay.
anchor = "addEventListener('resize',layout);"
assert anchor in s, 'reader script changed; resize hook not found'
s = s.replace(anchor,
  "document.addEventListener('keydown',(e)=>{if(e.key==='Escape'&&parent!==window)"
  "parent.postMessage('close-reader','*')});\n" + anchor)

open('issue/reader.html', 'w', encoding='utf-8').write(s)
print('  reader.html rebuilt')
PY
echo "done."
