extends Node3D
## The barangay around the SK Court: land, houses and props (one model), plus
## plants and collisions laid out from barangay_layout.json (exported from
## art/source/barangay_land.blend).
##
## Plants are drawn as one MultiMesh per plant type, so 66 grass clumps cost
## about the same as one. Small plants fade out with distance and cast no
## shadows (cheap on phones, invisible at sunset anyway).

const ENV_SCENE := preload("res://art/environment/barangay_env.glb")
const PLANTS_SCENE := preload("res://art/environment/barangay_plants.glb")
const LAYOUT_PATH := "res://art/environment/barangay_layout.json"

@export var small_plant_fade_start := 26.0 ## metres from the camera
@export var small_plant_fade_end := 34.0
@export var card_alpha_cutoff := 0.4


func _ready() -> void:
	add_child(ENV_SCENE.instantiate())
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	if layout == null:
		push_error("Barangay: can't read %s" % LAYOUT_PATH)
		return
	_build_plants(layout)
	_build_colliders(layout.boxes)


func _build_plants(layout: Dictionary) -> void:
	var library := PLANTS_SCENE.instantiate()
	var meshes := {}
	for mi in library.find_children("*", "MeshInstance3D", true, false):
		meshes[mi.name] = mi.mesh
	library.free()

	var small: Array = layout.get("small", [])
	var cards: Array = layout.get("cards", [])
	for plant_name in layout.plants:
		var mesh: Mesh = meshes.get(plant_name)
		if mesh == null:
			push_warning("Barangay: no mesh for plant %s" % plant_name)
			continue
		var entries: Array = layout.plants[plant_name]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = entries.size()
		for i in entries.size():
			var e: Dictionary = entries[i]
			var p: Array = e.p
			var b := Basis(Vector3.UP, float(e.ry)).scaled(Vector3.ONE * float(e.s))
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
		add_child(mmi)


## Grass/fern cards: cut-out alpha (cheap, no sorting), visible from both sides.
func _card_material(mesh: Mesh) -> Material:
	var src := mesh.surface_get_material(0) as StandardMaterial3D
	var m: StandardMaterial3D = src.duplicate() if src else StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = card_alpha_cutoff
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return m


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
		body.add_child(cs)
