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
##
## Houses you can reach collide with their real shape (a trimesh of the
## model), so roofs, ledges, awnings and open shop fronts are solid exactly
## where they look solid and players can parkour up onto them. The old
## simple boxes are kept (disabled) only as a quick footprint for scripts
## (house_boxes(): Mama's goal house, tayas running home, the curfew house).

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
## The playable barangay, (min x, min z, width, depth): a chain-link fence
## (cyclone wire) runs all the way round it. Everything inside is open to
## run around in during the chase.
const MAP_RECT := Rect2(-68.0, -88.0, 136.0, 146.0)
const FENCE_HEIGHT := 2.6 ## metres of wire (the collider is taller: no jumping it)
const FENCE_POST_GAP := 3.0
## Street lamps: along both sides of the court, and spread over the barangay.
const COURT_LAMPS_Z := [10.0, -2.0, -14.0, -26.0, -38.0, -48.0]
const COURT_LAMPS_X := 11.2
const MAP_LAMP_GAP := 21.0
const LAMP_HEIGHT := 4.6

signal lampposts_built

## Where each street lamp's bulb is (filled in once they're built).
var lamppost_bulbs: Array = []
## The glowing bulb material (DayNight turns it on at dusk).
var bulb_material: StandardMaterial3D
var _house_rects: Array = [] ## [centre, half, basis] of every walkable house

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
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	if layout == null:
		push_error("Barangay: can't read %s" % LAYOUT_PATH)
		_build_props()
		return
	for b in layout.boxes:
		if String(b.name).begins_with("House_"):
			_house_rects.append([Vector3(b.center[0], 0.0, b.center[2]), Vector2(b.size[0], b.size[2]) * 0.5,
					Basis(Vector3.UP, float(b.get("ry", 0.0)))])
	_build_props()
	_build_fence()
	_build_map_wall()
	if layout.has("houses"):
		for n in env.find_children("House_*", "", true, false):
			n.queue_free()
		_build_houses(layout.houses, _walkable_lots(layout.boxes))
	_build_plants(layout)
	_build_colliders(layout.boxes)
	# Street lamps go where nothing solid is, so they wait for the physics.
	await get_tree().physics_frame
	_build_lampposts()


## The props model, with solid collision on everything tall enough to bump into.
func _build_props() -> void:
	if not ResourceLoader.exists(PROPS_PATH):
		return
	var props: Node3D = (load(PROPS_PATH) as PackedScene).instantiate()
	props.name = "Props"
	add_child(props)
	for mi in props.find_children("*", "MeshInstance3D", true, false):
		_strip_strays(mi as MeshInstance3D)
	for mi in props.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or m.get_aabb().size.y * m.global_basis.get_scale().y < PROP_MIN_COLLIDE_HEIGHT:
			continue
		m.create_trimesh_collision()
		for cs in m.find_children("*", "CollisionShape3D", true, false):
			_two_sided(cs.shape)


## Blocks left in the props file with no material (plain white, modelling
## leftovers) that stand inside a house's footprint are cut out, so they don't
## swallow the house (one hid the hollow-block house west of the court).
func _strip_strays(m: MeshInstance3D) -> void:
	if m.mesh == null or _house_rects.is_empty():
		return
	var mesh := m.mesh as ArrayMesh
	if mesh == null:
		return
	var changed := false
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var mat := mesh.surface_get_material(s)
		var arrays := mesh.surface_get_arrays(s)
		if (mat == null or mat.resource_name == "") and mesh.surface_get_primitive_type(s) == Mesh.PRIMITIVE_TRIANGLES:
			var kept = _drop_pieces_in_houses(arrays, m.global_transform)
			if kept != null:
				changed = true
				if (kept as PackedInt32Array).is_empty():
					continue # the whole surface was strays
				arrays[Mesh.ARRAY_INDEX] = kept
		out.add_surface_from_arrays(mesh.surface_get_primitive_type(s), arrays)
		out.surface_set_material(out.get_surface_count() - 1, mat)
	if changed:
		m.mesh = out


