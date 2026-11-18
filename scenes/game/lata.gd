extends RigidBody3D
## The lata (can). Counts as "down" when it tips past tip_angle_deg
## or slides out of its circle. Clanks when something hits it hard and
## clinks as it bounces and rolls.
##
## Never lost: if a hard hit sends it somewhere no taya can get to (over
## the fence, through the ground, up on a roof or a cart), it's brought back
## lying on its side next to its circle, so the taya can stand it up.

signal knocked_down

@export var tip_angle_deg := 60.0
@export var circle_radius := 0.6
const CLANK_SPEED := 3.5 ## m/s change in one step: a real hit (full clank)
const CLINK_SPEED := 1.2 ## smaller bumps: bounces and rolls (soft clink)
const LOST_AFTER := 0.8 ## seconds out of reach before it's brought back
const ROLL_DAMP := 1.6 ## slows its sliding / rolling (higher = stops sooner)
const SPIN_DAMP := 3.0 ## slows its spinning and rolling over
const HIGH_UP := 0.9 ## resting this far above its circle = on something (a roof, a cart)

var is_down := false
var _home: Vector3
var _pending_reset := false
var _last_vel := Vector3.ZERO
var _sound_cd := 0.0
var _lost_time := 0.0
var _pending_drop := false
var carried := false ## a taya is carrying it back to its circle
var _saved_layers := Vector2i(1, 1)


## The can's look: the textured can model (art/sk_court/can.glb) fitted to
## the collision cylinder (0.4 m tall, 0.15 m radius). The plain red
## cylinder stays as a fallback.
const CAN_MODEL := "res://art/sk_court/can.glb"
const CAN_HEIGHT := 0.4
const CAN_RADIUS := 0.15


func _ready() -> void:
	_home = global_position
	add_to_group("lata")
	continuous_cd = true # a hard hit can't push it through the ground
	# Knocked over, it tumbles a little and settles instead of rolling away.
	linear_damp = ROLL_DAMP
	angular_damp = SPIN_DAMP
	var surface := PhysicsMaterial.new()
	surface.friction = 1.0
	surface.rough = true
	surface.bounce = 0.15
	physics_material_override = surface
	_dress()


func _dress() -> void:
	if not ResourceLoader.exists(CAN_MODEL):
		return
	var can: Node3D = (load(CAN_MODEL) as PackedScene).instantiate()
	var holder := Node3D.new()
	holder.name = "CanModel"
	add_child(holder)
	holder.add_child(can)
	var box := EasterEggs.bounds(can)
	if box.size.y <= 0.0001:
		holder.queue_free()
		return
	var ky := CAN_HEIGHT / box.size.y
	var kxz := CAN_RADIUS * 2.0 / maxf(box.size.x, box.size.z)
	can.scale = Vector3(kxz, ky, kxz)
	var c := box.get_center()
	can.position = Vector3(-c.x * kxz, -c.y * ky, -c.z * kxz)
	var plain := get_node_or_null("Mesh") as Node3D
	if plain:
		plain.visible = false


func _physics_process(delta: float) -> void:
	_impact_sound(delta)
	if _pending_reset or _pending_drop or carried:
		return
	if _out_of_reach():
		_lost_time += delta
		if _lost_time >= LOST_AFTER or global_position.y < _home.y - 3.0:
			_lost_time = 0.0
			if not is_down:
				is_down = true
				knocked_down.emit()
			_pending_drop = true
			sleeping = false
		return
	_lost_time = 0.0
	if is_down:
		return
	var up := global_transform.basis.y.normalized()
	var tilt := rad_to_deg(acos(clampf(up.dot(Vector3.UP), -1.0, 1.0)))
	var offset := Vector2(global_position.x - _home.x, global_position.z - _home.z).length()
	if tilt > tip_angle_deg or offset > circle_radius:
		is_down = true
		knocked_down.emit()


## Somewhere a taya can't walk to: outside the barangay's fence, under the
## ground, or resting up on something.
func _out_of_reach() -> bool:
	var p := global_position
	if not p.is_finite() or p.y < _home.y - 1.0:
		return true
	if p.y > _home.y + HIGH_UP and linear_velocity.length() < 0.5:
		return true
	var root := get_tree().root
	if root.has_meta("play_area"):
		var area: Rect2 = (root.get_meta("play_area") as Rect2).grow(-0.3)
		if not area.has_point(Vector2(p.x, p.z)):
			return true
	return false


## A sudden change of speed means it was hit or bounced: clank or clink.
func _impact_sound(delta: float) -> void:
	_sound_cd -= delta
	var dv := (linear_velocity - _last_vel).length()
	_last_vel = linear_velocity
	if _pending_reset or _sound_cd > 0.0 or dv < CLINK_SPEED:
		return
	_sound_cd = 0.09
	if dv >= CLANK_SPEED:
		Sfx.play_at("lata_hit", global_position, 0.0, 1.0, 0.05)
	else:
		var loud := clampf(dv / CLANK_SPEED, 0.25, 1.0)
		Sfx.play_at("lata_set", global_position, linear_to_db(loud), 1.15, 0.12)


## Stand the lata back up in its circle. Applied on the next physics step
## so the physics engine doesn't fight the teleport.
func reset_to_home() -> void:
	carry(false)
	is_down = false
	_pending_drop = false
	_lost_time = 0.0
	_pending_reset = true
	sleeping = false


## Where the lata stands (the middle of its circle).
func home() -> Vector3:
	return _home


## A taya picks it up (true) / lets go (false). While carried it's not a
## physics object: no gravity, it doesn't bump anyone, and it follows hold().
func carry(on: bool) -> void:
	if on == carried:
		return
	carried = on
	if on:
		_saved_layers = Vector2i(collision_layer, collision_mask)
		collision_layer = 0
		collision_mask = 0
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		freeze = true
	else:
		collision_layer = _saved_layers.x
		collision_mask = _saved_layers.y
		freeze = false
		sleeping = false


## Carried: upright, at `at` (in front of the taya).
func hold(at: Vector3) -> void:
	if carried:
		global_transform = Transform3D(Basis.IDENTITY, at)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _pending_drop:
		# Back by its circle, lying on its side (still down).
		var side := randf() * TAU
		var lying := Basis(Vector3.UP, side) * Basis(Vector3.RIGHT, PI * 0.5)
		state.transform = Transform3D(lying, _home + Vector3(cos(side), 0.0, sin(side)) * 0.4 + Vector3.UP * 0.16)
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		_last_vel = Vector3.ZERO
		_pending_drop = false
		return
	if not _pending_reset:
		return
	state.transform = Transform3D(Basis.IDENTITY, _home)
	state.linear_velocity = Vector3.ZERO
	state.angular_velocity = Vector3.ZERO
	_last_vel = Vector3.ZERO
	_pending_reset = false
