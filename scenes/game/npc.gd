class_name Npc
extends CharacterBody3D
## Barangay folk: kids, lolos and lolas, vendors... one for every sheet in the
## art/characters/Npc* folders (drop a new sheet in one of those folders and
## they're in the next game). Each shows up once per game - a few on the
## court, the rest out in the streets - then strolls around the barangay on the
## navigation mesh, and now and then walks to a house, goes in, and comes back
## out a little later.
##
## They're scenery: nothing collides with them and they don't care about the
## game. Their sheets face front only, so the same sheet is used whichever way
## they walk.

enum Do { PAUSE, WALK, INSIDE }

const SHEET_ROOT := "res://art/characters"
const COURT := Rect2(-8.0, -44.0, 16.0, 46.0) ## where they start (x, z)
const MAP := Rect2(-62.0, -82.0, 124.0, 134.0) ## where they may go (inside the fence)
const ROAM := 32.0 ## how far one walk takes them at most
const HOUSE_CHANCE := 0.5 ## of each new walk being to a house
const COURT_CHANCE := 0.12 ## of a plain walk going to the court
const COURT_START := 4 ## how many start out on the court (the rest are around the barangay)
## Path points sit a little above the ground; anything higher than this is a roof.
const NAV_GROUND := 1.0

var sheet := "" ## res:// path of the sheet
var speed := 1.3

var _doll: PaperDoll
var _do := Do.PAUSE
var _wait := 0.0
var _path := PackedVector3Array()
var _i := 0
var _door := {} ## the house being walked to: {centre, out}
var _barangay: Node
var _ground_t := 0


## Every NPC sheet in the art/characters/Npc* folders, each listed once.
static func sheets() -> PackedStringArray:
	var out := PackedStringArray()
	var root := DirAccess.open(SHEET_ROOT)
	if root == null:
		return out
	for d in root.get_directories():
		if not d.to_lower().begins_with("npc"):
			continue
		var dir := "%s/%s" % [SHEET_ROOT, d]
		for f in DirAccess.get_files_at(dir):
			# Exported games only keep the .import next to each texture.
			var fname := f.trim_suffix(".import")
			if fname.to_lower().ends_with(".png"):
				var path := "%s/%s" % [dir, fname]
				if not out.has(path) and ResourceLoader.exists(path):
					out.append(path)
	out.sort()
	return out


## One of each: a few start on the court, the rest out in the streets all
## over the barangay (never inside a house or on top of something).
static func spawn_all(parent: Node3D, barangay: Node, keep_clear: Array = []) -> Array:
	var npcs := []
	var taken: Array = keep_clear.duplicate()
	var houses: Array = barangay.house_boxes() if barangay and barangay.has_method("house_boxes") else []
	var space := parent.get_world_3d().direct_space_state
	var paths := sheets()
	var order := range(paths.size())
	order.shuffle()
	for k in order.size():
		var path: String = paths[order[k]]
		var n := Npc.new()
		n.sheet = path
		n._barangay = barangay
		n.name = "Npc_" + path.get_file().get_basename().validate_node_name()
		var area := COURT if k < COURT_START else MAP
		var spot := Vector3.INF
		for attempt in 60:
			var p := Vector3(randf_range(area.position.x, area.end.x), 0.0, randf_range(area.position.y, area.end.y))
			if area == MAP and COURT.grow(3.0).has_point(Vector2(p.x, p.z)):
				continue # the court has its few already
			if _near_any(p, taken, 2.5) or _in_house(p, houses):
				continue
			var from := p + Vector3.UP * 6.0
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, p + Vector3.DOWN * 1.0))
			if hit.is_empty() or (hit.position as Vector3).y > 0.3:
				continue # something's standing there (a prop, a roof...)
			spot = hit.position
			break
		if spot == Vector3.INF:
			n.free()
			continue
		taken.append(spot)
		parent.add_child(n)
		n.global_position = spot
		n.rotation.y = randf() * TAU
		npcs.append(n)
	return npcs


static func _near_any(p: Vector3, others: Array, d: float) -> bool:
	for t: Vector3 in others:
		if _flat(p - t).length() < d:
			return true
	return false


static func _in_house(p: Vector3, houses: Array) -> bool:
	for h: Dictionary in houses:
		var local: Vector3 = (h.basis as Basis).orthonormalized().inverse() * (p - (h.centre as Vector3))
		var half: Vector2 = h.half
		if absf(local.x) < half.x + 1.0 and absf(local.z) < half.y + 1.0:
			return true
	return false


func _ready() -> void:
	add_to_group("npc")
	collision_layer = 0
	collision_mask = 0
	_doll = PaperDoll.new()
	_doll.shadow_radius = 0.35
	_doll.hop_height = 0.07
	_doll.wobble_deg = 5.0
	add_child(_doll)
	_doll.set_look(PixelArt.single_sheet_look(sheet))
	# Kids hurry, grown-ups stroll (the kid sheets are the short ones).
	var kid := "bata" in sheet.to_lower()
	speed = randf_range(1.9, 2.4) if kid else randf_range(1.05, 1.5)
	_wait = randf_range(0.5, 5.0)


