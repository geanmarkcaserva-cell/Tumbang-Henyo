
import bpy, bmesh, math, random, os
from mathutils import Vector, Matrix, Euler
TEX = r"C:\Users\user\Documents\tumbang-henyo\art\source\textures"

def ps1_mat(name, img, alpha=False):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True; nt = m.node_tree; nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial"); bs = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bs.outputs[0], out.inputs[0]); bs.inputs["Roughness"].default_value = 0.95
    if "Specular IOR Level" in bs.inputs: bs.inputs["Specular IOR Level"].default_value = 0.05
    t = nt.nodes.new("ShaderNodeTexImage"); t.image = bpy.data.images.load(os.path.join(TEX, img), check_existing=True)
    t.interpolation = "Closest"
    nt.links.new(t.outputs["Color"], bs.inputs["Base Color"])
    if alpha:
        nt.links.new(t.outputs["Alpha"], bs.inputs["Alpha"])
        m.use_backface_culling = False
        if hasattr(m, "surface_render_method"): m.surface_render_method = "DITHERED"
        m.blend_method = "CLIP" if hasattr(m, "blend_method") else None
    return m

M = dict(bark=ps1_mat("PS1_Bark", "bark_ps1.png"), palmbark=ps1_mat("PS1_PalmBark", "palm_bark_ps1.png"),
         pinebark=ps1_mat("PS1_PineBark", "pine_bark_ps1.png"),
         leaf=ps1_mat("PS1_Leaf_Broad", "leaves_broad_ps1.png", True), leaf2=ps1_mat("PS1_Leaf_Broad2", "leaves_broad2_ps1.png", True),
         pine=ps1_mat("PS1_Leaf_Pine", "leaves_pine_ps1.png", True), frond=ps1_mat("PS1_Palm_Frond", "palm_frond_ps1.png", True),
         grass=ps1_mat("PS1_Grass", "grass_ps1.png", True))

class Build:
    def __init__(self): self.bm = bmesh.new(); self.uv = self.bm.loops.layers.uv.new("UVMap"); self.mats = []
    def mi(self, m):
        if m not in self.mats: self.mats.append(m)
        return self.mats.index(m)
    def face(self, pts, uvs, m):
        v = [self.bm.verts.new(Vector(p)) for p in pts]
        f = self.bm.faces.new(v); f.material_index = self.mi(m)
        for l, uv in zip(f.loops, uvs): l[self.uv].uv = uv
    def card(self, center, w, h, rot, m, u0=0, u1=1):
        R = rot.to_matrix(); c = Vector(center)
        pts = [c + R @ Vector(p) for p in [(-w/2, 0, -h/2), (w/2, 0, -h/2), (w/2, 0, h/2), (-w/2, 0, h/2)]]
        self.face(pts, [(u0, 0), (u1, 0), (u1, 1), (u0, 1)], m)
    def trunk(self, path, radii, m, sides=6, vrep=2.0):
        rings = []
        for p, r in zip(path, radii):
            rings.append([Vector(p) + Vector((r*math.cos(2*math.pi*i/sides), r*math.sin(2*math.pi*i/sides), 0)) for i in range(sides)])
        zacc = [0.0]
        for i in range(1, len(path)): zacc.append(zacc[-1] + (Vector(path[i]) - Vector(path[i-1])).length)
        for k in range(len(rings)-1):
            for i in range(sides):
                j = (i+1) % sides
                self.face([rings[k][i], rings[k][j], rings[k+1][j], rings[k+1][i]],
                          [(i/sides, zacc[k]/vrep), ((i+1)/sides, zacc[k]/vrep), ((i+1)/sides, zacc[k+1]/vrep), (i/sides, zacc[k+1]/vrep)], m)
    def roots(self, n, r0, length, m, seed):
        rnd = random.Random(seed)
        for k in range(n):
            a = 2*math.pi*k/n + rnd.uniform(-0.3, 0.3); L = length*rnd.uniform(0.7, 1.2)
            d = Vector((math.cos(a), math.sin(a), 0)); side = Vector((-d.y, d.x, 0)) * r0*0.55
            base = d * r0*0.6
            self.face([base - side, base + side + Vector((0,0,0.0)), d*L + Vector((0,0,0.03)), base + Vector((0,0,0.55))],
                      [(0,0),(1,0),(0.5,0.1),(0.5,0.4)], m)
            self.face([base + side, base - side, base + Vector((0,0,0.55)), d*L + Vector((0,0,0.03))],
                      [(1,0),(0,0),(0.5,0.4),(0.5,0.1)], m)
    def write(self, mesh):
        mesh.materials.clear()
        for m in self.mats: mesh.materials.append(m)
        self.bm.normal_update(); self.bm.to_mesh(mesh); self.bm.free(); mesh.update()

