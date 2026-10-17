
# NOTE: re-running this rebuilds the 4 houses from scratch and would undo hand edits
# made in Blender (e.g. the roof clean-up). For additions use add_house_details.py.
import bpy, bmesh, math, os
from mathutils import Vector, Matrix
TEX = r"C:\Users\user\Documents\tumbang-henyo\art\source\textures"

# ---------------- materials ----------------
MATS = {}
def mat(name, img=None, color=(0.5,0.5,0.5), size=2.0, rot=False, fit=False, two_sided=False, rough=0.9):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree; nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial"); out.location = (300, 0)
    bs = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bs.outputs[0], out.inputs[0])
    bs.inputs["Roughness"].default_value = rough
    if "Specular IOR Level" in bs.inputs: bs.inputs["Specular IOR Level"].default_value = 0.15
    if img:
        t = nt.nodes.new("ShaderNodeTexImage"); t.location = (-350, 0)
        t.image = bpy.data.images.load(os.path.join(TEX, img), check_existing=True)
        nt.links.new(t.outputs["Color"], bs.inputs["Base Color"])
    else:
        bs.inputs["Base Color"].default_value = (*color, 1)
    m.use_backface_culling = not two_sided
    su, sv = (size, size) if not isinstance(size, tuple) else size
    m["tex_size"] = su; m["tex_size_v"] = sv; m["uv_rot"] = rot; m["uv_fit"] = fit
    MATS[name] = m
    return m

mat("TH_Roof_Rust", "rusty_corrugated_iron_diff_1k.jpg", size=2.0, two_sided=True)
mat("TH_Roof_Worn", "worn_corrugated_iron_diff_1k.jpg", size=1.8, two_sided=True)
mat("TH_Roof_Red", "rusty_painted_metal_diff_1k.jpg", size=2.2, two_sided=True)
mat("TH_Concrete", "dirty_concrete_diff_1k.jpg", size=3.0)
mat("TH_Plaster_Moss", "worn_mossy_plasterwall_diff_1k.jpg", size=2.4)
mat("TH_Blue_Plaster", "blue_plaster_weathered_diff_1k.jpg", size=2.0)
mat("TH_Red_Peel", "peeling_painted_wall_diff_1k.jpg", size=1.8)
mat("TH_Rust_Wall", "rusty_metal_sheet_diff_1k.jpg", size=2.0)
mat("TH_Wood", "weathered_brown_planks_diff_1k.jpg", size=1.8)
mat("TH_Door", "weathered_brown_planks_diff_1k.jpg", size=1.4, rot=True)
mat("TH_Siding_Blue", "blue_painted_planks_diff_1k.jpg", size=1.0)
mat("TH_Timber", "weathered_peeling_timber_diff_1k.jpg", size=1.1, rot=True)
mat("TH_RawPlank", "raw_plank_wall_diff_1k.jpg", size=1.4, rot=True)
mat("TH_Shelves", "shelves_goods.jpg", fit=True, rough=0.8)
mat("TH_Sign_Caserva", "sign_caserva.jpg", fit=True, rough=0.6)
mat("TH_Sign_Nena", "sign_nena_old.jpg", fit=True, rough=0.6)
mat("TH_CHB", "chb_wall.jpg", size=(1.2, 1.8))
mat("TH_Shelves_A", "shelves_store_a.jpg", fit=True, rough=0.8)
mat("TH_Shelves_B", "shelves_store_b.jpg", fit=True, rough=0.8)
mat("TH_Sign_Cig", "sign_cig_billboard.jpg", fit=True, rough=0.7)
mat("TH_Poster", "poster_cig.jpg", fit=True, rough=0.7)
mat("TH_Tarp", None, color=(0.05, 0.25, 0.62), rough=0.6, two_sided=True)
mat("TH_Dark", None, color=(0.03, 0.025, 0.02), rough=1.0)
mat("TH_Rubber", None, color=(0.04, 0.04, 0.045), rough=0.8)
mat("TH_Drum", None, color=(0.05, 0.22, 0.55), rough=0.5)