## Splits a surface into connected pieces and drops the pieces whose middle is
## inside a house. Returns the new index list, or null if nothing changed.
func _drop_pieces_in_houses(arrays: Array, xf: Transform3D) -> Variant:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if idx.is_empty():
		for i in verts.size():
			idx.append(i)
	# Pieces: vertices joined by triangles, or sharing a position.
	var parent: Array = [] # an Array (shared by reference with the lambdas below)
	parent.resize(verts.size())
	for i in verts.size():
		parent[i] = i
	var find := func(a: int) -> int:
		while parent[a] != a:
			parent[a] = parent[parent[a]]
			a = parent[a]
		return a
	var join := func(a: int, b: int) -> void:
		var ra: int = find.call(a)
		var rb: int = find.call(b)
		if ra != rb:
			parent[ra] = rb
	var same := {}
	for i in verts.size():
		var key := (verts[i] * 1000.0).round()
		if same.has(key):
			join.call(i, same[key])
		else:
			same[key] = i
	for t in idx.size() / 3:
		join.call(idx[t * 3], idx[t * 3 + 1])
		join.call(idx[t * 3], idx[t * 3 + 2])
	var boxes := {}
	for i in verts.size():
		var r: int = find.call(i)
		var p := xf * verts[i]
		boxes[r] = AABB(p, Vector3.ZERO) if not boxes.has(r) else (boxes[r] as AABB).expand(p)
	var drop := {}
	for r in boxes:
		var c: Vector3 = (boxes[r] as AABB).get_center()
		for h in _house_rects:
			var local: Vector3 = (h[2] as Basis).inverse() * (Vector3(c.x, 0.0, c.z) - h[0])
			if absf(local.x) < h[1].x and absf(local.z) < h[1].y:
				drop[r] = true
				break
	if drop.is_empty():
		return null
	var kept := PackedInt32Array()
	for t in idx.size() / 3:
		if not drop.has(find.call(idx[t * 3])):
			kept.append(idx[t * 3])
			kept.append(idx[t * 3 + 1])
			kept.append(idx[t * 3 + 2])
	return kept


## Trimesh walls and roofs are paper-thin and, by default, only solid from
## their front side: jumping up under an eave, or clipping a corner on a fast
## landing, let the player pass through from behind and end up inside the
## walls. Solid from both sides (backface collision), they stop you either way.
static func _two_sided(shape: Shape3D) -> Shape3D:
	if shape is ConcavePolygonShape3D:
		(shape as ConcavePolygonShape3D).backface_collision = true
	return shape


## Lots that have a collision box in the layout: the houses you can run up to.
func _walkable_lots(boxes: Array) -> Dictionary:
	var out := {}
	for b in boxes:
		var n: String = b.name
		if n.begins_with("House_"):
			out[n.trim_prefix("House_")] = true
	return out


func _build_houses(entries: Array, walkable: Dictionary = {}) -> void:
	var library := HOUSES_SCENE.instantiate()
	var meshes := {}
	for mi in library.find_children("*", "MeshInstance3D", true, false):
		meshes[mi.name] = mi.mesh
	library.free()
	var root := Node3D.new()
	root.name = "Houses"
	add_child(root)
	# One trimesh shape per house model, shared by every copy of it.
	var shapes := {}
	var solid := StaticBody3D.new()
	solid.name = "HouseShapes"
	add_child(solid)
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
		if walkable.has(String(e.lot)):
			if not shapes.has(e.name):
				shapes[e.name] = _two_sided(mesh.create_trimesh_shape())
			var cs := CollisionShape3D.new()
			cs.name = "Shape_%s" % e.lot
			cs.shape = shapes[e.name]
			cs.transform = mi.transform
			solid.add_child(cs)


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


## A safety net for the house walls: even solid from both sides, a paper-thin
## wall or eave can still let a fast landing through now and then, and then
## you'd be stuck inside the house. Each walkable house gets a "core" - the
## room inside its walls, plus the low roof space on top of them - and
## unstick() lifts anyone who ends up in there back onto the roof (when they
## were going for it) or out through the nearest wall.
var _cores: Array = []
var _cores_ready := false


