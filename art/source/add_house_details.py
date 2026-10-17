
import bpy, bmesh, math, os
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree
TEX = r"C:\Users\user\Documents\tumbang-henyo\art\source\textures"

def ensure_mat(name, img, rough=0.85):
    m = bpy.data.materials.get(name)
    if m: return m
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree; nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial"); bs = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bs.outputs[0], out.inputs[0]); bs.inputs["Roughness"].default_value = rough
    if "Specular IOR Level" in bs.inputs: bs.inputs["Specular IOR Level"].default_value = 0.15
    t = nt.nodes.new("ShaderNodeTexImage"); t.image = bpy.data.images.load(os.path.join(TEX, img), check_existing=True)
    nt.links.new(t.outputs["Color"], bs.inputs["Base Color"])
    m.use_backface_culling = True
    m["tex_size"] = 1.0; m["tex_size_v"] = 1.0; m["uv_rot"] = False; m["uv_fit"] = True
    return m
ensure_mat("TH_Signs", "signs_atlas.jpg", 0.5)
ensure_mat("TH_Tire", "tire.jpg", 0.9)

# atlas: 3 columns x 4 rows of 340x256 cells (2 px gap), banner spans cells 10-11
def cell_uv(i):
    if i == 10:
        return (342/1024, 1 - 4*256/1024, 1022/1024, 1 - 3*256/1024)
    c, r = i % 3, i // 3
    x0 = c*342
    return (x0/1024, 1 - (r+1)*256/1024, (x0+340)/1024, 1 - r*256/1024)
SIGN = dict(ICE=0, LOAD=1, UTANG=2, RICE=3, NOSMOKE=4, SCHOOL=5, FROZEN=6, EWALLET=7, YELO=8, PALOAD=9, BANNER=10)