def broadleaf(mesh, seed, leaf, crown_r=2.9, crown_z=5.4, trunk_h=3.6):
    rnd = random.Random(seed); b = Build()
    lean = Vector((rnd.uniform(-0.3, 0.3), rnd.uniform(-0.3, 0.3), 0))
    path = [(0,0,0), (lean.x*0.3, lean.y*0.3, trunk_h*0.45), (lean.x*0.7, lean.y*0.7, trunk_h), (lean.x, lean.y, crown_z+0.6)]
    b.trunk(path, [0.34, 0.24, 0.17, 0.08], M["bark"], vrep=2.5)
    b.roots(5, 0.34, 1.0, M["bark"], seed)
    for k in range(4):   # branches as thin twisted strips
        a = rnd.uniform(0, 2*math.pi); z = rnd.uniform(trunk_h*0.8, crown_z)
        p0 = Vector((lean.x*0.8, lean.y*0.8, z)); p1 = p0 + Vector((math.cos(a), math.sin(a), 0.5)) * rnd.uniform(1.2, 2.0)
        sd = Vector((-math.sin(a), math.cos(a), 0)) * 0.06
        b.face([p0 - sd, p0 + sd, p1 + sd*0.3, p1 - sd*0.3], [(0,0),(0.3,0),(0.3,1),(0,1)], M["bark"])
    for k in range(16):  # leaf cards around the crown, tilted every which way
        a = rnd.uniform(0, 2*math.pi); rr = crown_r * math.sqrt(rnd.uniform(0.1, 1.0))
        c = (lean.x + rr*math.cos(a), lean.y + rr*math.sin(a), crown_z + rnd.uniform(-1.3, 1.5) - rr*0.25)
        s = rnd.uniform(2.4, 3.4)
        b.card(c, s, s, Euler((rnd.uniform(-1.2, 1.2), rnd.uniform(-0.4, 0.4), a + rnd.uniform(-0.6, 0.6))), leaf)
    for k in range(3):   # big crossed cards for the silhouette
        b.card((lean.x, lean.y, crown_z + 0.3), crown_r*2.2, crown_r*1.9, Euler((0, 0, k*math.pi/3 + rnd.uniform(-0.2, 0.2))), leaf)
    b.write(mesh)

def pine(mesh, seed, H=10.5):
    """PS1 conifer: a trunk with stacked cones of needle cards."""
    rnd = random.Random(seed); b = Build()
    b.trunk([(0,0,0),(0,0,H*0.5),(0,0,H)], [0.26, 0.17, 0.05], M["pinebark"], vrep=3.0)
    b.roots(5, 0.26, 0.8, M["pinebark"], seed)
    tiers = 5; sides = 7
    for t in range(tiers):
        z_bot = 2.2 + t * (H - 3.0) / tiers
        R = 3.0 * (1 - t / (tiers + 0.6)) + 0.5
        z_top = z_bot + R * 0.95 + 0.6
        rot = rnd.uniform(0, 2*math.pi)
        ring = [Vector((R*math.cos(rot + 2*math.pi*i/sides), R*math.sin(rot + 2*math.pi*i/sides), z_bot + rnd.uniform(-0.25, 0.15))) for i in range(sides)]
        apex = Vector((0, 0, z_top))
        for i in range(sides):
            j = (i + 1) % sides
            al = apex + (ring[i] - apex) * 0.08; ar = apex + (ring[j] - apex) * 0.08
            b.face([ring[i], ring[j], ar, al], [(0, 0), (1, 0), (0.55, 1), (0.45, 1)], M["pine"])
    b.card((0, 0, H - 0.3), 1.0, 1.6, Euler((0, 0, 0)), M["pine"]); b.card((0, 0, H - 0.3), 1.0, 1.6, Euler((0, 0, math.pi/2)), M["pine"])
    b.write(mesh)

