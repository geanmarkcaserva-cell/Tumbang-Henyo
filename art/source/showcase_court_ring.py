"""Make the houses right around the SK court a showcase: every model once, no repeats.

    python showcase_court_ring.py <barangay_layout.json> <house_footprints.json>

1. The ring = the houses within RING_DIST metres of the court. They get one model each
   (13 models -> 13 lots; any extra lot in the ring is removed). A model may slide back a little
   (away from the court) if it needs more room; it never touches roads, wires or other houses.
2. Further out, a house whose neighbour within SAME_DIST metres is the same model is switched to
   another model that fits, where possible.
3. Plants under changed houses are removed and house colliders rebuilt.
"""
import json, math, random, sys
from collections import Counter

LAYOUT, FOOT = sys.argv[1], sys.argv[2]
RING_DIST = 12.0
SAME_DIST = 16.0
rnd = random.Random(1018)
L = json.load(open(LAYOUT)); foot = json.load(open(FOOT))
VAR = {}
for name, verts in foot.items():
    low = [v for v in verts if v[2] < 1.6]
    VAR[name] = dict(x0=min(v[0] for v in low), x1=max(v[0] for v in low), y0=min(v[1] for v in low),
                     y1=max(v[1] for v in low), top=max(v[2] for v in verts))
MODELS = sorted(VAR)
CAP = {"House_V8_Patchwork": 6, "House_V7_Fence": 8, "House_V9_Kubo": 8}

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

H = [dict(name=h["name"], lot=h["lot"], x=h["p"][0], y=-h["p"][2], th=h["ry"], sc=h.get("s", 1.0),
          far=h["lot"].startswith("HPF")) for h in L["houses"]]
def h_rect(h, pad): return rect(h["x"], h["y"], h["th"], VAR[h["name"]], h["sc"], pad)
def centre(h):
    v = VAR[h["name"]]; lx = (v["x0"] + v["x1"]) / 2 * h["sc"]; ly = (v["y0"] + v["y1"]) / 2 * h["sc"]
    c, s = math.cos(h["th"]), math.sin(h["th"])
    return h["x"] + lx*c - ly*s, h["y"] + lx*s + ly*c
def court_dist(h):
    x, y = centre(h)
    return math.hypot(max(-13.4 - x, 0, x - 13.4), max(-14.2 - y, 0, y - 46.0))

def legal(cand):
    """Fits the land (roads, court, wires, posts); neighbours are checked separately."""
    v = VAR[cand["name"]]
    rk = h_rect(cand, 0.3)
    if any(overlap(rk, k) for k in KEEP_OUT): return False
    r = h_rect(cand, 0.0)
    if v["top"] > 3.2 and any(seg_hits(r, a, b, 1.2) for a, b in WIRES): return False
    if any(inside(p, h_rect(cand, 0.6)) for p in POSTS): return False
    return True
def clear_of(cand, others):
    rp = h_rect(cand, 0.8)
    return not any(overlap(rp, h_rect(o, 1.5 if o["far"] else 0.8)) for o in others)

def placed_like(slot, name, back=0.0):
    """Model `name` on a lot: same footprint centre and facing, slid `back` metres away from the court."""
    cx, cy = centre(slot)
    c, s = math.cos(slot["th"]), math.sin(slot["th"])
    cx += -s * back; cy += c * back          # local +Y = away from the front
    v = VAR[name]; lx = (v["x0"] + v["x1"]) / 2; ly = (v["y0"] + v["y1"]) / 2
    return dict(slot, name=name, x=cx - (lx*c - ly*s), y=cy - (lx*s + ly*c), sc=1.0, far=False, changed=True)

# ---------- 1. the showcase ring ----------
# The old ring lots are cleared and the 13 models are laid out fresh along the three sides of the
# court that have land (the main road runs along the fourth): left strip, right strip, behind the
# far hoop. Each house faces the court, with a slightly different setback, gap and angle so the
# row doesn't look planted.
near = [h for h in H if not h["far"]]
old_ring = [h for h in near if court_dist(h) < RING_DIST]
for h in old_ring: H.remove(h)
others = list(H)
print("cleared old ring lots", len(old_ring))