func build_cores() -> void:
	_cores.clear()
	var solid := get_node_or_null("HouseShapes")
	if solid == null:
		return
	var space := get_world_3d().direct_space_state
	for h in house_boxes():
		var half: Vector2 = h.half
		var basis: Basis = (h.basis as Basis).orthonormalized()
		var c: Vector3 = h.centre
		# The eaves: the lowest bit of roof just inside the four corners.
		var top := INF
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var pt: Vector3 = c + basis * Vector3(sx * (half.x - 0.4), 0.0, sz * (half.y - 0.4))
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(pt + Vector3.UP * 20.0, pt + Vector3.UP * 0.3))
				if not hit.is_empty() and hit.collider == solid:
					top = minf(top, (hit.position as Vector3).y)
		if top == INF or top < 1.4:
			continue
		_cores.append({"centre": c, "half": half, "basis": basis, "inv": basis.transposed(), "top": top,
			"reach": half.length() + 1.0})
	_cores_ready = true


## The house [param feet] (a body's feet) is shut inside, or {} when none.
## Shut in means roof overhead and wall or roof every way you look - so the
## open front of a tindahan, the space under a raised kubo or a porch roof
## under an upper storey don't count; only somewhere you can't get out of.
func house_core_at(feet: Vector3) -> Dictionary:
	var probe := feet + Vector3.UP * 0.35
	var solid := get_node_or_null("HouseShapes")
	for k: Dictionary in _cores:
		var c: Vector3 = k.centre
		if absf(probe.x - c.x) > k.reach or absf(probe.z - c.z) > k.reach:
			continue
		var local: Vector3 = (k.inv as Basis) * (probe - c)
		var half: Vector2 = k.half
		if absf(local.x) > half.x - 0.3 or absf(local.z) > half.y - 0.3:
			continue
		var space := get_world_3d().direct_space_state
		var up := space.intersect_ray(PhysicsRayQueryParameters3D.create(probe, probe + Vector3.UP * 12.0))
		if up.is_empty() or up.collider != solid:
			return {} # open sky above: on top of the roof, fine
		var basis: Basis = k.basis
		var hit: Array[bool] = []
		for dir: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]:
			var reach := (half.x if dir.x != 0.0 else half.y) * 2.0 + 0.6
			hit.append(_hits(space, probe, probe + basis * dir * reach, solid))
		if not hit.has(false):
			return k
		# Under the roof but on top of the walls: the low roof space, open at
		# the gable ends on some houses, with the roof sloping down either side
		# and no room to stand up. That's a botched roof landing too (the roof
		# decks of the brick houses have more headroom than this: those are fine).
		var headroom := (up.position as Vector3).y - feet.y
		if feet.y > float(k.top) - 0.4 and headroom < 2.0 and ((hit[0] and hit[1]) or (hit[2] and hit[3])):
			return k
		return {}
	return {}


static func _hits(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, solid: Node) -> bool:
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
	return not hit.is_empty() and hit.collider == solid


## Pulls [param body] out of a house it has clipped into. Returns true when it did.
func unstick(body: CharacterBody3D) -> bool:
	if not _cores_ready:
		return false
	var feet := body.global_position
	var k := house_core_at(feet)
	if k.is_empty():
		return false
	var c: Vector3 = k.centre
	var basis: Basis = k.basis
	var local: Vector3 = (k.inv as Basis) * (feet - c)
	var half: Vector2 = k.half
	var space := get_world_3d().direct_space_state
	var roof := space.intersect_ray(PhysicsRayQueryParameters3D.create(
		Vector3(feet.x, float(k.top) + 15.0, feet.z), Vector3(feet.x, float(k.top) - 0.5, feet.z), 1, [body.get_rid()]))
	if feet.y > float(k.top) * 0.45 and not roof.is_empty():
		# Going for the roof: put them on it.
		body.global_position = (roof.position as Vector3) + Vector3.UP * 0.06
	else:
		var out := _nearest_side(local, half)
		var spot: Vector3 = local * Vector3(absf(out.z), 0.0, absf(out.x)) + out * (absf(out.dot(Vector3(half.x, 0.0, half.y))) + 0.55)
		var p: Vector3 = c + basis * spot
		body.global_position = Vector3(p.x, maxf(feet.y, 0.05), p.z)
	body.velocity = Vector3(0.0, minf(body.velocity.y, 0.0), 0.0)
	return true


