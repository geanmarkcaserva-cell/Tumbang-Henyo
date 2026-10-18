
# Export every house variant in "house variantions.blend" to art/environment/house_variants.glb
# and write their footprints (art/source/house_footprints.json) for the layout scripts.
#
#   exec(open(r"C:\Users\user\Documents\tumbang-henyo\art\source\export_houses.py").read()); print(export_houses())
#
# Nothing in the .blend is changed: pieces are merged into temporary meshes, exported, then deleted.
import bpy, bmesh, os, json, math
from mathutils import Matrix, Vector

# Variants made of pieces named <base>, <base>.001, ... (origin = the base object's location).
BASES = ["House_V1_Tindahan", "House_V2_Blue", "House_V3_Tindahan", "House_V4_Tall", "House_V5_Shack", "House_V6_CHB"]
# Variants modelled by the user as single objects: export name -> (object, yaw in degrees that turns
# the model's front to face -Y, the same way the other variants face). Origin = bottom centre.
SINGLE = {
    "House_V7_Fence":     ("Cube", 0),
    "House_V8_Patchwork": ("Cube.001", 90),
    "House_V9_Kubo":      ("Cube.011", 0),
    "House_V10_Brick":    ("Cube.013", 0),
    "House_V11_Tindahan": ("Cube.025", 90),
    "House_V12_Kahoy":    ("balay na brown", 180),
    "House_V13_Semento":  ("cemento na balay", 180),
}
MAX_TEX = 1024  # photos bigger than this are shrunk for the game (the .blend keeps the originals)

def _add(bm, mats, ob, M):
    tmp = ob.data.copy()
    tmp.transform(M)
    if M.determinant() < 0: tmp.flip_normals()
    remap = []
    for m in tmp.materials:
        if m not in mats: mats.append(m)
        remap.append(mats.index(m))
    for p in tmp.polygons: p.material_index = remap[p.material_index] if remap else 0
    bm.from_mesh(tmp)
    bpy.data.meshes.remove(tmp)

def _finish(bm, mats, name):
    me = bpy.data.meshes.new(name + "__EXPORT")
    for m in mats: me.materials.append(m)
    bm.to_mesh(me); bm.free()
    return me

def combine(base_name):
    """Merge a variant's visible pieces into one new mesh, origin at the variant's base location."""
    parts = sorted([o for o in bpy.data.objects if o.type == "MESH" and (o.name == base_name or o.name.startswith(base_name + "."))
                    and o.name in bpy.context.view_layer.objects and not o.hide_get() and not o.hide_viewport], key=lambda o: o.name)
    # The base object if it still exists, else the first piece (e.g. after joining V1's pieces into .001).
    base = bpy.data.objects.get(base_name) or parts[0]
    off = base.matrix_world.translation.copy()
    mats = []; bm = bmesh.new()
    for o in parts:
        M = o.matrix_world.copy(); M.translation -= off
        _add(bm, mats, o, M)
    return _finish(bm, mats, base_name)

def single(name, obj_name, yaw):
    """One user-made object, front turned to -Y, origin at the centre of its base."""
    o = bpy.data.objects[obj_name]
    W = o.matrix_world
    pts = [W @ v.co for v in o.data.vertices]
    x0, x1 = min(p.x for p in pts), max(p.x for p in pts)
    y0, y1 = min(p.y for p in pts), max(p.y for p in pts)
    z0 = min(p.z for p in pts)
    M = Matrix.Rotation(math.radians(yaw), 4, "Z") @ Matrix.Translation(-Vector(((x0 + x1) / 2, (y0 + y1) / 2, z0))) @ W
    mats = []; bm = bmesh.new()
    _add(bm, mats, o, M)
    return _finish(bm, mats, name)

def _game_material(m, made):
    """Copy of a material with photos shrunk and shaders glTF can't read turned into a plain one."""
    if m is None or not m.use_nodes: return m
    if m.name in made: return made[m.name]
    nodes = m.node_tree.nodes
    tex = [n for n in nodes if n.type == "TEX_IMAGE" and n.image]
    has_bsdf = any(n.type == "BSDF_PRINCIPLED" for n in nodes)
    big = [n for n in tex if max(n.image.size) > MAX_TEX]
    if has_bsdf and not big:
        made[m.name] = m; return m
    c = m.copy(); c.name = m.name + "__GAME"
    for n in c.node_tree.nodes:
        if n.type == "TEX_IMAGE" and n.image and max(n.image.size) > MAX_TEX:
            key = n.image.name + "__GAME"
            img = bpy.data.images.get(key)
            if img is None:
                img = n.image.copy(); img.name = key
                w, h = n.image.size; k = MAX_TEX / max(w, h)
                img.scale(max(1, int(w * k)), max(1, int(h * k)))
            n.image = img
    if not has_bsdf:  # e.g. an emission/transparent mix: show the same picture on a plain surface
        nt = c.node_tree
        out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
        b = nt.nodes.new("ShaderNodeBsdfPrincipled")
        t = next((n for n in nt.nodes if n.type == "TEX_IMAGE" and n.image), None)
        if t: nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
        nt.links.new(b.outputs["BSDF"], out.inputs["Surface"])
    made[m.name] = c
    return c

def export_houses(path=r"C:\Users\user\Documents\tumbang-henyo\art\environment\house_variants.glb"):
    coll = bpy.data.collections.new("_export_tmp"); bpy.context.scene.collection.children.link(coll)
    objs = []; foot = {}; made = {}
    meshes = [(b, combine(b)) for b in BASES] + [(n, single(n, *SINGLE[n])) for n in SINGLE]
    for b, me in meshes:
        for i, m in enumerate(me.materials): me.materials[i] = _game_material(m, made)
        ob = bpy.data.objects.new(b + "__EXPORT", me); coll.objects.link(ob); objs.append((ob, b))
        foot[b] = [[round(c, 3) for c in v.co] for v in me.vertices]
    for o in bpy.context.view_layer.objects: o.select_set(False)
    for ob, b in objs: ob.select_set(True)
    renamed = []
    for ob, b in objs:
        clash = bpy.data.objects.get(b)
        if clash: clash.name = b + "__ORIG"; renamed.append(b)
        ob.name = b
    win = bpy.context.window_manager.windows[0]
    area = next(a for a in win.screen.areas if a.type == "VIEW_3D"); region = next(r for r in area.regions if r.type == "WINDOW")
    try:
        with bpy.context.temp_override(window=win, area=area, region=region):
            r = bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True, export_apply=True,
                export_cameras=False, export_lights=False, export_animations=False, export_image_format="JPEG", export_image_quality=88)
    finally:
        for ob, b in objs: ob.name = b + "__EXPORT"
        for b in renamed: bpy.data.objects[b + "__ORIG"].name = b
    info = {b: len(ob.data.polygons) for ob, b in objs}
    for ob, b in objs:
        me = ob.data; bpy.data.objects.remove(ob); bpy.data.meshes.remove(me)
    bpy.data.collections.remove(coll)
    for k, c in made.items():
        if c is not None and c.name.endswith("__GAME"): bpy.data.materials.remove(c)
    for img in [i for i in bpy.data.images if i.name.endswith("__GAME")]: bpy.data.images.remove(img)
    json.dump(foot, open(r"C:\Users\user\Documents\tumbang-henyo\art\source\house_footprints.json", "w"))
    return r, info
