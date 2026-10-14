extends RigidBody3D
## A thrown tsinelas. Spins end over end, gets pushed by the wind while
## airborne, and emits `settled` once it has come to rest.

signal settled

const SETTLE_SPEED := 0.3 ## below this speed (m/s) it counts as still
const SETTLE_TIME := 0.4 ## seconds it must stay still
const MAX_LIFETIME := 5.0

var _wind_accel := Vector3.ZERO
var _airborne := false
var _time := 0.0
var _still_time := 0.0
var _done := false


func launch(velocity: Vector3, wind_accel: Vector3) -> void:
	linear_velocity = velocity
	# Flip end over end around the slipper's own side axis.
	angular_velocity = global_basis.x * randf_range(-14.0, -9.0) + Vector3.UP * randf_range(-2.0, 2.0)
	_wind_accel = wind_accel
	_airborne = true


func _physics_process(delta: float) -> void:
	if _done:
		return
	_time += delta
	if get_contact_count() > 0:
		_airborne = false
	if _airborne:
		apply_central_force(_wind_accel * mass)

	if _time > 0.3 and linear_velocity.length() < SETTLE_SPEED:
		_still_time += delta
	else:
		_still_time = 0.0

	if _still_time > SETTLE_TIME or _time > MAX_LIFETIME or global_position.y < -5.0:
		_done = true
		settled.emit()
