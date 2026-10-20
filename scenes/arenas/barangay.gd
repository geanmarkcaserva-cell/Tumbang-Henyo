extends Node3D
## The barangay around the SK Court: flat land, roads and electric posts (one
## model), plus houses, plants and collisions laid out from
## barangay_layout.json (written by the scripts in art/source/).
##
## Plants are drawn as one MultiMesh per plant type, so thousands of grass
## clumps cost about the same as one. Small plants fade out with distance and
## cast no shadows (cheap on phones).
##
## Forced perspective: houses and trees far from the court are built bigger,
## so the barangay feels deeper than it is.

const ENV_SCENE := preload("res://art/environment/barangay_env.glb")
const PLANTS_SCENE := preload("res://art/environment/barangay_plants.glb")
## The textured house variants (art/source/house variantions.blend).
const HOUSES_SCENE := preload("res://art/environment/house_variants.glb")
## Hand-placed props around the court (stalls, umbrellas, tires, hollow blocks...),
## exported by art/source/export_barangay.py. Loaded only if the file exists.
const PROPS_PATH := "res://art/environment/barangay_props.glb"
## Props lower than this get no collision, so you can run over tires and blocks.
const PROP_MIN_COLLIDE_HEIGHT := 0.35
const LAYOUT_PATH := "res://art/environment/barangay_layout.json"
## Middle of the court; distances for forced perspective are measured from here.
const COURT_CENTRE := Vector2(0.0, -20.0)

@export var small_plant_fade_start := 30.0 ## metres from the camera
@export var small_plant_fade_end := 40.0
@export var card_alpha_cutoff := 0.4
@export_group("Trees grow with distance")
@export var tree_growth_start := 35.0 ## trees closer than this keep their size
@export var tree_growth_per_metre := 0.022 ## +2.2% size per metre beyond that
@export var tree_growth_max := 3.2


func _ready() -> void:
	var env := ENV_SCENE.instantiate()
	add_child(env)
	_build_props()
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	if layout == null:
		push_error("Barangay: can't read %s" % LAYOUT_PATH)
		return
	if layout.has("houses"):
		for n in env.find_children("House_*", "", true, false):
			n.queue_free()
		_build_houses(layout.houses)
	_build_plants(layout)
	_build_colliders(layout.boxes)


## The props model, with solid collision on everything tall enough to bump into.
func _build_props() -> void:
	if not ResourceLoader.exists(PROPS_PATH):
		return
	var props: Node3D = (load(PROPS_PATH) as PackedScene).instantiate()
	props.name = "Props"
	add_child(props)
	for mi in props.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or m.get_aabb().size.y * m.global_basis.get_scale().y < PROP_MIN_COLLIDE_HEIGHT:
			continue
		m.create_trimesh_collision()


func _build_houses(entries: Array) -> void:
	var library := HOUSES_SCENE.instantiate()
	var meshes := {}
	for mi in library.find_children("*", "MeshInstance3D", true, false):
		meshes[mi.name] = mi.mesh
	library.free()
	var root := Node3D.new()
	root.name = "Houses"
	add_child(root)
	for e in entries:
		var mesh: Mesh = meshes.get(e.name)
		if mesh == null:
			push_warning("Barangay: no house mesh %s" % e.name)
			continue
		var mi := MeshInstance3D.new()
		mi.name = "%s_%s" % [e.lot, e.name]
		mi.mesh = mesh
		var p: Array = e.p
		var s := float(e.get("s", 1.0))
		mi.transform = Transform3D(Basis(Vector3.UP, float(e.ry)).scaled(Vector3.ONE * s), Vector3(p[0], p[1], p[2]))
		if s > 1.05: # far-off scenery: the shadow would be outside the shadow range anyway
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.add_to_group("detail_heavy") # hidden in low detail mode (Settings)
		root.add_child(mi)