# ---------------- geometry helpers ----------------
class House:
    def __init__(self, name):
        self.name = name; self.bm = bmesh.new(); self.slots = []
    def mi(self, mname):
        if mname not in self.slots: self.slots.append(mname)
        return self.slots.index(mname)
    def box(self, mn, mx, m, skip=("-z",), M=None, face_mats=None):
        bm = self.bm
        x0,y0,z0 = mn; x1,y1,z1 = mx
        c = [Vector(p) for p in [(x0,y0,z0),(x1,y0,z0),(x1,y1,z0),(x0,y1,z0),(x0,y0,z1),(x1,y0,z1),(x1,y1,z1),(x0,y1,z1)]]
        if M is not None: c = [M @ p for p in c]
        v = [bm.verts.new(p) for p in c]
        faces = {"-z":(0,3,2,1), "+z":(4,5,6,7), "-y":(0,1,5,4), "+y":(2,3,7,6), "-x":(3,0,4,7), "+x":(1,2,6,5)}
        for k, idx in faces.items():
            if k in skip: continue
            f = bm.faces.new([v[i] for i in idx])
            mm = (face_mats or {}).get(k, m)
            f.material_index = self.mi(mm)
    def quad(self, pts, m):
        v = [self.bm.verts.new(Vector(p)) for p in pts]
        f = self.bm.faces.new(v); f.material_index = self.mi(m)
    def sheet(self, p0, p1, p2, waves, amp, m):
        """Roof / awning sheet. Kept LOW-POLY on purpose (one quad): the corrugation
        is in the texture. (waves/amp are ignored; kept so old calls still work.)"""
        p0, p1, p2 = Vector(p0), Vector(p1), Vector(p2)
        q = [p0, p1, p1 + (p2 - p0), p2]
        n = (q[1]-q[0]).cross(q[3]-q[0])
        if n.z < 0: q = q[::-1]
        v = [self.bm.verts.new(c) for c in q]
        f = self.bm.faces.new(v); f.material_index = self.mi(m)

    def cyl(self, center, r, h, sides, m, cap=True):
        cx, cy, cz = center; idx = self.mi(m)
        bot = [self.bm.verts.new((cx + r*math.cos(2*math.pi*i/sides), cy + r*math.sin(2*math.pi*i/sides), cz)) for i in range(sides)]
        top = [self.bm.verts.new((v.co.x, v.co.y, cz + h)) for v in bot]
        for i in range(sides):
            j = (i + 1) % sides
            f = self.bm.faces.new([bot[i], bot[j], top[j], top[i]]); f.material_index = idx
        if cap:
            f = self.bm.faces.new(top); f.material_index = idx
    def finish(self, offset_x=0.0, coll=None):
        bm = self.bm
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0005)
        bm.normal_update()
        uv = bm.loops.layers.uv.new("UVMap")
        for f in bm.faces:
            m = MATS[self.slots[f.material_index]]
            n = f.normal; ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
            def proj(co):
                if az >= ax and az >= ay: return (co.x, co.y)
                if ax >= ay: return (co.y if n.x > 0 else -co.y, co.z)
                return (-co.x if n.y > 0 else co.x, co.z)
            pts = [proj(l.vert.co) for l in f.loops]
            if m["uv_fit"]:
                us = [p[0] for p in pts]; vs = [p[1] for p in pts]
                u0, u1, v0, v1 = min(us), max(us), min(vs), max(vs)
                for l, p in zip(f.loops, pts):
                    l[uv].uv = ((p[0]-u0)/max(u1-u0,1e-6), (p[1]-v0)/max(v1-v0,1e-6))
            else:
                s = m["tex_size"]; sv = m.get("tex_size_v", s)
                for l, p in zip(f.loops, pts):
                    u, v = p[0]/s, p[1]/sv
                    if m["uv_rot"]: u, v = v, u
                    l[uv].uv = (u, v)
        me = bpy.data.meshes.get(self.name) or bpy.data.meshes.new(self.name)
        me.materials.clear()  # (clearing materials after to_mesh wipes the face material indices)
        for s in self.slots: me.materials.append(MATS[s])
        bm.to_mesh(me); bm.free()
        ob = bpy.data.objects.get(self.name)
        if ob is None:
            ob = bpy.data.objects.new(self.name, me)
        ob.data = me
        for c in list(ob.users_collection): c.objects.unlink(ob)
        coll.objects.link(ob)
        ob.location = (offset_x, 0, 0)
        return ob