# side: (front direction th, along-axis range, which way is "out")
SIDES = {
    "left":  dict(th=math.pi / 2,  lo=-12.6, hi=44.0),   # x = -13.4 - setback, along y
    "right": dict(th=-math.pi / 2, lo=-12.6, hi=44.0),   # x = +13.4 + setback, along y
    "back":  dict(th=0.0,          lo=-22.1, hi=22.6),   # y = 46.0 + setback, along x
}
def at_side(name, side, along, setback, jitter):
    v = VAR[name]; sd = SIDES[side]
    th = sd["th"] + jitter
    depth = v["y1"] - v["y0"]
    out = 13.4 + setback + depth / 2 if side != "back" else 46.0 + setback + depth / 2
    if side == "left": cx, cy = -out, along
    elif side == "right": cx, cy = out, along
    else: cx, cy = along, out
    c, s = math.cos(th), math.sin(th)
    lx = (v["x0"] + v["x1"]) / 2; ly = (v["y0"] + v["y1"]) / 2
    return dict(name=name, lot="", x=cx - (lx*c - ly*s), y=cy - (lx*s + ly*c), th=th, sc=1.0, far=False, changed=True, ring=True)

best = None
for it in range(20000):
    order = MODELS[:]; rnd.shuffle(order)
    rows = {k: [] for k in SIDES}
    for name in order: rows[rnd.choice(list(SIDES))].append(name)
    placed = []; good = True
    for side, names in rows.items():
        sd = SIDES[side]; pos = sd["lo"] + rnd.uniform(0.0, 2.0)
        for name in names:
            w = VAR[name]["x1"] - VAR[name]["x0"]
            cand = None
            for _ in range(6):
                along = pos + w / 2
                if along + w / 2 > sd["hi"]: break
                c = at_side(name, side, along, rnd.uniform(0.3, 1.4), math.radians(rnd.uniform(-5, 5)))
                if legal(c) and clear_of(c, others) and clear_of(c, placed):
                    cand = c; break
                pos += 1.0
            if cand is None: good = False; break
            placed.append(cand)
            pos += w + rnd.uniform(1.8, 3.5)
        if not good: break
    if good:
        best = placed; print("ring laid out after", it + 1, "tries:", {k: len(v) for k, v in rows.items()}); break
if best is None: sys.exit("no layout found - nothing written")
for i, h in enumerate(sorted(best, key=lambda h: math.atan2(centre(h)[1] - 16, centre(h)[0]))):
    h["lot"] = "HPR_%02d_%s" % (i, h["name"].replace("House_", ""))
    H.append(h)

# ---------- 2. further out: no same model right next door ----------
used = Counter(h["name"] for h in H)
def same_near(h, name):
    cx, cy = centre(dict(h, name=name))
    return any(o is not h and o["name"] == name and not o["far"] and math.dist(centre(o), (cx, cy)) < SAME_DIST for o in H)
fixed = 0
for h in sorted([h for h in H if not h["far"] and not h.get("ring")], key=court_dist):
    if not same_near(h, h["name"]): continue
    cands = [n for n in MODELS if n != h["name"] and used[n] < CAP.get(n, 999)]
    cands.sort(key=lambda n: (used[n], rnd.random()))
    for name in cands:
        cand = placed_like(h, name)
        if same_near(cand, name): continue
        if not legal(cand) or not clear_of(cand, [o for o in H if o is not h]): continue
        used[h["name"]] -= 1; used[name] += 1
        cand["lot"] = h["lot"].rsplit("_V", 1)[0] + "_" + name.replace("House_", "")
        H[H.index(h)] = cand; fixed += 1
        break
# Lots where nothing else fits: close to the court, an empty lot beats a twin (farther twin goes).
for h in sorted([h for h in H if not h["far"] and not h.get("ring")], key=court_dist, reverse=True):
    if court_dist(h) < 25.0 and same_near(h, h["name"]):
        H.remove(h); used[h["name"]] -= 1; print("removed twin lot", h["lot"])
left = sum(1 for h in H if not h["far"] and same_near(h, h["name"]))
print("neighbour repeats fixed", fixed, "still next to a twin", left)

# ---------- 3. plants, colliders, write ----------
BIG = ("PH_Mango", "PH_Coconut", "PH_Pine", "PH_Banana")
changed = [h for h in H if h.get("changed")]
removed = 0
for key in ("plants", "extra_plants"):
    for pname, lst in L[key].items():
        pad = 1.6 if pname.startswith(BIG) else 0.4
        keep = [e for e in lst if not any(inside((e["p"][0], -e["p"][2]), h_rect(h, pad)) for h in changed)]
        removed += len(lst) - len(keep); L[key][pname] = keep
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
print("plants removed", removed, "houses", len(houses))
print("ring:", sorted((round(court_dist(h), 1), h["name"]) for h in H if h.get("ring")))
