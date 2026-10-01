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

# Seam fix, ported from the app's own in-app reader (src/editor/server.ts).
# The exported reader does not yet carry it, so it is re-applied here on every
# build. Two parts:
#   1. layout() rounds the page to a whole, even number of pixels, so the two
#      halves of the leaf and the two slots meet on exact pixel edges instead
#      of fractional ones. This removes the cause rather than hiding it.
#   2. The inner half runs one pixel under the outer's hinge, showing the same
#      column of the picture, so the seam where the outer half bends never
#      opens to the ground beneath. The back face is mirrored about the half's
#      own middle, so widening it moves its picture — shifted back by the same
#      pixel via the fdx/bdx offsets.
# Drop this block once an export ships with the fix (the asserts will fire).
seam = [
 ("function pic(s){const im=new Image();im.src=s.src;const Ws=s.two?2*pw:pw;"
  "im.style.width=Ws+'px';im.style.height=ph+'px';im.style.left=(-s.x0*Ws)+'px';return im}",
  "function pic(s,dx){const im=new Image();im.src=s.src;const Ws=s.two?2*pw:pw;"
  "im.style.width=Ws+'px';im.style.height=ph+'px';im.style.left=(-s.x0*Ws+(dx||0))+'px';return im}"),
 ("function layout(){const w=innerWidth-24,h=innerHeight-68;ph=Math.min(h,(w/2)/ASPECT);"
  "pw=ph*ASPECT;book.style.width=(2*pw)+'px';book.style.height=ph+'px';if(shown&&!turning)paint(i)}",
  "function layout(){const w=innerWidth-24,h=innerHeight-68;"
  "pw=Math.floor(Math.min(h,(w/2)/ASPECT)*ASPECT);pw-=pw%2;ph=pw/ASPECT;"
  "book.style.width=(2*pw)+'px';book.style.height=ph+'px';if(shown&&!turning)paint(i)}"),
 ("function face(s,back){const d=div('face'+(back?' back':''));if(s)d.append(pic(s));return d}",
  "function face(s,back,dx){const d=div('face'+(back?' back':''));if(s)d.append(pic(s,dx));return d}"),
 ("function half(left,front,back){const h=div('half');h.style.left=left+'px';"
  "h.style.width=(pw/2)+'px';h.append(face(front,false),face(back,true));return h}",
  "function half(left,w,front,back,fdx,bdx){const h=div('half');h.style.left=left+'px';"
  "h.style.width=w+'px';h.append(face(front,false,fdx),face(back,true,bdx));return h}"),
 ("const inner=half(fwd?0:q,sub(front,fwd),sub(back,!fwd));",
  "const inner=fwd?half(0,q+1,sub(front,true),sub(back,false),0,1)"
  ":half(q-1,q+1,sub(front,false),sub(back,true),1,0);"),
 ("const outer=half(fwd?q:0,sub(front,!fwd),sub(back,fwd));",
  "const outer=half(fwd?q:0,q,sub(front,!fwd),sub(back,fwd),0,0);"),
]
for old, new_ in seam:
    assert old in s, f'reader changed; seam fix no longer applies: {old[:44]}'
    s = s.replace(old, new_)

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
