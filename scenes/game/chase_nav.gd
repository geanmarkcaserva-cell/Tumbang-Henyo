class_name ChaseNav
extends Node3D
## Paths around houses for everyone who chases you (tayas, Mama, tanods).
##
## At the start of a game it bakes a navigation mesh from the barangay's
## solid things (houses with their real shapes, props, posts, the ground) on
## a background thread. Until it's ready, chasers simply run straight at you
## like before.
##
## Chasers call route(): if they can see a clear way to where they want to
## go they run straight there; if a house is in the way they follow the
## path around it instead of pressing into the wall. A player up on a roof
## can't be reached on foot: the path ends at the closest spot below.

const CELL := 0.25
const CELL_HEIGHT := 0.2
const AGENT_RADIUS := 0.5
const AREA := AABB(Vector3(-120.0, -2.0, -120.0), Vector3(240.0, 16.0, 240.0))
const REPATH_TIME := 0.35 ## seconds between path updates per chaser
const REPATH_MOVE := 1.2 ## ...or sooner if the goal moved this far
const WAYPOINT_REACHED := 0.7

static var current: ChaseNav ## the one in the running game (null in menus)

var is_ready := false
var bake_ms := 0

var _region: NavigationRegion3D
var _started := 0


func _enter_tree() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null


## Bake from every solid thing under `root` (the arena). Skips the invisible
## court walls, so paths work in the open barangay too.
func build(root: Node) -> void:
	var map := get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map, CELL)
	NavigationServer3D.map_set_cell_height(map, CELL_HEIGHT)
	var src := NavigationMeshSourceGeometryData3D.new()
	# The ground, as one big flat quad (its collider changes size with the mode).
	var g := AREA.size.x * 0.5
	src.add_faces(PackedVector3Array([
		Vector3(-g, 0, -g), Vector3(g, 0, -g), Vector3(g, 0, g),
		Vector3(-g, 0, -g), Vector3(g, 0, g), Vector3(-g, 0, g)]), Transform3D.IDENTITY)
	var box := BoxMesh.new()
	var add_box := func(size: Vector3, xf: Transform3D) -> void:
		box.size = size
		src.add_mesh_array(box.get_mesh_arrays(), xf)
	for body in root.find_children("*", "StaticBody3D", true, false):
		for cs in body.get_children():
			if not (cs is CollisionShape3D) or cs.disabled or cs.shape == null:
				continue
			var n := String(cs.name)
			if n.begins_with("Bound") or n == "Ground":
				continue
			var xf: Transform3D = cs.global_transform
			var shape: Shape3D = cs.shape
			if shape is ConcavePolygonShape3D:
				src.add_faces((shape as ConcavePolygonShape3D).get_faces(), xf)
			elif shape is BoxShape3D:
				add_box.call((shape as BoxShape3D).size, xf)
			elif shape is ConvexPolygonShape3D or shape is CylinderShape3D or shape is CapsuleShape3D or shape is SphereShape3D:
				var aabb := shape.get_debug_mesh().get_aabb()
				add_box.call(aabb.size, xf * Transform3D(Basis(), aabb.get_center()))
	var nm := NavigationMesh.new()
	nm.cell_size = CELL
	nm.cell_height = CELL_HEIGHT
	nm.agent_radius = AGENT_RADIUS
	nm.agent_height = 1.6
	nm.agent_max_climb = 0.4
	nm.agent_max_slope = 40.0
	nm.region_min_size = 4.0
	nm.filter_baking_aabb = AREA
	_region = NavigationRegion3D.new()
	_region.name = "NavRegion"
	add_child(_region)
	_started = Time.get_ticks_msec()
	NavigationServer3D.bake_from_source_geometry_data_async(nm, src, func():
		_finish.call_deferred(nm))


func _finish(nm: NavigationMesh) -> void:
	if not is_inside_tree():
		return
	_region.navigation_mesh = nm
	bake_ms = Time.get_ticks_msec() - _started
	# The map picks the region up on its next sync.
	var map := get_world_3d().navigation_map
	var before := NavigationServer3D.map_get_iteration_id(map)
	for i in 30:
		await get_tree().physics_frame
		if NavigationServer3D.map_get_iteration_id(map) != before:
			break
	is_ready = true
	print("ChaseNav: baked in %d ms, %d polygons" % [bake_ms, nm.get_polygon_count()])


## Where `who` should run next to get to `goal`. `memo` is a Dictionary the
## caller keeps (its own path cache). Returns the goal itself when the way is
## clear or no path is known.
func route(who: CollisionObject3D, goal: Vector3, memo: Dictionary, delta: float) -> Vector3:
	var from := who.global_position
	if not is_ready:
		return goal
	# Looking is cheap but not free: re-check the straight line ~8 times a second.
	memo.look = float(memo.get("look", 0.0)) - delta
	if memo.look <= 0.0:
		memo.look = 0.12
		memo.clear_way = _clear_way(who, from, goal)
		memo.cut = true
	if memo.clear_way:
		memo.erase("path")
		return goal
	memo.t = float(memo.get("t", 0.0)) - delta
	var path: PackedVector3Array = memo.get("path", PackedVector3Array())
	var last_goal: Vector3 = memo.get("goal", Vector3.INF)
	if memo.t <= 0.0 or path.is_empty() or last_goal.distance_to(goal) > REPATH_MOVE:
		var map := get_world_3d().navigation_map
		path = NavigationServer3D.map_get_path(map, from, goal, true)
		memo.path = path
		memo.goal = goal
		memo.i = 1
		memo.t = REPATH_TIME * randf_range(0.8, 1.2)
	var i: int = memo.get("i", 1)
	while i < path.size() and _flat(path[i] - from).length() < WAYPOINT_REACHED:
		i += 1
	# Cut corners: skip ahead to the furthest waypoint in plain view
	# (checked at the same pace as the straight line).
	if memo.get("cut", false):
		memo.cut = false
		var j := mini(i + 3, path.size() - 1)
		while j > i:
			if _clear_way(who, from, path[j]):
				i = j
				break
			j -= 1
	memo.i = i
	if i >= path.size():
		return goal
	return path[i]


## Closest point on foot to `p` (e.g. below a roof the player stands on).
func ground_point(p: Vector3) -> Vector3:
	if not is_ready:
		return p
	return NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, p)


## A straight run is possible: nothing solid between from and to at knee and
## chest height, on both sides of a body about as wide as a person.
func _clear_way(who: CollisionObject3D, from: Vector3, to: Vector3) -> bool:
	var flat := _flat(to - from)
	if flat.length() < 0.3:
		return true
	if to.y - from.y > 1.2:
		return false # up on something: needs the path (which ends below it)
	var side := flat.normalized().cross(Vector3.UP) * (AGENT_RADIUS * 0.8)
	var space := get_world_3d().direct_space_state
	for h: float in [0.5, 1.3]:
		for s: Vector3 in [side, -side]:
			var a := from + Vector3.UP * h + s
			var b := Vector3(to.x, from.y, to.z) + Vector3.UP * h + s
			var q := PhysicsRayQueryParameters3D.create(a, b, 1, [who.get_rid()])
			var hit := space.intersect_ray(q)
			if not hit.is_empty() and not (hit.collider is CharacterBody3D) and not (hit.collider is RigidBody3D):
				return false
	return true


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