def coconut(mesh, seed, H=8.0):
    rnd = random.Random(seed); b = Build()
    bend = Vector((rnd.uniform(-1.2, 1.2), rnd.uniform(-1.2, 1.2), 0))
    path = []; radii = []
    for i in range(6):
        t = i / 5; path.append(tuple(bend * (t*t) + Vector((0, 0, H*t)))); radii.append(0.24 - 0.08*t)
    b.trunk(path, radii, M["palmbark"], vrep=1.6)
    top = Vector(path[-1])
    for k in range(10):   # fronds: 2 bent segments each
        a = 2*math.pi*k/10 + rnd.uniform(-0.2, 0.2); L = rnd.uniform(3.2, 4.2); w = rnd.uniform(1.0, 1.3)
        d = Vector((math.cos(a), math.sin(a), 0)); side = Vector((-d.y, d.x, 0)) * (w/2)
        up = rnd.uniform(0.25, 0.6)
        p0 = top; p1 = top + d * (L*0.5) + Vector((0, 0, up)); p2 = top + d * L + Vector((0, 0, up - rnd.uniform(1.0, 1.8)))
        b.face([p0 - side*0.3, p1 - side, p1 + side, p0 + side*0.3], [(0,0),(0.5,0),(0.5,1),(0,1)], M["frond"])
        b.face([p1 - side, p2 - side*0.2, p2 + side*0.2, p1 + side], [(0.5,0),(1,0.35),(1,0.65),(0.5,1)], M["frond"])
    b.write(mesh)

def grass(mesh, seed, blades):
    rnd = random.Random(seed); b = Build()
    for k in range(blades):
        a = rnd.uniform(0, 2*math.pi); h = rnd.uniform(0.28, 0.62); w = rnd.uniform(0.05, 0.09)
        lean = rnd.uniform(0.1, 0.35)
        base = Vector((math.cos(a), math.sin(a), 0)) * rnd.uniform(0, 0.12)
        side = Vector((-math.sin(a), math.cos(a), 0)) * w
        tip = base + Vector((math.cos(a)*lean*h, math.sin(a)*lean*h, h))
        b.face([base - side, base + side, tip], [(0, 0), (1, 0), (0.5, 1)], M["grass"])
    b.write(mesh)

src = bpy.data.collections["Foliage_Sources"]
broadleaf(bpy.data.meshes["PH_Mango_A"], 11, M["leaf"])
broadleaf(bpy.data.meshes["PH_Mango_B"], 23, M["leaf2"], crown_r=3.2, crown_z=5.8)
broadleaf(bpy.data.meshes["PH_Mango_C"], 37, M["leaf"], crown_r=2.5, crown_z=4.8, trunk_h=3.0)
coconut(bpy.data.meshes["PH_Coconut_A"], 5, H=8.0)
coconut(bpy.data.meshes["PH_Coconut_B"], 9, H=9.2)
pine(bpy.data.meshes["PH_Pine"], 3)
for nm, sd, n in (("PS1_Grass_A", 1, 7), ("PS1_Grass_B", 2, 10)):
    me = bpy.data.meshes.get(nm) or bpy.data.meshes.new(nm)
    grass(me, sd, n)
    ob = bpy.data.objects.get(nm) or bpy.data.objects.new(nm, me)
    if ob.name not in src.objects: src.objects.link(ob)
    ob.location = (300 + 12*(sd+1), -260, 0)
for n in ["PH_Mango_A","PH_Mango_B","PH_Mango_C","PH_Coconut_A","PH_Coconut_B","PH_Pine","PS1_Grass_A","PS1_Grass_B"]:
    me = bpy.data.meshes[n]; print(n, len(me.polygons))
