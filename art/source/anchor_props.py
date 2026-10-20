# Sit the barangay props on the ground (barangay_land.blend).
#
#   exec(open(r"C:\Users\user\Documents\tumbang-henyo\art\source\anchor_props.py").read()); print(anchor(apply=False))
#
# Props are handled as whole items: the loose parts of a prop that touch each other (a table
# and its legs, a stall and its shelves) form one item, and items move as a block, so nothing
# inside an item shifts. Rays go straight down from each item's lowest points to find what it
# stands on (the land, or another prop: a pan on a cart). An item hanging a little above that
# (or buried a little in the ground) is moved so it touches; whatever rests on an item that
# moves goes with it. Items more than MAX_GAP above anything are left alone.
# apply=False only reports what would move.
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

exec(open(r"C:\Users\user\Documents\tumbang-henyo\art\source\export_barangay.py").read())

GROUND = ["Terrain", "Court_Apron", "Road_Main", "Road_Side", "Path_Alley_L", "Court_Slab"]
MAX_GAP = 0.6     # m: higher than this above its support = placed there on purpose
MAX_SINK = 0.3    # m: at most this much buried in the ground gets lifted out
TOUCH = 0.02      # m: parts closer than this belong to the same item
EPS = 0.004       # m: closer than this already counts as touching
DOWN = Vector((0, 0, -1))


def _world_bvh(objs):
    verts, polys, owner = [], [], []
    for o in objs:
        mw = o.matrix_world; base = len(verts)
        verts += [mw @ v.co for v in o.data.vertices]
        for p in o.data.polygons:
            polys.append([base + i for i in p.vertices]); owner.append((o.name, p.index))
    return BVHTree.FromPolygons(verts, polys), owner


def _uf(n):
    parent = list(range(n))
    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]; i = parent[i]
        return i
    def union(a, b):
        a, b = find(a), find(b)
        if a != b: parent[a] = b
    return find, union


def _items(o):
    """The object's loose parts grouped into touching items: [(vertex indices, face indices)]."""
    me = o.data; mw = o.matrix_world
    find, union = _uf(len(me.vertices))
    for e in me.edges: union(e.vertices[0], e.vertices[1])
    isl = {}
    for i in range(len(me.vertices)): isl.setdefault(find(i), [[], []])[0].append(i)
    for p in me.polygons: isl[find(p.vertices[0])][1].append(p.index)
    isl = list(isl.values())
    boxes = []
    for vs, fs in isl:
        pts = [mw @ me.vertices[i].co for i in vs]
        boxes.append((Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts))),
                      Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))))
    f2, u2 = _uf(len(isl))
    idx = sorted(range(len(isl)), key=lambda i: boxes[i][0].x)
    for a_pos, a in enumerate(idx):          # sweep along x: only neighbours can touch
        a0, a1 = boxes[a]
        for b in idx[a_pos + 1:]:
            b0, b1 = boxes[b]
            if b0.x > a1.x + TOUCH: break
            if all(a0[k] - TOUCH <= b1[k] and b0[k] - TOUCH <= a1[k] for k in (1, 2)):
                u2(a, b)
    items = {}
    for i, (vs, fs) in enumerate(isl):
        it = items.setdefault(f2(i), [[], []]); it[0] += vs; it[1] += fs
    return list(items.values())


def anchor(apply=True):
    props = [bpy.data.objects[n] for n in prop_names()]
    ground_bvh, _ = _world_bvh([bpy.data.objects[n] for n in GROUND if n in bpy.data.objects])
    prop_bvh, owner = _world_bvh(props)
    items = []; face_item = {}
    for o in props:
        mw = o.matrix_world
        for vs, fs in _items(o):
            pts = [mw @ o.data.vertices[i].co for i in vs]
            k = len(items)
            items.append({"obj": o, "verts": vs, "pts": pts, "zmin": min(p.z for p in pts)})
            for fi in fs: face_item[(o.name, fi)] = k
    drop = {}; moves = []
    for k in sorted(range(len(items)), key=lambda k: items[k]["zmin"]):
        it = items[k]
        low = [p for p in it["pts"] if p.z < it["zmin"] + 0.01]
        step = max(1, len(low) // 12); low = low[::step][:12]
        best = None  # (gap, supporting item or None for the land)
        for p in low:
            hit = ground_bvh.ray_cast(Vector((p.x, p.y, p.z + MAX_SINK + 0.05)), DOWN)
            if hit[0] is not None:
                g = p.z - hit[0].z
                if best is None or abs(g) < abs(best[0]): best = (g, None)
            origin = p + Vector((0, 0, -0.0005))
            for _ in range(8):
                loc, nrm, fidx, dist = prop_bvh.ray_cast(origin, DOWN, MAX_GAP + 0.05)
                if loc is None: break
                j = face_item.get(owner[fidx])
                if j == k:
                    origin = loc + Vector((0, 0, -0.0005)); continue
                g = p.z - loc.z
                if g >= -EPS and (best is None or abs(g) < abs(best[0])):  # only the land lifts things out
                    best = (g, j)
                break
        if best is None or best[0] > MAX_GAP or best[0] < -MAX_SINK:
            drop[k] = 0.0; continue
        gap, sup = best
        d = (gap if abs(gap) > EPS else 0.0) + (drop.get(sup, 0.0) if sup is not None else 0.0)
        drop[k] = d
        if abs(d) > EPS:
            moves.append((it["obj"].name, len(it["verts"]), round(it["zmin"], 2), round(d, 3), "on prop" if sup is not None else "on land"))
    if apply:
        for k, d in drop.items():
            if abs(d) <= EPS: continue
            o = items[k]["obj"]
            local = o.matrix_world.inverted().to_3x3() @ Vector((0, 0, -d))
            for i in items[k]["verts"]:
                o.data.vertices[i].co += local
        for o in props: o.data.update()
    return {"items": len(items), "moved": len(moves), "biggest": sorted(moves, key=lambda m: -abs(m[3]))[:15]}
