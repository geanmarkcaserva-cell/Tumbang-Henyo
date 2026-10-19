extends Node3D
## Something Mama throws: a plastic clothes hanger (kind 0) or a walis tambo
## (kind 1). Flies on a simple ballistic arc, spinning; hits the player if it
## passes close to their body, otherwise clatters to the ground (or off a
## wall) and shrinks away. Low-poly, built from a few boxes and cylinders.

signal hit_target

const GRAVITY := 20.0
const HIT_RADIUS := 0.7 ## around the player's chest
const LIFETIME := 6.0
const HANGER_COLORS := [Color(1.0, 0.45, 0.65), Color(0.35, 0.72, 1.0), Color(0.6, 0.9, 0.3), Color(1.0, 0.85, 0.3)]

var kind := 0

var _vel := Vector3.ZERO
var _target: Node3D
var _exclude: Array[RID] = []
var _flying := false
var _life := 0.0
var _spin_axis := Vector3.RIGHT
var _spin_speed := 12.0
var _model: Node3D


func _ready() -> void:
	_model = Node3D.new()
	add_child(_model)
	if kind == 0:
		_build_hanger()
		_spin_axis = Vector3(0.15, 1.0, 0.1).normalized() # frisbee spin
		_spin_speed = 16.0
	else:
		_build_broom()
		_spin_axis = Vector3.RIGHT # end over end
		_spin_speed = 11.0


func launch(origin: Vector3, velocity: Vector3, target: Node3D, exclude: Array) -> void:
	global_position = origin
	_vel = velocity
	_target = target
	for r in exclude:
		_exclude.append(r)
	if target is CollisionObject3D:
		_exclude.append((target as CollisionObject3D).get_rid())
	_flying = true
	if kind == 1:
		# Point the broom along its flight so it tumbles forward.
		var flat := Vector3(velocity.x, 0.0, velocity.z)
		if flat.length() > 0.1:
			rotation.y = atan2(-flat.x, -flat.z)


func _physics_process(delta: float) -> void:
	_life += delta
	if _life > LIFETIME:
		queue_free()
		return
	if not _flying:
		return
	var from := global_position
	_vel.y -= GRAVITY * delta
	var to := from + _vel * delta
	if _target and is_instance_valid(_target):
		var chest := _target.global_position + Vector3.UP * 0.9
		if _segment_distance(from, to, chest) <= HIT_RADIUS:
			hit_target.emit()
			_poof()
			return
	var q := PhysicsRayQueryParameters3D.create(from, to, 1, _exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		global_position = hit.position + hit.normal * 0.06
		_land()
		return
	if to.y <= 0.06:
		global_position = Vector3(to.x, 0.06, to.z)
		_land()
		return
	global_position = to
	_model.rotate(_spin_axis, _spin_speed * delta)


## On the ground (or bounced off a wall): lie flat, then shrink away.
func _land() -> void:
	_flying = false
	global_position.y = 0.06
	_model.rotation = Vector3(0.0, randf() * TAU, 0.0)
	if kind == 0:
		_model.rotation.x = -PI * 0.5 # hanger flat on the ground
	else:
		_model.rotation.z = PI * 0.5 # broom lying down
		_model.position.y = 0.04
	var t := create_tween()
	t.tween_interval(1.2)
	t.tween_property(_model, "scale", Vector3.ONE * 0.01, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_callback(queue_free)


## Hit the player: a quick pop instead of lying around.
func _poof() -> void:
	_flying = false
	var t := create_tween()
	t.tween_property(_model, "scale", Vector3.ONE * 1.5, 0.06)
	t.tween_property(_model, "scale", Vector3.ONE * 0.01, 0.14)
	t.tween_callback(queue_free)


static func _segment_distance(a: Vector3, b: Vector3, p: Vector3) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.000001:
		return a.distance_to(p)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return (a + ab * t).distance_to(p)


# --- Models -------------------------------------------------------------------

## Wire-style plastic hanger: a triangle and a hook, in a bright colour.
func _build_hanger() -> void:
	var mat := _mat(HANGER_COLORS[randi() % HANGER_COLORS.size()])
	var s := 1.35 # a bit bigger than life so it reads at a distance
	var t := 0.045 * s
	_bar(Vector2(-0.22, 0.0) * s, Vector2(0.22, 0.0) * s, t, mat)
	_bar(Vector2(-0.22, 0.0) * s, Vector2(0.0, 0.16) * s, t, mat)
	_bar(Vector2(0.22, 0.0) * s, Vector2(0.0, 0.16) * s, t, mat)
	_bar(Vector2(0.0, 0.16) * s, Vector2(0.0, 0.21) * s, t, mat)
	var hook := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.035 * s
	torus.outer_radius = 0.065 * s
	torus.rings = 8
	torus.ring_segments = 4
	hook.mesh = torus
	hook.material_override = mat
	hook.rotation.x = PI * 0.5
	hook.position = Vector3(0.0, 0.26, 0.0) * s
	_model.add_child(hook)
	_model.position.y = -0.1


## Walis tambo: wooden handle with a red plastic band, flat fan of straw.
func _build_broom() -> void:
	var handle := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.028
	hm.bottom_radius = 0.028
	hm.height = 0.9
	hm.radial_segments = 6
	hm.rings = 1
	handle.mesh = hm
	handle.material_override = _mat(Color(0.72, 0.52, 0.3))
	handle.position.y = 0.3
	_model.add_child(handle)
	var band := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.042
	bm.bottom_radius = 0.042
	bm.height = 0.1
	bm.radial_segments = 6
	bm.rings = 1
	band.mesh = bm
	band.material_override = _mat(Color(0.85, 0.12, 0.12))
	band.position.y = -0.12
	_model.add_child(band)
	var head := MeshInstance3D.new()
	var fan := CylinderMesh.new()
	fan.top_radius = 0.05
	fan.bottom_radius = 0.26
	fan.height = 0.5
	fan.radial_segments = 8
	fan.rings = 1
	head.mesh = fan
	head.material_override = _mat(Color(0.88, 0.76, 0.45))
	head.position.y = -0.4
	head.scale = Vector3(1.0, 1.0, 0.28) # flat fan
	_model.add_child(head)


func _bar(a: Vector2, b: Vector2, thickness: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(a.distance_to(b) + thickness, thickness, thickness)
	mi.mesh = box
	mi.material_override = mat
	var mid := (a + b) * 0.5
	mi.position = Vector3(mid.x, mid.y, 0.0)
	mi.rotation.z = atan2(b.y - a.y, b.x - a.x)
	_model.add_child(mi)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.7
	return m
