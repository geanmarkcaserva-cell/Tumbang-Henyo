"""Mix the user's new house models (V7-V13) into the barangay layout.

Runs on plain Python (no Blender needed):
    python add_new_houses.py <barangay_layout.json> <house_footprints.json>

- Some existing lots switch to a new model (it keeps the lot's spot and facing, and is only
  swapped in if it fits without touching neighbours, roads, the court or the electric wires).
- A few extra houses are added in free space, near and far (far ones are scaled up like before).
- Plants under the new houses are removed and the house colliders are rebuilt.
"""
import json, math, random, re, sys

LAYOUT, FOOT = sys.argv[1], sys.argv[2]
rnd = random.Random(20261018)
L = json.load(open(LAYOUT)); foot = json.load(open(FOOT))

VAR = {}
for name, verts in foot.items():
    low = [v for v in verts if v[2] < 1.6]
    VAR[name] = dict(x0=min(v[0] for v in low), x1=max(v[0] for v in low), y0=min(v[1] for v in low),
                     y1=max(v[1] for v in low), top=max(v[2] for v in verts))
NEW = ["House_V7_Fence", "House_V8_Patchwork", "House_V9_Kubo", "House_V10_Brick",
       "House_V11_Tindahan", "House_V12_Kahoy", "House_V13_Semento"]
# The two heaviest models (4.5k / 8.3k triangles) are used sparingly for phones.
CAP = {"House_V8_Patchwork": 6, "House_V7_Fence": 8, "House_V9_Kubo": 8}  # kubo: an open stall, not a home
NEAR_W = {"House_V11_Tindahan": 4, "House_V9_Kubo": 3, "House_V10_Brick": 3, "House_V12_Kahoy": 3,
          "House_V13_Semento": 3, "House_V7_Fence": 2, "House_V8_Patchwork": 2}
FAR_W = {"House_V10_Brick": 3, "House_V12_Kahoy": 3, "House_V13_Semento": 3, "House_V11_Tindahan": 2,
         "House_V7_Fence": 2, "House_V8_Patchwork": 2, "House_V9_Kubo": 1}

def rect(cx, cy, th, v, sc=1.0, pad=0.0):
    c, s = math.cos(th), math.sin(th); pts = []
    for lx, ly in [(v["x0"]*sc-pad, v["y0"]*sc-pad), (v["x1"]*sc+pad, v["y0"]*sc-pad),
                   (v["x1"]*sc+pad, v["y1"]*sc+pad), (v["x0"]*sc-pad, v["y1"]*sc+pad)]:
        pts.append((cx + lx*c - ly*s, cy + lx*s + ly*c))
    return pts
def aabb(x0, y0, x1, y1): return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
def overlap(a, b):
    for poly in (a, b):
        for i in range(4):
            p, q = poly[i], poly[(i+1) % 4]; ax = (q[1]-p[1], p[0]-q[0])
            pa = [ax[0]*x + ax[1]*y for x, y in a]; pb = [ax[0]*x + ax[1]*y for x, y in b]
            if max(pa) < min(pb) or max(pb) < min(pa): return False
    return True
def inside(pt, poly):
    sgn = None
    for i in range(4):
        p, q = poly[i], poly[(i+1) % 4]
        cr = (q[0]-p[0])*(pt[1]-p[1]) - (q[1]-p[1])*(pt[0]-p[0])
        if sgn is None: sgn = cr > 0
        elif (cr > 0) != sgn: return False
    return True
def seg_hits(poly, a, b, width):
    n = int(math.dist(a, b) / 0.5) + 1
    for i in range(n + 1):
        t = i / n; p = (a[0] + (b[0]-a[0])*t, a[1] + (b[1]-a[1])*t)
        for dx, dy in ((0, 0), (width, 0), (-width, 0), (0, width), (0, -width)):
            if inside((p[0]+dx, p[1]+dy), poly): return True
    return False

