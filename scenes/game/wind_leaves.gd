extends Node3D
## Leaves blowing across the court in windy rounds, so players can read the
## wind at a glance: they drift the way it blows, faster and in bigger numbers
## the stronger it is, tumbling and fluttering as they go.
##
## Drawn with one MultiMesh (cheap on phones); the leaf is a small built-in
## mesh, no texture. They live in a box in front of the player (between them
## and the lata), and a leaf that drifts out is re-blown in from the upwind side.

const MAX_LEAVES := 64
const MAX_WIND := 6.0 ## m/s, the strongest wind the rounds roll
const COLOURS := [Color(0.48, 0.74, 0.25), Color(0.73, 0.76, 0.26), Color(0.8, 0.52, 0.22), Color(0.6, 0.66, 0.2), Color(0.86, 0.66, 0.3)]
const HALF := Vector3(9.0, 0.0, 10.0) ## half extents of the box (side, -, depth)
const LOW := 0.4 ## leaves fly between these heights (the band you look through when aiming)
const HIGH := 3.6

var wind := Vector3.ZERO
var follow: Node3D ## the player: the box sits in front of them

const BASE_TINT := Color(0.92, 0.92, 0.92)

var _mat: StandardMaterial3D
var _leaves: Array = []
var _mm := MultiMesh.new()
var _fade := 0.0 ## 0..1, all leaves together (fade in/out with the wind)
var _target_fade := 0.0
var _time := 0.0


func _ready() -> void:
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = _leaf_mesh()
	_mm.instance_count = MAX_LEAVES
	_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 60.0
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Unlit: a leaf seen from behind against the sun would otherwise turn into a
	# dark blob. The two-tone halves and the tumbling still give it shape.
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = BASE_TINT
	mmi.material_override = mat
	_mat = mat
	add_child(mmi)
	top_level = true


## The leaves are unlit, so the day/night cycle darkens them by hand.
func set_tint(c: Color) -> void:
	if _mat:
		_mat.albedo_color = Color(BASE_TINT.r * c.r, BASE_TINT.g * c.g, BASE_TINT.b * c.b)


## New wind for this throw. Zero wind: the leaves settle away.
func set_wind(w: Vector3) -> void:
	wind = Vector3(w.x, 0.0, w.z)
	_target_fade = 1.0 if wind.length() > 0.05 else 0.0
	if _target_fade > 0.0 and _leaves.is_empty():
		_spawn_all()


## Hide (quiz, run) or show (throw) the leaves.
func set_active(on: bool) -> void:
	_target_fade = 1.0 if on and wind.length() > 0.05 else 0.0
	if _target_fade > 0.0 and _leaves.is_empty():
		_spawn_all()


func _count() -> int:
	var k := clampf(wind.length() / MAX_WIND, 0.0, 1.0)
	var n := int(lerpf(22.0, MAX_LEAVES, k))
	if Settings.low_detail:
		n = int(n * 0.5)
	return n


func _centre() -> Vector3:
	if follow == null:
		return Vector3.ZERO
	var fwd := -follow.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	return follow.global_position + fwd * 7.0


func _spawn_all() -> void:
	_leaves.clear()
	var c := _centre()
	for i in _count():
		var leaf := _new_leaf()
		leaf.pos = c + Vector3(randf_range(-HALF.x, HALF.x), 0.0, randf_range(-HALF.z, HALF.z))
		leaf.pos.y = randf_range(LOW, HIGH)
		leaf.age = randf() * leaf.life # start mid-life so they don't all pop in together
		_leaves.append(leaf)


func _new_leaf() -> Dictionary:
	return {
		"pos": Vector3.ZERO,
		"axis": Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized(),
		"spin": randf_range(2.0, 6.0) * (1.0 if randf() < 0.5 else -1.0),
		"angle": randf() * TAU,
		"phase": randf() * TAU,
		"size": randf_range(0.34, 0.52),
		"speed": randf_range(0.75, 1.25),
		"colour": COLOURS[randi() % COLOURS.size()],
		"age": 0.0,
		"life": randf_range(4.0, 7.5),
	}


