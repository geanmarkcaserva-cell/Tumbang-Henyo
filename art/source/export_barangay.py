# Export the barangay from barangay_land.blend for the game:
#   art/environment/barangay_env.glb   - land, roads, electric posts and wires (one model)
#   art/environment/barangay_props.glb - hand-placed props (stalls, umbrellas, tires, hollow blocks...)
#
#   exec(open(r"C:\Users\user\Documents\tumbang-henyo\art\source\export_barangay.py").read()); print(export_env()); print(export_props())
#
# Nothing in the .blend is changed: objects are copied, photos bigger than MAX_TEX are shrunk on
# the copies, exported, and the copies are deleted again.
# Houses and plants are NOT exported here (they come from barangay_layout.json).
import bpy, os

ROOT = r"C:\Users\user\Documents\tumbang-henyo\art\environment"
MAX_TEX = 1024
ENV = ["Court_Apron", "Road_Main", "Road_Side", "Path_Alley_L", "Terrain", "Electric_Posts.049"]
PROP_COLLECTIONS = ["Miscs"]          # whole collections of props
PROP_EXTRA = ["fishbolbol.001", "pan.001"]  # props that ended up in other collections


def prop_names():
    """Props: the Miscs collection, loose meshes in the scene root, and PROP_EXTRA."""
    names = []
    for c in PROP_COLLECTIONS:
        names += [o.name for o in bpy.data.collections[c].objects if o.type == "MESH"]  # not its "Props" child (fences/posts)
    names += [o.name for o in bpy.context.scene.collection.objects if o.type == "MESH"]
    names += [n for n in PROP_EXTRA if n in bpy.data.objects]
    return names


def _game_material(m, made):
    if m is None or not m.use_nodes:
        return m
    if m.name in made:
        return made[m.name]
    big = [n for n in m.node_tree.nodes if n.type == "TEX_IMAGE" and n.image and max(n.image.size) > MAX_TEX]
    if not big:
        made[m.name] = m
        return m
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
    made[m.name] = c
    return c


def _export(names, path):
    coll = bpy.data.collections.new("_export_tmp"); bpy.context.scene.collection.children.link(coll)
    made = {}; copies = []; renamed = []
    for n in names:
        o = bpy.data.objects[n]
        c = o.copy(); c.data = o.data.copy(); c.parent = None
        c.matrix_world = o.matrix_world.copy()
        for i, m in enumerate(c.data.materials):
            c.data.materials[i] = _game_material(m, made)
        coll.objects.link(c); copies.append((c, n))
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    for c, n in copies:
        o = bpy.data.objects[n]; o.name = n + "__ORIG"; renamed.append(n)
        c.name = n; c.hide_set(False); c.select_set(True)
    win = bpy.context.window_manager.windows[0]
    area = next(a for a in win.screen.areas if a.type == "VIEW_3D"); region = next(r for r in area.regions if r.type == "WINDOW")
    try:
        with bpy.context.temp_override(window=win, area=area, region=region):
            r = bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                export_apply=True, export_cameras=False, export_lights=False, export_animations=False,
                export_image_format="AUTO")
    finally:
        info = {n: len(c.data.polygons) for c, n in copies}
        for c, n in copies:
            me = c.data; bpy.data.objects.remove(c); bpy.data.meshes.remove(me)
        for n in renamed:
            bpy.data.objects[n + "__ORIG"].name = n
        bpy.data.collections.remove(coll)
        for k, m in made.items():
            if m is not None and m.name.endswith("__GAME"):
                bpy.data.materials.remove(m)
        for img in [i for i in bpy.data.images if i.name.endswith("__GAME")]:
            bpy.data.images.remove(img)
    return r, round(os.path.getsize(path) / 1e6, 2), info


def export_env(path=ROOT + r"\barangay_env.glb"):
    return _export(ENV, path)


def export_props(path=ROOT + r"\barangay_props.glb"):
    return _export(prop_names(), path)
