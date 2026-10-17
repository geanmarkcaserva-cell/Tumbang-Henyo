
import bpy, os
def export_plants(path=r"C:\Users\user\Documents\tumbang-henyo\art\environment\barangay_plants.glb"):
    src = bpy.data.collections["Foliage_Sources"]
    lc = bpy.context.view_layer.layer_collection.children["Foliage_Sources"]
    was_ex = lc.exclude; lc.exclude = False
    objs = [o for o in src.all_objects if o.name.startswith(("PH_", "Card_", "PS1_"))]
    saved = {o.name: o.location.copy() for o in objs}
    for o in bpy.context.view_layer.objects: o.select_set(False)
    for o in objs: o.location = (0, 0, 0); o.hide_set(False); o.select_set(True)
    win = bpy.context.window_manager.windows[0]
    area = next(a for a in win.screen.areas if a.type == "VIEW_3D"); region = next(r for r in area.regions if r.type == "WINDOW")
    try:
        with bpy.context.temp_override(window=win, area=area, region=region):
            r = bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True, export_apply=True,
                                          export_cameras=False, export_lights=False, export_animations=False)
    finally:
        for o in objs: o.location = saved[o.name]
        lc.exclude = was_ex
    return r, [o.name for o in objs]