static func _nearest_side(local: Vector3, half: Vector2) -> Vector3:
	var dx := half.x - absf(local.x)
	var dz := half.y - absf(local.z)
	if dx < dz:
		return Vector3(signf(local.x) if local.x != 0.0 else 1.0, 0.0, 0.0)
	return Vector3(0.0, 0.0, signf(local.z) if local.z != 0.0 else 1.0)


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


## The invisible court walls come down so you can run between the houses
## (the game keeps it open; the fence round the barangay is the limit), and
## the ground collider grows to cover the whole barangay.
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


# --- Fence round the barangay -----------------------------------------------------

## An invisible wall just outside the fence, thick and sky-high, so nobody gets
## out by jumping off a roof over the fence, and a slipper thrown over it
## bounces back in (a taya has to be able to go and pick it up again).
const MAP_WALL_HEIGHT := 120.0
const MAP_WALL_THICK := 6.0
const MAP_WALL_BOUNCE := 0.55 ## slippers spring back off it

func _build_map_wall() -> void:
	var wall := StaticBody3D.new()
	wall.name = "MapWall"
	var pm := PhysicsMaterial.new()
	pm.bounce = MAP_WALL_BOUNCE
	pm.friction = 0.2
	wall.physics_material_override = pm
	add_child(wall)
	var r := MAP_RECT
	var t := MAP_WALL_THICK
	var y := MAP_WALL_HEIGHT * 0.5 - 2.0
	# (centre, size): inner faces sit on the fence line (+0.15, its half-thickness).
	var sides := [
		[Vector3(r.position.x - 0.15 - t * 0.5, y, r.get_center().y), Vector3(t, MAP_WALL_HEIGHT, r.size.y + t * 2.0)],
		[Vector3(r.end.x + 0.15 + t * 0.5, y, r.get_center().y), Vector3(t, MAP_WALL_HEIGHT, r.size.y + t * 2.0)],
		[Vector3(r.get_center().x, y, r.position.y - 0.15 - t * 0.5), Vector3(r.size.x + t * 2.0, MAP_WALL_HEIGHT, t)],
		[Vector3(r.get_center().x, y, r.end.y + 0.15 + t * 0.5), Vector3(r.size.x + t * 2.0, MAP_WALL_HEIGHT, t)],
	]
	for side in sides:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = side[1]
		cs.shape = box
		cs.position = side[0]
		wall.add_child(cs)
	# Slippers check this too, in case one ever slips through.
	get_tree().root.set_meta("play_area", r)