KEEP_OUT = [aabb(-13.4, -14.2, 13.4, 46.0), aabb(-200, -20.6, 200, -12.9),
            aabb(22.9, -13.5, 29.1, 58.5), aabb(-27.1, -13.5, -22.4, 50.6)]
WIRES = [((-12.6, -12), (-30, -21)), ((12.6, -12.5), (30, -21)), ((-30, -21), (30, -21))]
POSTS = [(-12.6, -12), (-12.6, 10), (-12.6, 32), (12.6, -12.5), (12.6, 12), (12.6, 36), (-30, -21), (30, -21)]

# Houses in Blender coordinates (x, y), facing th, scale sc.
H = []
for h in L["houses"]:
    H.append(dict(name=h["name"], lot=h["lot"], x=h["p"][0], y=-h["p"][2], th=h["ry"], sc=h.get("s", 1.0),
                  far=h["lot"].startswith("HPF")))
def h_rect(h, pad): return rect(h["x"], h["y"], h["th"], VAR[h["name"]], h["sc"], pad)

def fits(cand, others):
    v = VAR[cand["name"]]
    if cand["far"]:
        rp = h_rect(cand, 1.5)
        x, y = cand["x"], cand["y"]
        if (-24.6 < y < -8.9) or (18.9 < x < 33.1 and y > -13.5) or (-31.1 < x < -18.4 and y > -13.5): return False
        for k in KEEP_OUT:
            if overlap(h_rect(cand, 2.0), k): return False
    else:
        rp = h_rect(cand, 0.8)
        rk = h_rect(cand, 0.3)
        for k in KEEP_OUT:
            if overlap(rk, k): return False
        r = h_rect(cand, 0.0)
        if v["top"] > 3.2 and any(seg_hits(r, a, b, 1.2) for a, b in WIRES): return False
        if any(inside(p, h_rect(cand, 0.6)) for p in POSTS): return False
    for o in others:
        if o is cand.get("_replaces"): continue
        if overlap(rp, h_rect(o, 1.5 if o["far"] else 0.8)): return False
    return True

def centre(h):
    v = VAR[h["name"]]; lx = (v["x0"] + v["x1"]) / 2 * h["sc"]; ly = (v["y0"] + v["y1"]) / 2 * h["sc"]
    c, s = math.cos(h["th"]), math.sin(h["th"])
    return h["x"] + lx*c - ly*s, h["y"] + lx*s + ly*c

used = {n: 0 for n in NEW}
def pick(weights):
    names = [n for n in weights if used[n] < CAP.get(n, 999)]
    return rnd.choices(names, [weights[n] for n in names])[0]

# ---- 1. swap about 40% of the lots to new models ----
swapped = 0
order = list(range(len(H))); rnd.shuffle(order)
for i in order:
    h = H[i]
    if rnd.random() > 0.42: continue
    w = FAR_W if h["far"] else NEAR_W
    names = [n for n in w if used[n] < CAP.get(n, 999)]
    # least-used models first, so every new model shows up
    names.sort(key=lambda n: (used[n] / w[n], rnd.random()))
    for name in names:
        cx, cy = centre(h)
        v = VAR[name]; lx = (v["x0"] + v["x1"]) / 2 * h["sc"]; ly = (v["y0"] + v["y1"]) / 2 * h["sc"]
        c, s = math.cos(h["th"]), math.sin(h["th"])
        cand = dict(h, name=name, x=cx - (lx*c - ly*s), y=cy - (lx*s + ly*c), _replaces=h)
        if fits(cand, H):
            cand.pop("_replaces"); cand["new"] = True
            cand["lot"] = re.sub(r"_V\d+_.*$", "_" + name.replace("House_", ""), h["lot"])
            H[i] = cand; used[name] += 1; swapped += 1
            break
print("swapped", swapped)

