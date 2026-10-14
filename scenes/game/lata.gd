extends RigidBody3D
## The lata (can). Counts as "down" when it tips past tip_angle_deg
## or slides out of its circle.

signal knocked_down

@export var tip_angle_deg := 60.0
@export var circle_radius := 0.6

var is_down := false
var _home: Vector3
var _pending_reset := false


func _ready() -> void:
	_home = global_position


func _physics_process(_delta: float) -> void:
	if is_down or _pending_reset:
		return
	var up := global_transform.basis.y.normalized()
	var tilt := rad_to_deg(acos(clampf(up.dot(Vector3.UP), -1.0, 1.0)))
	var offset := Vector2(global_position.x - _home.x, global_position.z - _home.z).length()
	if tilt > tip_angle_deg or offset > circle_radius:
		is_down = true
		knocked_down.emit()


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
	_pending_reset = false