## Chain-link (cyclone wire) on steel posts all the way round MAP_RECT, with a
## top rail. Solid and tall enough that you can't jump it.
func _build_fence() -> void:
	var root := StaticBody3D.new()
	root.name = "Fence"
	add_child(root)
	var r := MAP_RECT
	var corners := [Vector3(r.position.x, 0, r.position.y), Vector3(r.end.x, 0, r.position.y),
			Vector3(r.end.x, 0, r.end.y), Vector3(r.position.x, 0, r.end.y)]
	var wire := StandardMaterial3D.new()
	wire.albedo_texture = _chain_link_texture()
	wire.albedo_color = Color(0.72, 0.74, 0.76)
	wire.metallic = 0.6
	wire.roughness = 0.5
	wire.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	wire.alpha_scissor_threshold = 0.5
	wire.cull_mode = BaseMaterial3D.CULL_DISABLED
	wire.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.5, 0.52, 0.55)
	steel.metallic = 0.7
	steel.roughness = 0.45
	steel.cull_mode = BaseMaterial3D.CULL_DISABLED
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rails := SurfaceTool.new()
	rails.begin(Mesh.PRIMITIVE_TRIANGLES)
	var posts: Array[Vector3] = []
	for i in 4:
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % 4]
		var length := a.distance_to(b)
		# Wire panel: one long quad, the pattern repeats every half metre.
		var up := Vector3.UP * FENCE_HEIGHT
		var u := length * 2.0
		var v := FENCE_HEIGHT * 2.0
		st.set_normal((b - a).cross(Vector3.UP).normalized())
		for q in [[a, Vector2(0, v)], [b, Vector2(u, v)], [b + up, Vector2(u, 0)], [a, Vector2(0, v)], [b + up, Vector2(u, 0)], [a + up, Vector2(0, 0)]]:
			st.set_uv(q[1])
			st.add_vertex(q[0])
		# Top rail and bottom rail.
		for h in [FENCE_HEIGHT, 0.12]:
			_add_box(rails, (a + b) * 0.5 + Vector3.UP * h, Vector3(0.06, 0.06, length), Basis.looking_at((b - a).normalized(), Vector3.UP))
		var n := int(ceil(length / FENCE_POST_GAP))
		for k in n:
			posts.append(a.lerp(b, float(k) / n))
		# Solid wall for collisions (tall: no jumping over from a roof).
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.3, 7.0, length + 0.3)
		cs.shape = box
		cs.transform = Transform3D(Basis.looking_at((b - a).normalized(), Vector3.UP), (a + b) * 0.5 + Vector3.UP * 3.5)
		root.add_child(cs)
	var panel := MeshInstance3D.new()
	panel.name = "Wire"
	panel.mesh = st.commit()
	panel.material_override = wire
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(panel)
	for p in posts:
		_add_box(rails, p + Vector3.UP * (FENCE_HEIGHT + 0.15) * 0.5, Vector3(0.09, FENCE_HEIGHT + 0.15, 0.09), Basis())
	var steel_mi := MeshInstance3D.new()
	steel_mi.name = "Posts"
	steel_mi.mesh = rails.commit()
	steel_mi.material_override = steel
	root.add_child(steel_mi)


