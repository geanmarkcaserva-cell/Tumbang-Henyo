"""Build art/ui/fonts/HrClunky-Tight.ttf from the original Hr Clunky (art/source/fonts):
   - letters 30% bigger for the same font size (the original draws them small),
   - the wide gaps between letters tightened,
   - every letter put on one baseline, each kind of letter at one height,
   - hollow "bubble outline" letters filled in solid (only real counters, like the
     holes in O, B, e, stay open), so they read as white letters with one outline.
   python make_title_font.py HrClunky-Regular.otf HrClunky-Tight.ttf
"""
import sys
from fontTools.ttLib import TTFont
from fontTools.ttLib.scaleUpem import scale_upem
from fontTools.ttLib.tables._g_l_y_f import GlyphCoordinates
from matplotlib.path import Path

SRC, DST = sys.argv[1], sys.argv[2]
SCALE = 1.3   # letter size
SIDE = 34     # space on each side of a letter (units of 1000/em)
SPACE = 240   # width of a space

f = TTFont(SRC)
scale_upem(f, int(1000 * SCALE))
f['head'].unitsPerEm = 1000
glyf = f['glyf']; hm = f['hmtx']

# 1. fill the hollow letters
for name in f.getGlyphOrder():
    g = glyf[name]
    if g.numberOfContours <= 0 or g.isComposite():
        continue
    coords, ends, flags = g.getCoordinates(glyf)
    cs = []; s = 0
    for e in ends:
        cs.append((list(coords[s:e + 1]), list(flags[s:e + 1]))); s = e + 1
    paths = [Path(c[0]) for c in cs]
    n = len(cs)
    depth = [sum(1 for j in range(n) if j != i and paths[j].contains_point(cs[i][0][0])) for i in range(n)]
    inner = [not any(j != i and paths[i].contains_point(cs[j][0][0]) for j in range(n)) for i in range(n)]
    keep = []
    for i, (pts, fl) in enumerate(cs):
        if depth[i] == 0:
            keep.append((pts, fl))                    # outside of the letter
        elif depth[i] >= 2 and inner[i]:              # a counter (hole in O, B, e...)
            if depth[i] % 2 == 0:                     # drawn as a ring without its hole:
                pts, fl = pts[::-1], fl[::-1]         # its outline becomes the hole
            keep.append((pts, fl))
    allp, allf, new_ends = [], [], []
    for pts, fl in keep:
        allp += pts; allf += fl; new_ends.append(len(allp) - 1)
    g.coordinates = GlyphCoordinates(allp); g.flags = bytearray(allf)
    g.endPtsOfContours = new_ends; g.numberOfContours = len(new_ends)
    g.recalcBounds(glyf)

# 1b. line the letters up: every letter on one baseline, each kind at one height
#     (capitals, small letters, tall small letters, letters with tails), so the
#     handwriting keeps its wobble but the words sit straight.
cmap = f.getBestCmap()
def _h(ch): g = glyf[cmap[ord(ch)]]; return g.yMax - g.yMin
CAP = sorted(_h(c) for c in "ABCDEFGHIKLMNOPRSTUVWXYZ")[12]          # median capital height
XH = sorted(_h(c) for c in "acemnorsuvwxz")[6]                       # median small-letter height
RULES = {}  # char -> (height, bottom)
for c in "ABCDEFGHIJKLMNOPRSTUVWXYZ!?": RULES[c] = (CAP, 0)
RULES["Q"] = (CAP * 1.12, -CAP * 0.12)
for c in "acemnorsuvwxz": RULES[c] = (XH, 0)
for c in "bdfhkl": RULES[c] = (CAP, 0)
RULES["t"] = (CAP * 0.86, 0)
RULES["i"] = (CAP * 0.92, 0)
RULES["j"] = (CAP * 0.92 + XH * 0.4, -XH * 0.4)
for c in "gpqy": RULES[c] = (XH * 1.42, -XH * 0.42)
RULES["."] = (CAP * 0.24, 0)
RULES[","] = (CAP * 0.4, -CAP * 0.14)
RULES[":"] = (XH, 0)
RULES[";"] = (XH * 1.14, -XH * 0.14)
for ch, (height, bottom) in RULES.items():
    name = cmap.get(ord(ch))
    if not name: continue
    g = glyf[name]
    if g.numberOfContours <= 0 or g.isComposite(): continue
    g.recalcBounds(glyf)
    k = height / max(g.yMax - g.yMin, 1)
    k = min(max(k, 0.72), 1.35)  # don't distort a letter too far
    x0, y0 = g.xMin, g.yMin
    g.coordinates = GlyphCoordinates([((x - x0) * k + x0, (y - y0) * k + bottom) for x, y in g.coordinates])
    g.recalcBounds(glyf)

# 2. tighten the spacing
for name in f.getGlyphOrder():
    g = glyf[name]
    if g.numberOfContours == 0:
        if name == 'space':
            hm[name] = (SPACE, 0)
        continue
    g.recalcBounds(glyf)
    dx = SIDE - g.xMin
    if g.isComposite():
        for c in g.components: c.x += dx
    else:
        g.coordinates.translate((dx, 0))
    g.recalcBounds(glyf)
    hm[name] = (g.xMax - g.xMin + 2 * SIDE, g.xMin)

# 3. vertical metrics that fit the bigger letters
names = [n for n in f.getGlyphOrder() if glyf[n].numberOfContours]
ymin = min(glyf[n].yMin for n in names); ymax = max(glyf[n].yMax for n in names)
hh = f['hhea']; hh.ascent = ymax + 20; hh.descent = ymin - 10; hh.lineGap = 0
os2 = f['OS/2']
os2.sTypoAscender, os2.sTypoDescender, os2.sTypoLineGap = hh.ascent, hh.descent, 0
os2.usWinAscent, os2.usWinDescent = hh.ascent, -hh.descent
os2.fsSelection |= 1 << 7
f['head'].yMax = ymax; f['head'].yMin = ymin
f.save(DST)
print("saved", DST)