func _build_plants(layout: Dictionary) -> void:
	var library := PLANTS_SCENE.instantiate()
	var meshes := {}
	for mi in library.find_children("*", "MeshInstance3D", true, false):
		meshes[mi.name] = mi.mesh
	library.free()

	var small: Array = layout.get("small", [])
	var cards: Array = layout.get("cards", [])
	var ps1: Array = layout.get("ps1", [])
	var grow: Array = layout.get("grow_with_distance", [])
	# Hand-placed plants plus the generated forest belt and grass.
	var all_plants := {}
	for src in [layout.get("plants", {}), layout.get("extra_plants", {})]:
		for plant_name in src:
			if not all_plants.has(plant_name):
				all_plants[plant_name] = []
			all_plants[plant_name].append_array(src[plant_name])

	for plant_name in all_plants:
		var mesh: Mesh = meshes.get(plant_name)
		if mesh == null:
			push_warning("Barangay: no mesh for plant %s" % plant_name)
			continue
		if plant_name in ps1:
			mesh = _ps1_mesh(mesh)
		var entries: Array = all_plants[plant_name]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = entries.size()
		var grows: bool = plant_name in grow
		for i in entries.size():
			var e: Dictionary = entries[i]
			var p: Array = e.p
			var s := float(e.s)
			if grows:
				var d := Vector2(p[0], p[2]).distance_to(COURT_CENTRE)
				s *= clampf(1.0 + (d - tree_growth_start) * tree_growth_per_metre, 1.0, tree_growth_max)
			var b := Basis(Vector3.UP, float(e.ry)).scaled(Vector3.ONE * s)
			mm.set_instance_transform(i, Transform3D(b, Vector3(p[0], p[1], p[2])))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = plant_name
		mmi.multimesh = mm
		if plant_name in small:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_begin = 0.0
			mmi.visibility_range_end = small_plant_fade_end
			mmi.visibility_range_end_margin = small_plant_fade_end - small_plant_fade_start
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		if plant_name in cards:
			mmi.material_override = _card_material(mesh)
		if plant_name in small or plant_name in cards:
			mmi.add_to_group("detail_heavy") # hidden in low detail mode (Settings)
		add_child(mmi)


## PS1 look for the trees and spiky grass: blocky (nearest) texture filtering,
## cut-out leaves seen from both sides.
func _ps1_mesh(src: Mesh) -> Mesh:
	var mesh := src.duplicate() as Mesh
	for i in mesh.get_surface_count():
		var m0 := mesh.surface_get_material(i) as StandardMaterial3D
		if m0 == null:
			continue
		var m := m0.duplicate() as StandardMaterial3D
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		m.roughness = 1.0
		m.metallic_specular = 0.1
		var n := m.resource_name.to_lower()
		if "leaf" in n or "frond" in n:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			m.alpha_scissor_threshold = 0.5
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		elif "grass" in n:
			m.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh.surface_set_material(i, m)
	return mesh


## Grass/fern cards: cut-out alpha (cheap, no sorting), visible from both sides.
func _card_material(mesh: Mesh) -> Material:
	var src := mesh.surface_get_material(0) as StandardMaterial3D
	var m: StandardMaterial3D = src.duplicate() if src else StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = card_alpha_cutoff
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return m


## The houses you can walk up to (their collision boxes): each entry is
## {name, centre (ground level), half (half size x/z), basis (house turn)}.
func house_boxes() -> Array:
	var out := []
	var body := get_node_or_null("Colliders")
	if body == null:
		return out
	for cs in body.get_children():
		if not (cs is CollisionShape3D and String(cs.name).begins_with("House_")):
			continue
		var size: Vector3 = (cs.shape as BoxShape3D).size
		var c: Vector3 = cs.global_position
		out.append({"name": String(cs.name), "centre": Vector3(c.x, 0.0, c.z),
			"half": Vector2(size.x, size.z) * 0.5, "basis": cs.global_basis})
	return out


## Where a lamp would hang on each electric post (just under the top).
func lamp_spots() -> Array:
	var out := []
	var body := get_node_or_null("Colliders")
	if body == null:
		return out
	for cs in body.get_children():
		if cs is CollisionShape3D and String(cs.name).begins_with("Post"):
			var h: float = (cs.shape as BoxShape3D).size.y
			out.append(cs.global_position + Vector3(0.0, h * 0.5 - 0.6, 0.0))
	return out


## Mama's round: the invisible court walls come down so you can run between
## the houses, and the ground collider grows to cover the whole barangay.
func set_open_world(on: bool) -> void:
	var body := get_node_or_null("Colliders")
	if body == null:
		return
	for n in ["BoundL", "BoundR", "BoundFront", "BoundBack"]:
		var cs := body.get_node_or_null(n) as CollisionShape3D
		if cs:
			cs.set_deferred("disabled", on)
	var ground := body.get_node_or_null("Ground") as CollisionShape3D
	if ground:
		(ground.shape as BoxShape3D).size = Vector3(220.0, 1.0, 220.0) if on else Vector3(70.0, 1.0, 90.0)


## Houses, posts and the invisible play-area boundaries, plus the ground.
func _build_colliders(boxes: Array) -> void:
	var body := StaticBody3D.new()
	body.name = "Colliders"
	add_child(body)
	var all := boxes.duplicate()
	all.append({"name": "Ground", "center": [0.0, -0.5, -13.5], "size": [70.0, 1.0, 90.0]})
	for b in all:
		var shape := BoxShape3D.new()
		shape.size = Vector3(b.size[0], b.size[1], b.size[2])
		var cs := CollisionShape3D.new()
		cs.name = b.name
		cs.shape = shape
		cs.position = Vector3(b.center[0], b.center[1], b.center[2])
		if b.has("ry"):  # houses are turned at all sorts of angles
			cs.rotation.y = float(b.ry)
		body.add_child(cs)