func _physics_process(delta: float) -> void:
	match _do:
		Do.PAUSE:
			velocity = Vector3.ZERO
			_wait -= delta
			if _wait <= 0.0:
				_next_walk()
		Do.WALK:
			_walk(delta)
		Do.INSIDE:
			velocity = Vector3.ZERO
			_wait -= delta
			if _wait <= 0.0:
				_come_out()


func _walk(delta: float) -> void:
	while _i < _path.size() and _flat(_path[_i] - global_position).length() < 0.3:
		_i += 1
	if _i >= _path.size():
		velocity = Vector3.ZERO
		_arrive()
		return
	var to := _flat(_path[_i] - global_position)
	var dir := to.normalized()
	velocity = dir * speed
	global_position += velocity * delta
	global_basis = Basis.looking_at(dir, Vector3.UP)
	_stick_to_ground()


## Feet on whatever is underfoot (the path network floats a little above it).
func _stick_to_ground() -> void:
	_ground_t -= 1
	if _ground_t > 0:
		return
	_ground_t = 3
	var from := global_position + Vector3.UP * 1.2
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 3.0))
	if not hit.is_empty():
		global_position.y = (hit.position as Vector3).y


func _pause(t: float) -> void:
	_do = Do.PAUSE
	_wait = t
	_path = PackedVector3Array()
	_door = {}


## Where next: often a house (to go in), otherwise somewhere on the court or
## a stroll down the street.
func _next_walk() -> void:
	var nav := ChaseNav.current
	if nav == null or not nav.is_ready:
		_wait = 1.0
		return
	var map := get_world_3d().navigation_map
	var goal := Vector3.INF
	_door = {}
	if randf() < HOUSE_CHANCE:
		_door = _pick_door(map)
		if not _door.is_empty():
			goal = _door.out
	if goal == Vector3.INF:
		for attempt in 12:
			var p: Vector3
			if randf() < COURT_CHANCE:
				p = Vector3(randf_range(COURT.position.x, COURT.end.x), 0.0, randf_range(COURT.position.y, COURT.end.y))
			else:
				var a := randf() * TAU
				p = global_position + Vector3(cos(a), 0.0, sin(a)) * randf_range(8.0, ROAM)
			if not MAP.has_point(Vector2(p.x, p.z)):
				continue
			var q := NavigationServer3D.map_get_closest_point(map, p)
			if q.y < NAV_GROUND and _flat(q - p).length() < 1.5: # on the ground, not a roof
				goal = q
				break
	if goal == Vector3.INF:
		_wait = randf_range(1.0, 2.0)
		return
	_path = NavigationServer3D.map_get_path(map, global_position, goal, true)
	if _path.size() < 2:
		_pause(randf_range(1.0, 3.0))
		return
	_i = 1
	_do = Do.WALK


## A house nearby and the spot just outside one of its walls that's on the
## path network (its "door").
func _pick_door(map: RID) -> Dictionary:
	if _barangay == null or not _barangay.has_method("house_boxes"):
		return {}
	var near := []
	for h in _barangay.house_boxes():
		var c: Vector3 = h.centre
		if _flat(c - global_position).length() < ROAM + 8.0 and MAP.has_point(Vector2(c.x, c.z)):
			near.append(h)
	if near.is_empty():
		return {}
	var h: Dictionary = near.pick_random()
	var c: Vector3 = h.centre
	var basis: Basis = (h.basis as Basis).orthonormalized()
	var half: Vector2 = h.half
	var best := {}
	var best_d := INF
	for side: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]:
		var reach := (half.x if side.x != 0.0 else half.y) + 0.7
		var want := c + basis * side * reach
		var q := NavigationServer3D.map_get_closest_point(map, want)
		if q.y > NAV_GROUND or _flat(q - want).length() > 0.9:
			continue
		var d := _flat(q - global_position).length()
		if d < best_d:
			best_d = d
			best = {"centre": c, "out": q}
	return best


func _arrive() -> void:
	if _door.is_empty():
		_pause(randf_range(2.0, 7.0))
		return
	# In through the door: face the house, step in and shrink away.
	var into := _flat(_door.centre - global_position).normalized()
	if into != Vector3.ZERO:
		global_basis = Basis.looking_at(into, Vector3.UP)
	_do = Do.INSIDE
	_wait = randf_range(6.0, 20.0)
	var t := create_tween().set_parallel()
	t.tween_property(self, "global_position", global_position + into * 0.6, 0.35)
	t.tween_property(_doll, "scale", Vector3(0.05, 1.3, 0.05), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(func(): _doll.visible = false)


func _come_out() -> void:
	var out: Vector3 = _door.get("out", global_position)
	out.y = global_position.y
	var away := _flat(out - global_position).normalized()
	if away != Vector3.ZERO:
		global_basis = Basis.looking_at(away, Vector3.UP)
	_doll.visible = true
	_do = Do.PAUSE
	_wait = randf_range(1.0, 3.5)
	var t := create_tween().set_parallel()
	t.tween_property(self, "global_position", out, 0.35)
	t.tween_property(_doll, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_door = {}


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
