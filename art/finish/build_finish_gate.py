# Rebuild: blender -b --factory-startup --python art/finish/build_finish_gate.py -- art/finish/finish_gate.glb <preview.png>
# Builds the FINISH gate: a white-rimmed pad with a cyan panel and the word
# FINISH, and a soft cyan light curtain rising round its back and sides.
# Blender: X across the court, -Y towards the runner, Z up.
import bpy, bmesh, sys, math
import numpy as np

argv = sys.argv[sys.argv.index("--") + 1:]
OUT, PREVIEW = argv[0], argv[1]

W, D = 18.0, 3.0          # pad size (the court is 18 m wide)
PAD_T = 0.12              # pad thickness (half of it sinks into the ground)
RIM = 0.3                 # white border round the cyan panel
CURTAIN_H = 3.2

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene


def mat(name, color, emit=0.0, rough=0.6, alpha_tex=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    if emit > 0.0:
        bsdf.inputs["Emission Color"].default_value = (*color, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emit
    if alpha_tex is not None:
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = alpha_tex
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
        try:
            m.surface_render_method = "BLENDED"
        except Exception:
            m.blend_method = "BLEND"
        m.use_backface_culling = False
    return m


def gradient_image(name, w, h, fn):
    img = bpy.data.images.new(name, w, h, alpha=True)
    px = np.zeros((h, w, 4), dtype=np.float32)
    for y in range(h):
        for x in range(w):
            px[y, x] = fn(x / (w - 1), y / (h - 1))
    img.pixels.foreach_set(px.ravel())
    img.pack()
    return img


# Light curtain texture: cyan, strongest at the bottom, fading out upwards,
# with a few faint vertical streaks (like the art). Kept see-through.
rng = np.random.default_rng(7)
streaks = np.clip(rng.normal(0.0, 1.0, 64), 0, None)
streaks = (streaks > 1.1) * 0.35
def curtain_px(u, v):
    fade = (1.0 - v) ** 1.6
    s = streaks[int(u * 63)] * (1.0 - v) ** 0.6
    a = 0.42 * fade + s * 0.5
    c = np.array([0.55, 0.95, 1.0]) * (0.85 + 0.15 * (1 - v))
    return (*c, min(a, 0.6))
curtain_img = gradient_image("finish_curtain", 64, 128, curtain_px)

# Soft halo on the ground round the pad.
def halo_px(u, v):
    dx = abs(u - 0.5) * 2.0
    dy = abs(v - 0.5) * 2.0
    d = max(dx ** 6 + dy ** 2.2, 0.0)
    a = max(0.0, 1.0 - d) ** 1.5 * 0.38
    return (0.55, 0.95, 1.0, a)
halo_img = gradient_image("finish_halo", 128, 32, halo_px)

M_RIM = mat("FinishRim", (0.92, 0.97, 1.0), emit=0.15, rough=0.5)
M_PANEL = mat("FinishPanel", (0.30, 0.86, 0.95), emit=0.35, rough=0.4)
M_TEXT = mat("FinishText", (1.0, 1.0, 1.0), emit=0.5, rough=0.4)
M_CURTAIN = mat("FinishCurtain", (0.55, 0.95, 1.0), alpha_tex=curtain_img)
M_HALO = mat("FinishHalo", (0.55, 0.95, 1.0), alpha_tex=halo_img)


def box(name, size, loc, material, bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    if bevel > 0:
        b = o.modifiers.new("bevel", "BEVEL")
        b.width = bevel
        b.segments = 1
        bpy.ops.object.modifier_apply(modifier="bevel")
    o.data.materials.append(material)
    return o


# Pad: white slab, half sunk into the ground; cyan panel inset on top.
box("PadRim", (W, D, PAD_T), (0, 0, 0.0), M_RIM, bevel=0.05)
box("PadPanel", (W - RIM * 2, D - RIM * 2, 0.02), (0, 0, PAD_T * 0.5), M_PANEL)

# FINISH in bold italic-ish letters, flat on the panel, read from the runner's side.
bpy.ops.object.text_add(location=(0, 0, 0))
t = bpy.context.active_object
t.name = "FinishText"
t.data.body = "FINISH"
t.data.align_x = "CENTER"
t.data.align_y = "CENTER"
t.data.shear = 0.22
t.data.extrude = 0.012
t.data.offset = 0.03   # fatter strokes, reads as bold
t.data.size = 1.0
bpy.context.view_layer.update()
dims = t.dimensions.copy()
k = min((W * 0.62) / dims.x, (D - RIM * 2 - 0.5) / dims.y)
t.scale = (k, k, 1.0)
bpy.ops.object.convert(target="MESH")
t = bpy.context.active_object
bpy.ops.object.transform_apply(scale=True)
t.location = (0, 0, PAD_T * 0.5 + 0.012)
t.data.materials.clear()
t.data.materials.append(M_TEXT)

# Light curtain: back and both sides, open at the front (the runner's side).
bm = bmesh.new()
uv = bm.loops.layers.uv.new()
hx, hy = W * 0.5 - 0.05, D * 0.5 - 0.05
walls = [((-hx, hy), (hx, hy)), ((-hx, -hy), (-hx, hy)), ((hx, hy), (hx, -hy))]
for (a, b) in walls:
    v0 = bm.verts.new((a[0], a[1], 0.02))
    v1 = bm.verts.new((b[0], b[1], 0.02))
    v2 = bm.verts.new((b[0], b[1], CURTAIN_H))
    v3 = bm.verts.new((a[0], a[1], CURTAIN_H))
    f = bm.faces.new((v0, v1, v2, v3))
    length = math.dist(a, b)
    for loop, (uu, vv) in zip(f.loops, [(0, 0), (length / 6.0, 0), (length / 6.0, 1), (0, 1)]):
        loop[uv].uv = (uu, vv)
me = bpy.data.meshes.new("FinishCurtain")
bm.to_mesh(me)
bm.free()
cur = bpy.data.objects.new("FinishCurtain", me)
scene.collection.objects.link(cur)
me.materials.append(M_CURTAIN)

# Ground halo.
bpy.ops.mesh.primitive_plane_add(size=1.0, location=(0, 0, 0.015))
h = bpy.context.active_object
h.name = "FinishHalo"
h.scale = (W + 3.0, D + 2.4, 1.0)
bpy.ops.object.transform_apply(scale=True)
h.data.materials.append(M_HALO)

bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_apply=True,
                          export_yup=True, export_materials="EXPORT")

# Quick preview render (Eevee) so the shape can be checked before Godot.
cam_data = bpy.data.cameras.new("cam")
cam = bpy.data.objects.new("cam", cam_data)
scene.collection.objects.link(cam)
cam.location = (0, -17, 6.5)
cam.rotation_euler = (math.radians(72), 0, 0)
scene.camera = cam
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
sun.rotation_euler = (math.radians(50), 0, math.radians(30))
scene.collection.objects.link(sun)
world = bpy.data.worlds.new("w")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.05, 0.06, 0.09, 1)
scene.world = world
bpy.ops.mesh.primitive_plane_add(size=60, location=(0, 0, -0.001))
g = bpy.context.active_object
g.data.materials.append(mat("ground", (0.25, 0.25, 0.27)))
scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE"
scene.render.resolution_x = 960
scene.render.resolution_y = 540
scene.render.filepath = PREVIEW
bpy.ops.render.render(write_still=True)
print("FINISH_GATE_OK", OUT)
