
import bpy, bmesh, json, math, random
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree
ROOT = r"C:\Users\user\Documents\tumbang-henyo"
LAYOUT = ROOT + r"\art\environment\barangay_layout.json"
random.seed(1734)

terrain = bpy.data.objects["Terrain"]
FOL = bpy.data.collections["Foliage"]
BIG = ("PH_Mango", "PH_Coconut", "PH_Pine", "PH_Banana")

# ---------- 1. flatten the hills (and stretch the outer ring far out so there is no visible edge) ----------
if not terrain.get("flattened"):
    deps = bpy.context.evaluated_depsgraph_get()
    bvh = BVHTree.FromObject(terrain, deps)
    for o in FOL.all_objects:                       # remember how high each plant sat above the ground
        hit = bvh.ray_cast(Vector((o.location.x, o.location.y, 60)), Vector((0, 0, -1)))
        o["above_ground"] = (o.location.z - hit[0].z) if hit[0] else 0.0
    def stretch(c, lo, hi, mid):
        d = c - mid
        lim = (hi - lo) / 2 - 18.0
        if abs(d) <= lim: return c
        return mid + math.copysign(lim + (abs(d) - lim) * 12.0, d)
    me = terrain.data
    xs = [v.co.x for v in me.vertices]; ys = [v.co.y for v in me.vertices]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    for v in me.vertices:
        v.co.x = stretch(v.co.x, x0, x1, (x0 + x1) / 2)
        v.co.y = stretch(v.co.y, y0, y1, (y0 + y1) / 2)
        v.co.z = -0.05
    me.update(); terrain["flattened"] = True
    for o in FOL.all_objects:
        o.location.z = -0.05 + o.get("above_ground", 0.0)

# ---------- 2. house variants: footprints from the exported meshes ----------
foot = json.load(open(ROOT + r"\art\source\house_footprints.json"))
VAR = {}
for name, verts in foot.items():
    low = [v for v in verts if v[2] < 1.6]
    VAR[name] = dict(x0=min(v[0] for v in low), x1=max(v[0] for v in low), y0=min(v[1] for v in low),
                     y1=max(v[1] for v in low), top=max(v[2] for v in verts))

def rect(cx, cy, th, v, pad=0.0):
    c, s = math.cos(th), math.sin(th)
    pts = []
    for lx, ly in [(v["x0"]-pad, v["y0"]-pad), (v["x1"]+pad, v["y0"]-pad), (v["x1"]+pad, v["y1"]+pad), (v["x0"]-pad, v["y1"]+pad)]:
        pts.append((cx + lx*c - ly*s, cy + lx*s + ly*c))
    return pts
def aabb_rect(x0, y0, x1, y1): return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
def overlap(a, b):  # separating axis test for two convex quads
    for poly in (a, b):
        for i in range(4):
            p, q = poly[i], poly[(i+1) % 4]
            ax = (q[1]-p[1], p[0]-q[0])
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
    # sample the segment
    n = int(((b[0]-a[0])**2 + (b[1]-a[1])**2) ** 0.5 / 0.5) + 1
    for i in range(n + 1):
        t = i / n; p = (a[0] + (b[0]-a[0])*t, a[1] + (b[1]-a[1])*t)
        for dx, dy in ((0,0),(width,0),(-width,0),(0,width),(0,-width)):
            if inside((p[0]+dx, p[1]+dy), poly): return True
    return False

KEEP_OUT = [aabb_rect(-13.4, -14.2, 13.4, 46.0),          # court + apron
            aabb_rect(-200, -20.6, 200, -12.9),          # main road
            aabb_rect(22.9, -13.5, 29.1, 58.5),          # side road
            aabb_rect(-27.1, -13.5, -22.4, 50.6)]        # alley
WIRES = [((-12.6, -12), (-30, -21)), ((12.6, -12.5), (30, -21)), ((-30, -21), (30, -21))]
trees = [(o.location.x, o.location.y) for o in FOL.all_objects if o.data and o.data.name.startswith(BIG)]

placed = []
def try_place(name, cx, cy, th):
    v = VAR[name]
    r = rect(cx, cy, th, v)
    rp = rect(cx, cy, th, v, pad=0.8)
    rk = rect(cx, cy, th, v, pad=0.3)
    for k in KEEP_OUT:
        if overlap(rk, k): return False
    for p in placed:
        if overlap(rp, p["rp"]): return False
    for a, b in WIRES:
        if v["top"] > 3.2 and seg_hits(r, a, b, 1.2): return False
    placed.append(dict(name=name, x=cx, y=cy, th=th, r=r, rp=rp)); return True

