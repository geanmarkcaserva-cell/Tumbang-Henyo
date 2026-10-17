
import bpy, json, math, os
ROOT = r"C:\Users\user\Documents\tumbang-henyo"
LAYOUT = ROOT + r"\art\environment\barangay_layout.json"
foot = json.load(open(ROOT + r"\art\source\house_footprints.json"))
VAR = {}
for name, verts in foot.items():
    low = [v for v in verts if v[2] < 1.6]
    VAR[name] = dict(x0=min(v[0] for v in low), x1=max(v[0] for v in low), y0=min(v[1] for v in low),
                     y1=max(v[1] for v in low), top=max(v[2] for v in verts))
L = json.load(open(LAYOUT))
houses = []; boxes = [b for b in L["boxes"] if not b["name"].startswith("House_")]
for o in sorted(bpy.data.collections["House_Placements"].objects, key=lambda o: o.name):
    v = VAR[o["variant"]]; th = o.rotation_euler.z; x, y = o.location.x, o.location.y
    sc = round(o.scale.x, 3)
    houses.append({"name": o["variant"], "lot": o.name, "p": [round(x, 3), 0.0, round(-y, 3)], "ry": round(th, 5), "s": sc})
    if o.get("far"): continue   # far-off scenery: no collision needed
    lx, ly = (v["x0"] + v["x1"]) / 2, (v["y0"] + v["y1"]) / 2
    cx = x + lx * math.cos(th) - ly * math.sin(th); cy = y + lx * math.sin(th) + ly * math.cos(th)
    boxes.append({"name": "House_" + o.name, "center": [round(cx, 3), round(v["top"] / 2, 3), round(-cy, 3)],
                  "size": [round(v["x1"] - v["x0"], 3), round(v["top"], 3), round(v["y1"] - v["y0"], 3)], "ry": round(th, 5)})
plants = {}
for o in bpy.data.collections["Foliage"].all_objects:
    if not o.data: continue
    plants.setdefault(o.data.name, []).append({"p": [round(o.location.x, 3), round(o.location.z, 3), round(-o.location.y, 3)],
                                               "ry": round(o.rotation_euler.z, 4), "s": round(o.scale.x, 3)})
L["houses"] = houses; L["boxes"] = boxes; L["plants"] = plants
json.dump(L, open(LAYOUT, "w"), indent=1)
print("houses", len(houses), "plants", sum(len(v) for v in plants.values()))