def window(h, x0, x1, z0, z1, y=0.0, frame="TH_Timber", flap=None, bars=0):
    """Dark window on a wall facing -Y at plane y, with a frame, optional bars and flap awning."""
    d = 0.02
    h.quad([(x0, y-d, z0), (x1, y-d, z0), (x1, y-d, z1), (x0, y-d, z1)], "TH_Dark")
    t = 0.09
    h.box((x0-t, y-0.08, z0-t), (x1+t, y, z0), frame, skip=())
    h.box((x0-t, y-0.08, z1), (x1+t, y, z1+t), frame, skip=())
    h.box((x0-t, y-0.08, z0), (x0, y, z1), frame, skip=())
    h.box((x1, y-0.08, z0), (x1+t, y, z1), frame, skip=())
    for i in range(bars):
        bx = x0 + (x1-x0) * (i+1) / (bars+1)
        h.box((bx-0.025, y-0.06, z0), (bx+0.025, y-0.03, z1), "TH_Rubber", skip=("-z","+z"))
    if flap:  # timber flap propped open above the window
        ang = math.radians(flap)
        M = Matrix.Translation((0, y, z1+t)) @ Matrix.Rotation(-ang, 4, "X")
        h.box((x0-0.15, -0.02, -0.04), (x1+0.15, 0.0, 0.0), "TH_Timber", skip=(), M=M) if False else None
        # flap as a thin box hinged at the top of the window, swung out by ang
        L = (z1 - z0) * 0.8
        M = Matrix.Translation((0, y, z1+t+0.02)) @ Matrix.Rotation(ang, 4, "X")
        h.box((x0-0.15, -L, -0.04), (x1+0.15, 0.0, 0.0), "TH_Timber", skip=(), M=M)

def tilted_quad(h, cx, y, cz, w, ht, m, tilt_deg=0.0):
    """Upright quad facing -Y, centred at (cx, y, cz), rotated tilt_deg in its plane."""
    t = math.radians(tilt_deg); c, s_ = math.cos(t), math.sin(t)
    pts = []
    for dx, dz in [(-w/2, -ht/2), (w/2, -ht/2), (w/2, ht/2), (-w/2, ht/2)]:
        pts.append((cx + dx*c - dz*s_, y, cz + dx*s_ + dz*c))
    h.quad(pts, m)

def poster(h, cx, cz, y=0.0, w=0.6, tilt=0.0, face="-y", x=None):
    """Faded cigarette poster stuck on a wall (portrait)."""
    ht = w * 1.47
    if face == "-y":
        tilted_quad(h, cx, y - 0.015, cz, w, ht, "TH_Poster", tilt)
    else:  # on a wall facing -X at plane x, cx is the y position
        t = math.radians(tilt); c, s_ = math.cos(t), math.sin(t)
        pts = []
        for dy, dz in [(w/2, -ht/2), (-w/2, -ht/2), (-w/2, ht/2), (w/2, ht/2)]:
            pts.append((x - 0.015, cx + dy*c - dz*s_, cz + -dy*s_ + dz*c))
        h.quad(pts, "TH_Poster")

def store(h, x0, x1, depth, shelves, sign_mat=None, wall="TH_Siding_Blue", counter="TH_RawPlank",
          awning="TH_Roof_Worn", y=0.0, sign_aspect=0.375, sign_tilt=0.0, billboard=None, twist=0.12):
    """Sari-sari kiosk on the front (-Y) of a wall at plane y: walls, real shop shelves inside,
    a counter, a slightly crooked corrugated awning and a sign or a big billboard."""
    yf = y - depth
    t = 0.15; zc = 0.95; zh = 2.35
    h.box((x0, yf, 0), (x1, yf+t, zc), wall)                        # counter wall
    h.box((x0, yf, 0), (x0+t, y, 2.75), wall)                       # left side
    h.box((x1-t, yf, 0), (x1, y, 2.75), wall)                       # right side
    h.box((x0, yf, zh), (x1, yf+t, 2.75), wall, skip=())            # header
    h.box((x0+t, yf+t, zh), (x1-t, y, zh+0.06), "TH_Dark", skip=()) # ceiling
    h.box((x0+t, yf+t, zc-0.05), (x1-t, y, zc), "TH_Dark", skip=("-z",))
    h.quad([(x0+t, y-0.03, zc), (x1-t, y-0.03, zc), (x1-t, y-0.03, zh), (x0+t, y-0.03, zh)], shelves)
    h.box((x0-0.1, yf-0.35, zc), (x1+0.12, yf+0.1, zc+0.06), counter, skip=())  # counter board
    for bx in (x0+0.3, x1-0.35):
        h.box((bx-0.04, yf-0.3, zc-0.25), (bx+0.04, yf, zc), "TH_Timber", skip=())
    top_z, low_z = 3.45, 2.55
    waves = max(6, int((x1-x0+0.6) / 0.2))
    # crooked awning: the right end sits a little higher than the left
    p0 = Vector((x0-0.3, y+0.05, top_z)); p1 = Vector((x1+0.3, y+0.05, top_z + twist))
    p2 = Vector((x0-0.3, yf-0.8, low_z))
    h.sheet(p0, p1, p2, waves, 0.035, awning)
    cx = (x0+x1)/2
    if billboard:
        bw = billboard; bh = bw * sign_aspect
        ys = yf - 0.55; zb = 2.95
        for px, lean in ((cx - bw*0.42, -2.5), (cx + bw*0.42, 3.0)):   # leaning posts
            M = Matrix.Translation((px, ys+0.12, 0)) @ Matrix.Rotation(math.radians(lean), 4, "Y")
            h.box((-0.05, -0.05, 0), (0.05, 0.05, zb + bh*0.6), "TH_Timber", skip=("-z",), M=M)
        M = Matrix.Translation((cx, ys + 0.06, zb + bh/2)) @ Matrix.Rotation(math.radians(sign_tilt), 4, "Y")
        h.box((-bw/2-0.06, 0, -bh/2-0.06), (bw/2+0.06, 0.07, bh/2+0.06), "TH_Timber", skip=(), M=M)
        tilted_quad(h, cx, ys + 0.05, zb + bh/2, bw, bh, sign_mat, sign_tilt)
    elif sign_mat:
        sw = min(2.9, (x1-x0) * 0.8); sh = sw * sign_aspect
        ys = yf - 0.25
        zs = top_z - (top_z-low_z) * ((y+0.05-ys) / (y+0.05-(yf-0.8))) + 0.05
        M = Matrix.Translation((cx, ys + 0.04, zs + sh/2 + 0.06)) @ Matrix.Rotation(math.radians(sign_tilt), 4, "Y")
        h.box((-sw/2-0.06, 0, -sh/2-0.06), (sw/2+0.06, 0.08, sh/2+0.06), "TH_Timber", skip=(), M=M)
        tilted_quad(h, cx, ys - 0.01, zs + sh/2 + 0.06, sw, sh, sign_mat, sign_tilt)

