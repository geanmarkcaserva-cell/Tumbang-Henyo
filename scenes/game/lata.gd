extends RigidBody3D
## The lata (can). Counts as "down" when it tips past tip_angle_deg
## or slides out of its circle. Clanks when something hits it hard and
## clinks as it bounces and rolls.

signal knocked_down

@export var tip_angle_deg := 60.0
@export var circle_radius := 0.6
const CLANK_SPEED := 3.5 ## m/s change in one step: a real hit (full clank)
const CLINK_SPEED := 1.2 ## smaller bumps: bounces and rolls (soft clink)

var is_down := false
var _home: Vector3
var _pending_reset := false
var _last_vel := Vector3.ZERO
var _sound_cd := 0.0


## The can's look: the textured can model (art/sk_court/can.glb) fitted to
## the collision cylinder (0.4 m tall, 0.15 m radius). The plain red
## cylinder stays as a fallback.
const CAN_MODEL := "res://art/sk_court/can.glb"
const CAN_HEIGHT := 0.4
const CAN_RADIUS := 0.15


func _ready() -> void:
	_home = global_position
	add_to_group("lata")
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
	if is_down or _pending_reset:
		return
	var up := global_transform.basis.y.normalized()
	var tilt := rad_to_deg(acos(clampf(up.dot(Vector3.UP), -1.0, 1.0)))
	var offset := Vector2(global_position.x - _home.x, global_position.z - _home.z).length()
	if tilt > tip_angle_deg or offset > circle_radius:
		is_down = true
		knocked_down.emit()


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
	is_down = false
	_pending_reset = true
	sleeping = false


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not _pending_reset:
		return
	state.transform = Transform3D(Basis.IDENTITY, _home)
	state.linear_velocity = Vector3.ZERO
	state.angular_velocity = Vector3.ZERO
	_last_vel = Vector3.ZERO
	_pending_reset = false