class Add:
    def __init__(self, obj_name):
        self.ob = bpy.data.objects[obj_name]; self.me = self.ob.data
        self.bm = bmesh.new(); self.bm.from_mesh(self.me)
        self.bvh = BVHTree.FromBMesh(self.bm)
        self.uvl = self.bm.loops.layers.uv.active or self.bm.loops.layers.uv.new("UVMap")
        self.new = []; self.fixed_uv = {}
    def mi(self, name):
        mats = [m.name for m in self.me.materials]
        if name not in mats: self.me.materials.append(bpy.data.materials[name]); mats.append(name)
        return mats.index(name)
    def face(self, pts, m, uvs=None):
        v = [self.bm.verts.new(Vector(p)) for p in pts]
        f = self.bm.faces.new(v); f.material_index = self.mi(m); self.new.append(f)
        if uvs: self.fixed_uv[f] = uvs
        return f
    def box(self, mn, mx, m, M=None, skip=()):
        x0,y0,z0 = mn; x1,y1,z1 = mx
        c = [Vector(p) for p in [(x0,y0,z0),(x1,y0,z0),(x1,y1,z0),(x0,y1,z0),(x0,y0,z1),(x1,y0,z1),(x1,y1,z1),(x0,y1,z1)]]
        if M is not None: c = [M @ p for p in c]
        F = {"-z":(0,3,2,1), "+z":(4,5,6,7), "-y":(0,1,5,4), "+y":(2,3,7,6), "-x":(3,0,4,7), "+x":(1,2,6,5)}
        for k, idx in F.items():
            if k in skip: continue
            self.face([c[i] for i in idx], m)
    # --- windows on side walls (facing +X when side=+1, -X when side=-1) ---
    def side_window(self, x, y0, y1, z0, z1, side, bars=0):
        s = side; d = 0.02*s; t = 0.09; o = 0.08*s
        if s > 0: q = [(x+d,y0,z0),(x+d,y1,z0),(x+d,y1,z1),(x+d,y0,z1)]
        else:     q = [(x+d,y1,z0),(x+d,y0,z0),(x+d,y0,z1),(x+d,y1,z1)]
        self.face(q, "TH_Dark")
        xa, xb = (x, x+o) if s > 0 else (x+o, x)
        self.box((xa, y0-t, z0-t), (xb, y1+t, z0), "TH_Timber")
        self.box((xa, y0-t, z1), (xb, y1+t, z1+t), "TH_Timber")
        self.box((xa, y0-t, z0), (xb, y0, z1), "TH_Timber")
        self.box((xa, y1, z0), (xb, y1+t, z1), "TH_Timber")
        for i in range(bars):
            by = y0 + (y1-y0)*(i+1)/(bars+1)
            xa2, xb2 = (x+0.03, x+0.06) if s > 0 else (x-0.06, x-0.03)
            self.box((xa2, by-0.025, z0), (xb2, by+0.025, z1), "TH_Rubber", skip=("-z","+z"))
    # --- laminated signs from the atlas ---
    def sign(self, key, cx, cy, cz, w, facing="-y", tilt=0.0):
        u0, v0, u1, v1 = cell_uv(SIGN[key])
        h = w * (256/340) if key != "BANNER" else w * (256/680)
        a = math.radians(tilt); ca, sa = math.cos(a), math.sin(a)
        corners = [(-w/2,-h/2),(w/2,-h/2),(w/2,h/2),(-w/2,h/2)]
        uvs = [(u0,v0),(u1,v0),(u1,v1),(u0,v1)]
        pts = []
        for dx, dz in corners:
            rx, rz = dx*ca - dz*sa, dx*sa + dz*ca
            if facing == "-y": pts.append((cx+rx, cy-0.012, cz+rz))
            elif facing == "+x": pts.append((cx+0.012, cy+rx, cz+rz))
            else: pts.append((cx-0.012, cy-rx, cz+rz))
        self.face(pts, "TH_Signs", uvs)
    # --- textured tire lying on the roof, dropped onto the surface below ---
    def tire(self, x, y, r=0.38, h=0.2, sides=12):
        hit = self.bvh.ray_cast(Vector((x, y, 20)), Vector((0, 0, -1)))
        z = (hit[0].z if hit[0] else 6.0) - 0.03
        bot = [Vector((x + r*math.cos(2*math.pi*i/sides), y + r*math.sin(2*math.pi*i/sides), z)) for i in range(sides)]
        top = [p + Vector((0,0,h)) for p in bot]
        for i in range(sides):
            j = (i+1) % sides
            u_i = 0.5 + 0.5*i/sides; u_j = 0.5 + 0.5*(i+1)/sides
            self.face([bot[i], bot[j], top[j], top[i]], "TH_Tire", [(u_i,0.04),(u_j,0.04),(u_j,0.96),(u_i,0.96)])
        cap = [(0.25 + 0.245*math.cos(2*math.pi*i/sides), 0.5 + 0.49*math.sin(2*math.pi*i/sides)) for i in range(sides)]
        self.face(top, "TH_Tire", cap)
    def finish(self):
        bm = self.bm; bm.normal_update()
        mats = list(self.me.materials)
        for f in self.new:
            if f in self.fixed_uv:
                for l, uv in zip(f.loops, self.fixed_uv[f]): l[self.uvl].uv = uv
                continue
            m = mats[f.material_index]; s = m.get("tex_size", 2.0); sv = m.get("tex_size_v", s)
            n = f.normal; ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
            for l in f.loops:
                co = l.vert.co
                if az >= ax and az >= ay: p = (co.x, co.y)
                elif ax >= ay: p = (co.y if n.x > 0 else -co.y, co.z)
                else: p = (-co.x if n.y > 0 else co.x, co.z)
                u, v = p[0]/s, p[1]/sv
                if m.get("uv_rot"): u, v = v, u
                l[self.uvl].uv = (u, v)
        bm.to_mesh(self.me); bm.free(); self.me.update()
        print(self.ob.name, "+", len(self.new), "faces ->", len(self.me.polygons))

# ===== V2: retexture the existing tires, side windows, rice sign + load banner =====
a = Add("House_V2_Blue")
tire_faces = [f for f in a.bm.faces if a.me.materials[f.material_index].name == "TH_Rubber" and f.calc_center_median().z > 5.6]
ti = a.mi("TH_Tire")
for f in tire_faces:
    f.material_index = ti
    c = f.calc_center_median()
    if f.normal.z > 0.9:   # cap
        # find the tire centre = average of cap verts
        cx = sum(v.co.x for v in f.verts)/len(f.verts); cy = sum(v.co.y for v in f.verts)/len(f.verts)
        r = max((Vector((v.co.x-cx, v.co.y-cy))).length for v in f.verts)
        for l in f.loops:
            l[a.uvl].uv = (0.25 + 0.245*(l.vert.co.x-cx)/r, 0.5 + 0.49*(l.vert.co.y-cy)/r)
