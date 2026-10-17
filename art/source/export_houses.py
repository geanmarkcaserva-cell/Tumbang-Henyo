
import bpy, bmesh, os, json
BASES = ["House_V1_Tindahan","House_V2_Blue","House_V3_Tindahan","House_V4_Tall","House_V5_Shack","House_V6_CHB"]
def combine(base_name):
    """Merge a variant's visible pieces into one new mesh, origin at the variant's base location."""
    base = bpy.data.objects[base_name]; off = base.matrix_world.translation.copy()
    parts = [o for o in bpy.data.objects if o.type == "MESH" and (o.name == base_name or o.name.startswith(base_name + "."))
             and not o.hide_get() and not o.hide_viewport]
    mats = []; bm = bmesh.new()
    for o in parts:
        tmp = o.data.copy()
        M = o.matrix_world.copy(); M.translation -= off
        tmp.transform(M)
        if M.determinant() < 0: tmp.flip_normals()
        remap = []
        for m in tmp.materials:
            if m not in mats: mats.append(m)
            remap.append(mats.index(m))
        idx = [p.material_index for p in tmp.polygons]
        for p, i in zip(tmp.polygons, idx): p.material_index = remap[i] if remap else 0
        bm.from_mesh(tmp)
        bpy.data.meshes.remove(tmp)
    me = bpy.data.meshes.new(base_name + "__EXPORT")
    for m in mats: me.materials.append(m)
    bm.to_mesh(me); bm.free()
    return me
def export_houses(path=r"C:\Users\user\Documents\tumbang-henyo\art\environment\house_variants.glb"):
    coll = bpy.data.collections.new("_export_tmp"); bpy.context.scene.collection.children.link(coll)
    objs = []; foot = {}
    for b in BASES:
        me = combine(b)
        ob = bpy.data.objects.new(b + "__EXPORT", me); coll.objects.link(ob); objs.append((ob, b))
        foot[b] = [[round(c, 3) for c in v.co] for v in me.vertices]
    for o in bpy.context.view_layer.objects: o.select_set(False)
    for ob, b in objs: ob.select_set(True)
    for ob, b in objs: bpy.data.objects[b].name = b + "__ORIG"; ob.name = b
    win = bpy.context.window_manager.windows[0]
    area = next(a for a in win.screen.areas if a.type == "VIEW_3D"); region = next(r for r in area.regions if r.type == "WINDOW")
    try:
        with bpy.context.temp_override(window=win, area=area, region=region):
            r = bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True, export_apply=True,
                export_cameras=False, export_lights=False, export_animations=False, export_image_format="JPEG", export_image_quality=88)
    finally:
        for ob, b in objs:
            ob.name = b + "__EXPORT"; bpy.data.objects[b + "__ORIG"].name = b
    info = {b: len(ob.data.polygons) for ob, b in objs}
    for ob, b in objs:
        me = ob.data; bpy.data.objects.remove(ob); bpy.data.meshes.remove(me)
    bpy.data.collections.remove(coll)
    json.dump(foot, open(r"C:\Users\user\Documents\tumbang-henyo\art\source\house_footprints.json", "w"))
    return r, info