## Put a leaf back in on the upwind side of the box.
func _respawn(leaf: Dictionary) -> void:
	var c := _centre()
	var dir := wind.normalized() if wind.length() > 0.01 else Vector3.RIGHT
	var side := Vector3(-dir.z, 0.0, dir.x)
	var reach := absf(dir.x) * HALF.x + absf(dir.z) * HALF.z
	leaf.pos = c - dir * reach * randf_range(0.6, 1.0) + side * randf_range(-HALF.x, HALF.x)
	leaf.pos.y = randf_range(LOW, HIGH)
	leaf.age = 0.0
	leaf.life = randf_range(4.0, 7.5)


func _process(delta: float) -> void:
	_time += delta
	_fade = move_toward(_fade, _target_fade, delta * 1.5)
	if _fade <= 0.0:
		_mm.visible_instance_count = 0
		if _target_fade <= 0.0:
			_leaves.clear()
		return
	var want := _count()
	while _leaves.size() < want:
		var leaf := _new_leaf()
		_respawn(leaf)
		_leaves.append(leaf)
	if _leaves.size() > want:
		_leaves.resize(want)
	# Gusts: the visual wind breathes a little around the real value.
	var gust := 1.0 + 0.25 * sin(_time * 0.9) + 0.12 * sin(_time * 2.3)
	var c := _centre()
	var dir := wind.normalized()
	var side := Vector3(-dir.z, 0.0, dir.x)
	var reach := absf(dir.x) * HALF.x + absf(dir.z) * HALF.z
	for i in _leaves.size():
		var leaf: Dictionary = _leaves[i]
		leaf.age += delta
		var t: float = _time + leaf.phase
		var v: Vector3 = wind * gust * leaf.speed
		v += side * sin(t * 1.7) * 0.6 # sway across the wind
		v.y = sin(t * 2.4) * 0.5 - 0.08 # bob, slowly sinking
		if leaf.pos.y < LOW:
			v.y = absf(v.y) + 0.3 # skim back up off the ground
		leaf.pos += v * delta
		leaf.angle += leaf.spin * delta * (0.6 + 0.4 * gust)
		var rel: Vector3 = leaf.pos - c
		var along := rel.dot(dir)
		if leaf.age > leaf.life or along > reach or absf(rel.dot(side)) > HALF.x * 1.3:
			_respawn(leaf)
		# Grow in, shrink out (and with the overall fade).
		var life_k: float = minf(leaf.age / 0.6, 1.0) * minf((leaf.life - leaf.age) / 0.8, 1.0)
		var s: float = leaf.size * clampf(life_k, 0.0, 1.0) * _fade
		var b := Basis(leaf.axis, leaf.angle) * Basis(Vector3.UP, leaf.phase)
		b = b.scaled(Vector3.ONE * maxf(s, 0.001))
		_mm.set_instance_transform(i, Transform3D(b, leaf.pos))
		_mm.set_instance_color(i, leaf.colour)
	_mm.visible_instance_count = _leaves.size()


## A small leaf in the XY plane, 1 unit long: two halves (light / dark) with a
## pointed tip, and a short stem.
static func _leaf_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var steps := 10
	var outline_l: Array[Vector3] = []
	var outline_r: Array[Vector3] = []
	for k in steps + 1:
		var t := float(k) / steps
		var y := lerpf(-0.5, 0.5, t)
		var w := pow(sin(PI * t), 0.85) * (0.55 + 0.45 * (1.0 - t)) * 0.32
		outline_l.append(Vector3(-w, y, 0.0))
		outline_r.append(Vector3(w, y, 0.0))
	for k in steps:
		var a := Vector3(0, lerpf(-0.5, 0.5, float(k) / steps), 0)
		var b := Vector3(0, lerpf(-0.5, 0.5, float(k + 1) / steps), 0)
		# Left half (slightly darker), right half (lighter); a tiny fold in z.
		for tri in [[a, outline_l[k], outline_l[k + 1]], [a, outline_l[k + 1], b]]:
			for p in tri:
				verts.append(p + Vector3(0, 0, -absf(p.x) * 0.25))
				cols.append(Color(0.82, 0.82, 0.82))
		for tri in [[a, outline_r[k + 1], outline_r[k]], [a, b, outline_r[k + 1]]]:
			for p in tri:
				verts.append(p + Vector3(0, 0, -absf(p.x) * 0.25))
				cols.append(Color(1, 1, 1))
	# Stem.
	for p in [Vector3(-0.015, -0.5, 0), Vector3(0.015, -0.5, 0), Vector3(0.0, -0.66, 0)]:
		verts.append(p)
		cols.append(Color(0.6, 0.6, 0.6))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3(0, 0, 1))
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