caps = [f for f in tire_faces if f.normal.z > 0.9]
centres = [(sum(v.co.x for v in f.verts)/len(f.verts), sum(v.co.y for v in f.verts)/len(f.verts)) for f in caps]
for f in tire_faces:
    if f.normal.z > 0.9: continue
    c = f.calc_center_median()
    cx, cy = min(centres, key=lambda q: (q[0]-c.x)**2 + (q[1]-c.y)**2)
    zs = [v.co.z for v in f.verts]; z0, z1 = min(zs), max(zs)
    angs = [math.atan2(l.vert.co.y-cy, l.vert.co.x-cx) % (2*math.pi) for l in f.loops]
    if max(angs) - min(angs) > math.pi: angs = [g + 2*math.pi if g < math.pi else g for g in angs]
    for l, g in zip(f.loops, angs):
        l[a.uvl].uv = (0.5 + 0.5*((g/(2*math.pi)) % 1.0001), 0.04 + 0.92*(l.vert.co.z-z0)/max(z1-z0, 1e-4))
a.side_window(2.4, 2.0, 3.0, 1.1, 1.9, +1)
a.side_window(-2.4, 2.0, 3.0, 1.1, 1.9, -1)
a.side_window(2.4, 1.8, 3.0, 4.0, 4.9, +1, bars=3)
a.side_window(-2.4, 2.2, 3.2, 4.0, 4.8, -1)
a.sign("BANNER", -1.2, 0.0, 2.45, 1.9, tilt=-1.0)
a.sign("RICE", 1.95, 0.0, 1.45, 0.5, tilt=3)
a.sign("ICE", -1.15, 0.0, 0.62, 0.45, tilt=-4)
a.finish()

# ===== V1 (cigarette billboard store) =====
a = Add("House_V1_Tindahan")
a.side_window(2.6, 1.4, 2.6, 1.1, 2.0, +1)
a.side_window(2.6, 1.6, 2.8, 3.8, 4.7, +1, bars=3)
a.side_window(-4.2, 1.8, 2.8, 3.9, 4.7, -1)
a.side_window(-4.2, -1.0, -0.4, 1.2, 1.8, -1)
a.sign("LOAD", 1.75, -1.8, 0.55, 0.5, tilt=2)
a.sign("YELO", 0.25, -1.8, 0.5, 0.46, tilt=-3)
a.sign("UTANG", -1.15, -0.06, 2.0, 0.42, tilt=4)
a.sign("NOSMOKE", -3.9, -1.4, 1.55, 0.38, tilt=-2)
a.tire(0.6, 2.4); a.tire(-1.6, 3.6)
a.finish()

# ===== V3 (Aling Nena) =====
a = Add("House_V3_Tindahan")
a.side_window(3.2, 2.0, 3.1, 1.2, 2.0, +1, bars=3)
a.side_window(-3.2, 2.0, 3.1, 1.2, 2.0, -1, bars=3)
a.side_window(-3.2, 2.4, 3.4, 3.7, 4.5, -1)
a.sign("SCHOOL", 0.2, -1.5, 0.55, 0.5, tilt=-2)
a.sign("FROZEN", 1.3, -1.5, 0.5, 0.46, tilt=3)
a.sign("EWALLET", 2.45, -1.5, 0.55, 0.46, tilt=-1)
a.sign("UTANG", 2.55, -0.06, 2.0, 0.4, tilt=-5)
a.tire(1.8, 2.5); a.tire(-1.9, 2.8)
a.finish()

# ===== V4 (tall house) =====
a = Add("House_V4_Tall")
a.side_window(-1.8, 1.5, 2.5, 4.3, 5.1, -1)
a.side_window(-1.8, 2.0, 2.9, 1.2, 1.9, -1)
a.side_window(1.8, 1.4, 2.4, 4.4, 5.2, +1, bars=3)
a.side_window(3.6, 2.0, 3.0, 1.3, 2.0, +1)
a.side_window(-2.0, -1.2, -0.5, 1.2, 1.8, -1)
a.sign("PALOAD", 2.0, -1.6, 1.15, 0.5, tilt=4)
a.tire(1.4, -0.9, r=0.34)
a.finish()