## Diamond wire pattern on a transparent background (32 x 32, tiles).
static func _chain_link_texture() -> Texture2D:
	var img := Image.create(32, 32, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 32:
		for x in 32:
			var a := posmod(x + y, 32)
			var b := posmod(x - y, 32)
			if a <= 1 or b <= 1:
				img.set_pixel(x, y, Color(1, 1, 1, 1))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Adds a box (centre, size, turn) to a SurfaceTool mesh.
static func _add_box(st: SurfaceTool, centre: Vector3, size: Vector3, basis: Basis) -> void:
	var h := size * 0.5
	var faces := [
		[Vector3.RIGHT, Vector3.UP, Vector3.BACK], [Vector3.LEFT, Vector3.UP, Vector3.FORWARD],
		[Vector3.UP, Vector3.BACK, Vector3.RIGHT], [Vector3.DOWN, Vector3.FORWARD, Vector3.RIGHT],
		[Vector3.BACK, Vector3.UP, Vector3.LEFT], [Vector3.FORWARD, Vector3.UP, Vector3.RIGHT],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var t1: Vector3 = f[1]
		var t2: Vector3 = f[2]
		var c := n * h
		var e1 := t1 * h
		var e2 := t2 * h
		var quad := [c - e1 - e2, c - e1 + e2, c + e1 + e2, c - e1 - e2, c + e1 + e2, c + e1 - e2]
		st.set_normal(basis * n)
		for q in quad:
			st.add_vertex(centre + basis * q)


# --- Street lamps --------------------------------------------------------------------

## Low-poly street lamps: a steel pole, an arm and a lamp head with a bulb
## that DayNight lights at dusk (5:40 PM). Along both sides of the court, and
## spread over the barangay wherever there's room (not in houses or props).
func _build_lampposts() -> void:
	var spots: Array = [] ## [base position, facing yaw]
	for z in COURT_LAMPS_Z:
		spots.append([Vector3(-COURT_LAMPS_X, 0, z), -PI * 0.5]) # arm reaches over the court
		spots.append([Vector3(COURT_LAMPS_X, 0, z), PI * 0.5])
	var r := MAP_RECT.grow(-6.0)
	var row := 0
	var z0 := r.position.y
	while z0 <= r.end.y:
		var x0 := r.position.x + (MAP_LAMP_GAP * 0.5 if row % 2 else 0.0) # staggered rows
		while x0 <= r.end.x:
			var p := Vector3(x0, 0, z0)
			if absf(p.x) > 15.0 or p.z > 16.0 or p.z < -52.0: # the court has its own
				var free := _free_spot(p)
				if free != Vector3.INF:
					spots.append([free, fmod(x0 * 0.37 + z0 * 0.21, TAU)])
			x0 += MAP_LAMP_GAP
		z0 += MAP_LAMP_GAP * 0.87
		row += 1
	var poles := SurfaceTool.new()
	poles.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bulbs := SurfaceTool.new()
	bulbs.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := StaticBody3D.new()
	body.name = "Lampposts"
	add_child(body)
	for s in spots:
		var base: Vector3 = s[0]
		var turn := Basis(Vector3.UP, float(s[1]))
		var arm_dir := turn * Vector3.FORWARD
		_add_box(poles, base + Vector3.UP * 0.2, Vector3(0.3, 0.4, 0.3), turn) # foot
		_add_box(poles, base + Vector3.UP * LAMP_HEIGHT * 0.5, Vector3(0.12, LAMP_HEIGHT, 0.12), turn)
		_add_box(poles, base + Vector3.UP * (LAMP_HEIGHT - 0.1) + arm_dir * 0.55, Vector3(0.08, 0.08, 1.1), turn)
		var head := base + Vector3.UP * (LAMP_HEIGHT - 0.2) + arm_dir * 1.1
		_add_box(poles, head, Vector3(0.36, 0.14, 0.5), turn)
		_add_box(bulbs, head + Vector3.DOWN * 0.08, Vector3(0.26, 0.04, 0.38), turn)
		lamppost_bulbs.append(head + Vector3.DOWN * 0.35)
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.3, LAMP_HEIGHT, 0.3)
		cs.shape = box
		cs.position = base + Vector3.UP * LAMP_HEIGHT * 0.5
		body.add_child(cs)
	var pole_mat := StandardMaterial3D.new()
	pole_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	pole_mat.albedo_color = Color(0.26, 0.28, 0.3)
	pole_mat.metallic = 0.5
	pole_mat.roughness = 0.55
	var pmi := MeshInstance3D.new()
	pmi.name = "Poles"
	pmi.mesh = poles.commit()
	pmi.material_override = pole_mat
	body.add_child(pmi)
	bulb_material = StandardMaterial3D.new()
	bulb_material.albedo_color = Color(0.85, 0.82, 0.7)
	bulb_material.emission_enabled = true
	bulb_material.emission = Color(1.0, 0.78, 0.45)
	bulb_material.emission_energy_multiplier = 0.0
	bulb_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var bmi := MeshInstance3D.new()
	bmi.name = "Bulbs"
	bmi.mesh = bulbs.commit()
	bmi.material_override = bulb_material
	bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(bmi)
	lampposts_built.emit()


## `p` if a lamp fits there (nothing solid within about a metre and a half,
## not in a house), else a nearby free spot, else Vector3.INF.
func _free_spot(p: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.0, 4.0, 3.0)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 1
	for off in [Vector3.ZERO, Vector3(3, 0, 0), Vector3(-3, 0, 0), Vector3(0, 0, 3), Vector3(0, 0, -3)]:
		var c: Vector3 = p + off
		var inside := false
		for h in _house_rects:
			var local: Vector3 = (h[2] as Basis).inverse() * (c - h[0])
			if absf(local.x) < h[1].x + 2.0 and absf(local.z) < h[1].y + 2.0:
				inside = true
				break
		if inside:
			continue
		q.transform = Transform3D(Basis(), c + Vector3.UP * 2.3)
		if space.intersect_shape(q, 1).is_empty():
			return c
	return Vector3.INF


## Where a house is: its lot name (e.g. "HP_17_V6_CHB") -> the house model's
## transform, or an empty Transform3D() if there's no such lot.
func house_transform(lot: String) -> Transform3D:
	var cs := get_node_or_null("HouseShapes/Shape_" + lot) as Node3D
	return cs.global_transform if cs else Transform3D()


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
		if String(b.name).begins_with("House_") and get_node_or_null("HouseShapes"):
			cs.disabled = true # the real shape (HouseShapes) does the colliding
		body.add_child(cs)
