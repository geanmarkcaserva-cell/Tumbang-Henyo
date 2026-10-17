
import bpy, bmesh, json, math, random
ROOT = r"C:\Users\user\Documents\tumbang-henyo"
exec(open(ROOT + r"\art\source\scatter_houses.py").read().split("# ---------- 2. house variants")[0].split("# ---------- 1. flatten")[0])  # imports only
foot = json.load(open(ROOT + r"\art\source\house_footprints.json"))
VAR = {}
for name, verts in foot.items():
    low = [v for v in verts if v[2] < 1.6]
    VAR[name] = dict(x0=min(v[0] for v in low), x1=max(v[0] for v in low), y0=min(v[1] for v in low),
                     y1=max(v[1] for v in low), top=max(v[2] for v in verts))
rnd = random.Random(902)
CX, CY = 0.0, 20.0     # court centre (Blender)

def rect(cx, cy, th, v, sc=1.0, pad=0.0):
    c, s = math.cos(th), math.sin(th); pts = []
    for lx, ly in [(v["x0"]*sc-pad, v["y0"]*sc-pad), (v["x1"]*sc+pad, v["y0"]*sc-pad), (v["x1"]*sc+pad, v["y1"]*sc+pad), (v["x0"]*sc-pad, v["y1"]*sc+pad)]:
        pts.append((cx + lx*c - ly*s, cy + lx*s + ly*c))
    return pts
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
def on_road(x, y, m=0.0):
    return (-20.6 - m < y < -12.9 + m and abs(x) < 400) or (22.9 - m < x < 29.1 + m and -13.5 < y < 58.5) or (-27.1 - m < x < -22.4 + m and -13.5 < y < 50.6)

hp = bpy.data.collections["House_Placements"]
near = []
for o in hp.objects:
    if o.get("far"): continue
    v = VAR[o["variant"]]; near.append(rect(o.location.x, o.location.y, o.rotation_euler.z, v, o.scale.x, pad=0.8))
for o in [o for o in hp.objects if o.get("far")]: bpy.data.objects.remove(o)

# ---------- far ring of bigger houses (forced perspective) ----------
BIG = {"House_V1_Tindahan": 2, "House_V2_Blue": 4, "House_V3_Tindahan": 2, "House_V4_Tall": 4, "House_V6_CHB": 2, "House_V5_Shack": 1}
names = list(BIG); w = [BIG[n] for n in names]
far = []; tries = 0
while len(far) < 48 and tries < 6000:
    tries += 1
    a = rnd.uniform(0, 2*math.pi); d = rnd.uniform(62, 150)
    x = CX + d*math.cos(a); y = CY + d*math.sin(a)*1.1
    if on_road(x, y, 4): continue
    name = rnd.choices(names, w)[0]; v = VAR[name]
    sc = 1.15 + (d - 62) / 88 * 1.05
    th = math.atan2(-(CX - x), (CY - y)) + math.pi + math.radians(rnd.uniform(-40, 40))
    rp = rect(x, y, th, v, sc, pad=1.5)
    if any(overlap(rp, q) for q in near + [f["rp"] for f in far]): continue
    far.append(dict(name=name, x=x, y=y, th=th, sc=sc, rp=rp))
for i, f in enumerate(far):
    v = VAR[f["name"]]
    me = bpy.data.meshes.new("HPF_" + f["name"]); bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0)
    for vert in bm.verts:
        vert.co.x = v["x0"] + (vert.co.x + 0.5) * (v["x1"] - v["x0"]); vert.co.y = v["y0"] + (vert.co.y + 0.5) * (v["y1"] - v["y0"])
        vert.co.z = (vert.co.z + 0.5) * v["top"]
    bm.to_mesh(me); bm.free()
    ob = bpy.data.objects.new("HPF_%02d_%s" % (i, f["name"].replace("House_", "")), me)
    ob["variant"] = f["name"]; ob["far"] = True
    ob.location = (f["x"], f["y"], 0); ob.rotation_euler = (0, 0, f["th"]); ob.scale = (f["sc"],) * 3
    ob.display_type = "WIRE"; hp.objects.link(ob)
print("far houses", len(far), "tries", tries)

all_rects = near + [f["rp"] for f in far]
def blocked(x, y, pad_rects):
    return any(inside((x, y), r) for r in pad_rects)

# ---------- forest belt: denser and taller the further out ----------
TREES = [("PH_Mango_A", 3), ("PH_Mango_B", 3), ("PH_Mango_C", 2), ("PH_Coconut_A", 3), ("PH_Coconut_B", 3), ("PH_Pine", 2)]
tn = [t[0] for t in TREES]; tw = [t[1] for t in TREES]
extra = {}
n = 0; tries = 0
while n < 620 and tries < 20000:
    tries += 1
    a = rnd.uniform(0, 2*math.pi); d = 58 + (rnd.random() ** 0.7) * 170
    x = CX + d*math.cos(a); y = CY + d*math.sin(a)*1.1
    if on_road(x, y, 2): continue
    if blocked(x, y, all_rects): continue
    name = rnd.choices(tn, tw)[0]
    extra.setdefault(name, []).append({"p": [round(x, 2), -0.05, round(-y, 2)], "ry": round(rnd.uniform(0, 6.283), 3), "s": round(rnd.uniform(0.85, 1.2), 3)})
    n += 1
print("forest trees", n)

# ---------- spiky low-poly grass around the court ----------
g = 0; tries = 0
while g < 3200 and tries < 40000:
    tries += 1
    x = rnd.uniform(-70, 70); y = rnd.uniform(-55, 95)
    if -13.6 < x < 13.6 and -14.4 < y < 46.2: continue          # court and apron stay clean
    if on_road(x, y, 0.2): continue
    if blocked(x, y, all_rects): continue
    # clumps: grass grows in patches
    for k in range(rnd.randint(1, 4)):
        gx = x + rnd.uniform(-1.2, 1.2); gy = y + rnd.uniform(-1.2, 1.2)
        name = "PS1_Grass_A" if rnd.random() < 0.6 else "PS1_Grass_B"
        extra.setdefault(name, []).append({"p": [round(gx, 2), -0.05, round(-gy, 2)], "ry": round(rnd.uniform(0, 6.283), 3), "s": round(rnd.uniform(0.8, 1.5), 3)})
        g += 1
print("grass clumps", g)
L = json.load(open(ROOT + r"\art\environment\barangay_layout.json"))
L["extra_plants"] = extra
for nm in ("PS1_Grass_A", "PS1_Grass_B"):
    if nm not in L["small"]: L["small"].append(nm)
L["ps1"] = ["PH_Mango_A", "PH_Mango_B", "PH_Mango_C", "PH_Coconut_A", "PH_Coconut_B", "PH_Pine", "PS1_Grass_A", "PS1_Grass_B"]
L["grow_with_distance"] = ["PH_Mango_A", "PH_Mango_B", "PH_Mango_C", "PH_Coconut_A", "PH_Coconut_B", "PH_Pine"]
json.dump(L, open(ROOT + r"\art\environment\barangay_layout.json", "w"), indent=1)