def face(cx, cy, tx, ty):   # rotation so the front (-Y) looks at (tx, ty)
    return math.atan2(-(tx - cx), (ty - cy)) + math.pi

# zones: (count, x range, y range, variant weights, look-at function, jitter deg, diagonal chance)
SMALL = {"House_V5_Shack": 4, "House_V6_CHB": 4, "House_V2_Blue": 2, "House_V4_Tall": 1, "House_V1_Tindahan": 1, "House_V3_Tindahan": 1}
STORE = {"House_V1_Tindahan": 3, "House_V3_Tindahan": 3, "House_V2_Blue": 2, "House_V6_CHB": 2, "House_V4_Tall": 2, "House_V5_Shack": 1}
def court_pt(x, y): return (math.copysign(11.0, x), min(max(y, 0.0), 40.0))
ZONES = [
    (10, (-23.0, 23.0), (-12.0, 46.0), STORE, lambda x, y: court_pt(x, y), 18, 0.15),   # first ring, facing the court
    (30, (-55.0, 55.0), (-12.0, 70.0), SMALL, lambda x, y: court_pt(x, y), 35, 0.3),     # outer ring
    (14, (-50.0, 50.0), (-50.0, -22.0), SMALL, lambda x, y: (x * 0.6, -16.0), 30, 0.25),  # across the main road
    (10, (-34.0, 34.0), (48.0, 76.0), SMALL, lambda x, y: (x * 0.4, 44.0), 30, 0.3),       # behind the far hoop
]
FIRST = ["House_V1_Tindahan", "House_V3_Tindahan", "House_V3_Tindahan", "House_V1_Tindahan"]
for zi, (count, xr, yr, weights, look, jit, diag) in enumerate(ZONES):
    names = list(weights); w = [weights[n] for n in names]
    n_ok = 0; tries = 0
    while n_ok < count and tries < 4000:
        tries += 1
        cx = random.uniform(*xr); cy = random.uniform(*yr)
        name = FIRST[n_ok] if zi == 0 and n_ok < len(FIRST) else random.choices(names, w)[0]
        tx, ty = look(cx, cy)
        th = face(cx, cy, tx, ty) + math.radians(random.uniform(-jit, jit))
        if random.random() < diag: th += math.radians(random.choice([-45, 45]))
        if try_place(name, cx, cy, th): n_ok += 1
    print("zone placed", n_ok, "of", count, "in", tries, "tries")

# ---------- 3. placement markers in Blender (move/rotate them, then re-run the layout export) ----------
hp = bpy.data.collections.get("House_Placements")
if hp is None:
    hp = bpy.data.collections.new("House_Placements"); bpy.context.scene.collection.children.link(hp)
for o in list(hp.objects): bpy.data.objects.remove(o)
for i, p in enumerate(placed):
    v = VAR[p["name"]]
    me = bpy.data.meshes.new("HP_" + p["name"])
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for vert in bm.verts:
        vert.co.x = v["x0"] + (vert.co.x + 0.5) * (v["x1"] - v["x0"])
        vert.co.y = v["y0"] + (vert.co.y + 0.5) * (v["y1"] - v["y0"])
        vert.co.z = (vert.co.z + 0.5) * v["top"]
    bm.to_mesh(me); bm.free()
    ob = bpy.data.objects.new("HP_%02d_%s" % (i, p["name"].replace("House_", "")), me)
    ob["variant"] = p["name"]; ob.location = (p["x"], p["y"], 0); ob.rotation_euler = (0, 0, p["th"])
    ob.display_type = "WIRE"; ob.show_name = False
    hp.objects.link(ob)

# ---------- 4. drop plants (small ones and trees) that ended up inside or against a house ----------
removed = 0
for o in list(FOL.all_objects):
    if not o.data: continue
    big = o.data.name.startswith(BIG)
    pt = (o.location.x, o.location.y)
    for p in placed:
        if inside(pt, rect(p["x"], p["y"], p["th"], VAR[p["name"]], pad=1.6 if big else 0.4)):
            bpy.data.objects.remove(o); removed += 1; break
print("houses", len(placed), "small plants removed", removed)