def tarp(h, p0, p1, p2, m="TH_Tarp"):
    """Sagging plastic tarp thrown over something."""
    h.sheet(p0, p1, p2, 3, 0.06, m)

def door(h, x0, x1, y=0.0, m="TH_Door", z1=2.1):
    h.box((x0, y-0.06, 0), (x1, y, z1), m)
    h.box((x0-0.08, y-0.09, z1), (x1+0.08, y, z1+0.1), "TH_Timber", skip=())

def roof(h, x0, x1, y_front, y_back, z_front, z_back, m, waves=None):
    waves = waves or max(8, int((x1-x0) / 0.22))
    h.sheet((x0, y_back, z_back), (x1, y_back, z_back), (x0, y_front, z_front), waves, 0.03, m)


# ---------------- collection ----------------
coll = bpy.data.collections.get("House_Variants")
if coll is None:
    coll = bpy.data.collections.new("House_Variants"); bpy.context.scene.collection.children.link(coll)

# ===== V1: two-storey concrete house, sari-sari store under a cigarette billboard =====
h = House("House_V1_Tindahan")
h.box((-2.4, 0, 0), (2.6, 4.5, 5.6), "TH_Concrete")
h.box((-4.2, 0.3, 0), (-2.4, 4.5, 6.1), "TH_Rust_Wall")
roof(h, -2.6, 2.9, -0.35, 4.8, 5.95, 5.62, "TH_Roof_Worn")
roof(h, -0.4, 1.6, -0.2, 2.6, 6.0, 5.82, "TH_Roof_Rust", waves=9)       # patched sheet
roof(h, -4.45, -2.3, 0.0, 4.8, 6.4, 6.1, "TH_Roof_Rust")
window(h, -1.6, 0.0, 3.6, 4.7, flap=50)
window(h, 1.0, 1.9, 3.8, 4.6, bars=3)
store(h, -1.8, 2.4, 1.8, "TH_Shelves_A", sign_mat="TH_Sign_Cig", billboard=3.7, sign_aspect=0.4, sign_tilt=-1.5)
h.box((-4.2, -1.4, 0), (-1.8, 0.3, 2.6), "TH_Wood")
door(h, -3.6, -2.6, y=-1.4)
poster(h, -2.15, 1.5, y=-1.4, w=0.45, tilt=4)
roof(h, -4.45, -1.65, -1.85, 0.5, 2.6, 3.05, "TH_Roof_Red")
v1 = h.finish(0.0, coll)

