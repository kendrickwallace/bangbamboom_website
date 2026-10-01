#!/usr/bin/env bash
# Rebuild the on-site issue from an app export.
#
#   tools/build-issue.sh /path/to/exports/<issue>/publish/release-N
#
# Takes the exported pages and reader and produces:
#   issue/pages/*.webp        page images, web-sized
#   issue/reader.html         the exported reader, adapted for the site
#   images/issue-1-cover.webp the landing-page thumbnail
set -euo pipefail

SRC="${1:?usage: build-issue.sh <release-dir>}"
[ -d "$SRC/pages" ] || { echo "no pages/ in $SRC" >&2; exit 1; }
[ -f "$SRC/reader/index.html" ] || { echo "no reader/index.html in $SRC" >&2; exit 1; }
cd "$(dirname "$0")/.."

# Stale pages must go: a new release may have fewer of them.
rm -rf issue/pages && mkdir -p issue/pages

total=0
for f in "$SRC"/pages/*.jpg; do
  n=$(basename "$f" .jpg)
  w=$(sips -g pixelWidth "$f" | awk '/pixelWidth/{print $2}')
  # Spreads are two pages wide, singles one. Halving the target for singles
  # keeps every page the same height through the book.
  if [ "$w" -gt 2000 ]; then target=2000; else target=1000; fi
  cwebp -quiet -q 80 -resize "$target" 0 "$f" -o "issue/pages/$n.webp"
  kb=$(( $(stat -f%z "issue/pages/$n.webp") / 1024 ))
  total=$(( total + kb ))
  printf '  %s  %spx -> %spx  %sKB\n' "$n" "$w" "$target" "$kb"
done
echo "  pages total: ${total}KB"

# The landing-page thumbnail is always the front cover.
cwebp -quiet -q 82 -resize 520 0 "$SRC/pages/01.jpg" -o images/issue-1-cover.webp

python3 - "$SRC/reader/index.html" <<'PY'
import sys
s = open(sys.argv[1], encoding='utf-8').read()

# Point at the WebP pages beside this file.
s = s.replace('"../pages/', '"pages/').replace('.jpg"', '.webp"')

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

# The leaf's two halves are separately composited 3D layers, so a sub-pixel
# gap opens where they meet, showing the dark page through as a hairline down
# the turning page — most visible on a bright page over an empty slot.
# Bleeding the inner half one pixel under the outer closes it; the extra pixel
# is the same image content the outer half starts with, so nothing shifts.
# (Worth fixing upstream in the app's reader export too.)
seam = [
 ("function face(s,back){const d=div('face'+(back?' back':''));if(s)d.append(pic(s));return d}",
  "function face(s,back,shift){const d=div('face'+(back?' back':''));"
  "if(s){const p=pic(s);if(shift)p.style.left=(parseFloat(p.style.left)+shift)+'px';d.append(p)}return d}"),
 ("function half(left,front,back){const h=div('half');h.style.left=left+'px';"
  "h.style.width=(pw/2)+'px';h.append(face(front,false),face(back,true));return h}",
  "function half(left,front,back,bleed){const h=div('half');const b=bleed||0,sh=b<0?1:0;"
  "h.style.left=(left-sh)+'px';h.style.width=((pw/2)+(b?1:0))+'px';"
  "h.append(face(front,false,sh),face(back,true,sh));return h}"),
 ("const inner=half(fwd?0:q,sub(front,fwd),sub(back,!fwd));",
  "const inner=half(fwd?0:q,sub(front,fwd),sub(back,!fwd),fwd?1:-1);"),
]
for old, new in seam:
    assert old in s, f'reader changed; seam fix no longer applies: {old[:44]}'
    s = s.replace(old, new)

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
