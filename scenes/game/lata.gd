extends RigidBody3D
## The lata (can). Counts as "down" when it tips past tip_angle_deg
## or slides out of its circle.

signal knocked_down

@export var tip_angle_deg := 60.0
@export var circle_radius := 0.6

var is_down := false
var _home: Vector3


func _ready() -> void:
	_home = global_position


func _physics_process(_delta: float) -> void:
	if is_down:
		return
	var up := global_transform.basis.y.normalized()
	var tilt := rad_to_deg(acos(clampf(up.dot(Vector3.UP), -1.0, 1.0)))
	var offset := Vector2(global_position.x - _home.x, global_position.z - _home.z).length()
	if tilt > tip_angle_deg or offset > circle_radius:
		is_down = true
		knocked_down.emit()


## Stand the lata back up in its circle (used by the taya's Reset state later).
func reset_to_home() -> void:
	is_down = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = Transform3D(Basis.IDENTITY, _home)