# ---- 2. a few extra houses in the gaps ----
def face(cx, cy, tx, ty): return math.atan2(-(tx - cx), (ty - cy)) + math.pi
def court_pt(x, y): return (math.copysign(11.0, x), min(max(y, 0.0), 40.0))
ZONES = [  # count, x range, y range, look-at, jitter
    (6, (-30.0, 30.0), (-12.0, 50.0), lambda x, y: court_pt(x, y), 20),
    (10, (-60.0, 60.0), (-12.0, 75.0), lambda x, y: court_pt(x, y), 35),
    (6, (-55.0, 55.0), (-52.0, -22.0), lambda x, y: (x * 0.6, -16.0), 30),
]
added = 0; n_lot = 0
for count, xr, yr, look, jit in ZONES:
    ok = 0; tries = 0
    while ok < count and tries < 3000:
        tries += 1
        x, y = rnd.uniform(*xr), rnd.uniform(*yr)
        name = pick(NEAR_W)
        th = face(x, y, *look(x, y)) + math.radians(rnd.uniform(-jit, jit))
        if rnd.random() < 0.25: th += math.radians(rnd.choice([-45, 45]))
        cand = dict(name=name, lot="HPN_%02d_%s" % (n_lot, name.replace("House_", "")), x=x, y=y, th=th, sc=1.0, far=False, new=True)
        if fits(cand, H):
            H.append(cand); used[name] += 1; ok += 1; added += 1; n_lot += 1
CX, CY = 0.0, 20.0
ok = 0; tries = 0
while ok < 12 and tries < 4000:
    tries += 1
    a = rnd.uniform(0, 2*math.pi); d = rnd.uniform(62, 150)
    x = CX + d*math.cos(a); y = CY + d*math.sin(a)*1.1
    name = pick(FAR_W); sc = 1.15 + (d - 62) / 88 * 1.05
    th = math.atan2(-(CX - x), (CY - y)) + math.pi + math.radians(rnd.uniform(-40, 40))
    cand = dict(name=name, lot="HPFN_%02d_%s" % (ok, name.replace("House_", "")), x=x, y=y, th=th, sc=round(sc, 3), far=True, new=True)
    if fits(cand, H):
        H.append(cand); used[name] += 1; ok += 1; added += 1
print("added", added, "uses", used)

# ---- 3. plants: none inside the new houses ----
BIG = ("PH_Mango", "PH_Coconut", "PH_Pine", "PH_Banana")
new_rects = [(h, h_rect(h, 0)) for h in H if h.get("new")]
removed = 0
for key in ("plants", "extra_plants"):
    for pname, lst in L[key].items():
        big = pname.startswith(BIG)
        keep = []
        for e in lst:
            pt = (e["p"][0], -e["p"][2])
            hit = False
            for h, _ in new_rects:
                if inside(pt, h_rect(h, (1.6 if big else 0.4) * (1.0 if not h["far"] else 1.0))):
                    hit = True; break
            if hit: removed += 1
            else: keep.append(e)
        L[key][pname] = keep
print("plants removed", removed)

# ---- 4. write houses and rebuild their colliders ----
houses = []; boxes = [b for b in L["boxes"] if not b["name"].startswith("House_")]
for h in H:
    houses.append({"name": h["name"], "lot": h["lot"], "p": [round(h["x"], 3), 0.0, round(-h["y"], 3)],
                   "ry": round(h["th"], 5), "s": round(h["sc"], 3)})
    if h["far"]: continue
    v = VAR[h["name"]]; cx, cy = centre(h)
    boxes.append({"name": "House_" + h["lot"], "center": [round(cx, 3), round(v["top"] / 2, 3), round(-cy, 3)],
                  "size": [round(v["x1"] - v["x0"], 3), round(v["top"], 3), round(v["y1"] - v["y0"], 3)], "ry": round(h["th"], 5)})
L["houses"] = houses; L["boxes"] = boxes
json.dump(L, open(LAYOUT, "w"), indent=1)
from collections import Counter
print("houses", len(houses), Counter(h["name"] for h in H))