# ===== V2: blue two-storey house, red band, barred window, tire on the roof =====
h = House("House_V2_Blue")
h.box((-2.4, 0, 0), (2.4, 5.0, 2.9), "TH_Blue_Plaster")
h.box((-2.47, -0.07, 2.9), (2.47, 5.07, 3.35), "TH_Red_Peel", skip=())
h.box((-2.4, 0, 3.35), (2.4, 5.0, 5.8), "TH_Plaster_Moss", skip=())
h.box((-2.4, -0.06, 3.35), (-0.9, 0.0, 5.8), "TH_Rust_Wall", skip=("-z","+z","+y"))
roof(h, -2.7, 2.7, -0.4, 5.4, 6.05, 5.8, "TH_Roof_Worn")
roof(h, -2.0, -0.3, -0.3, 3.0, 6.12, 5.95, "TH_Roof_Red", waves=8)    # patched sheet
h.cyl((1.0, 2.6, 5.95), 0.38, 0.2, 12, "TH_Rubber")
h.cyl((-1.3, 3.6, 6.0), 0.36, 0.18, 12, "TH_Rubber")
window(h, 0.3, 1.6, 4.0, 5.0, bars=4)
roof(h, 0.15, 1.75, -0.5, 0.05, 5.15, 5.4, "TH_Roof_Worn", waves=7)
window(h, -1.7, -0.6, 1.0, 1.9, bars=0)
door(h, 0.6, 1.5, m="TH_RawPlank")
poster(h, -0.2, 1.4, w=0.5, tilt=-3)
h.box((0.45, -0.5, 0), (1.65, 0, 0.18), "TH_Concrete", skip=("-z",))
v2 = h.finish(12.0, coll)

# ===== V3: hollow-block shack with the ALING NENA store, wooden loft and a tarp =====
h = House("House_V3_Tindahan")
h.box((-3.2, 0, 0), (3.2, 5.0, 3.0), "TH_CHB")
h.box((-3.2, 0.9, 3.0), (0.4, 5.0, 5.2), "TH_Wood", skip=())
roof(h, -3.45, 3.45, -0.35, 5.3, 3.25, 3.0, "TH_Roof_Rust")
roof(h, -3.45, 0.65, 0.55, 5.3, 5.5, 5.25, "TH_Roof_Rust")
window(h, -2.4, -1.2, 3.7, 4.5, y=0.9, flap=40)
store(h, -0.4, 3.0, 1.5, "TH_Shelves_B", sign_mat="TH_Sign_Nena", wall="TH_RawPlank", counter="TH_Timber",
      awning="TH_Roof_Red", sign_tilt=2.5, twist=-0.1)
tarp(h, (0.6, 0.1, 3.55), (3.4, 0.1, 3.5), (0.6, -2.2, 2.6))
door(h, -2.5, -1.6)
window(h, -1.2, -0.65, 1.2, 1.9, bars=3)
poster(h, -0.9, 1.45, w=0.5, tilt=5)
poster(h, -2.9, 1.5, w=0.42, tilt=-6)
h.cyl((-3.7, 1.2, 0), 0.32, 0.9, 10, "TH_Drum")
v3 = h.finish(24.0, coll)

# ===== V4: tall narrow rusty house with a wooden annex =====
h = House("House_V4_Tall")
h.box((-1.8, 0, 0), (1.8, 4.2, 6.4), "TH_Rust_Wall")
h.box((1.8, 0.8, 0), (3.6, 4.2, 3.6), "TH_CHB")
roof(h, -2.1, 2.1, -0.4, 4.6, 6.7, 6.4, "TH_Roof_Worn")
roof(h, 1.7, 3.85, 0.5, 4.5, 3.85, 3.6, "TH_Roof_Rust", waves=10)
window(h, -0.9, 0.5, 4.2, 5.2, flap=55)
window(h, 2.3, 3.1, 1.4, 2.1, y=0.8, bars=3)
h.quad([(0.7, -0.02, 2.9), (1.6, -0.02, 2.95), (1.62, -0.02, 3.9), (0.68, -0.02, 3.85)], "TH_RawPlank")  # plywood patch
h.box((-2.0, -1.6, 0), (2.4, 0, 2.5), "TH_Wood")
door(h, -1.3, -0.4, y=-1.6)
window(h, 0.7, 1.6, 1.2, 1.8, y=-1.6)
roof(h, -2.25, 2.65, -2.0, 0.25, 2.55, 2.95, "TH_Roof_Red")
tarp(h, (-2.3, 0.2, 3.05), (0.4, 0.2, 3.0), (-2.3, -2.1, 2.62))
v4 = h.finish(36.0, coll)

for ob in (v1, v2, v3, v4):
    print(ob.name, len(ob.data.polygons), "faces", [round(d,2) for d in ob.dimensions])
