extends RigidBody3D
## A thrown tsinelas. Spins end over end, gets pushed by the wind while
## airborne, and emits `settled` once it has come to rest.
##
## The HitZone sphere is a forgiving hitbox: if it touches the lata while
## the tsinelas is still moving fast, the lata gets knocked as if hit
## directly. The real collision shape stays slipper-sized so it lands flat.

signal settled
signal hit_target(body: Node3D) ## the hitbox caught something in target_group

## Which group the forgiving hitbox looks for: "lata" for the player's
## throws, "player" for the taya's throws.
@export var target_group := "lata"
## Radius of the forgiving hitbox. The player's throws get a big one,
## the taya's throws a small one so they're dodgeable.
@export var hit_radius := 0.4

const SETTLE_SPEED := 0.3 ## below this speed (m/s) it counts as still
const SETTLE_TIME := 0.4 ## seconds it must stay still
const MAX_LIFETIME := 5.0
const MIN_HIT_SPEED := 3.0 ## the hitbox only counts while the tsinelas is flying fast
const HIT_PUSH := 0.5 ## multiplier on the tsinelas momentum passed to the lata

var _wind_accel := Vector3.ZERO
var _airborne := false
var _time := 0.0
var _still_time := 0.0
var _done := false
var _has_hit := false

@onready var _hit_zone: Area3D = $HitZone


func _ready() -> void:
	_hit_zone.body_entered.connect(_on_hit_zone_body_entered)


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


func _on_hit_zone_body_entered(body: Node3D) -> void:
	if _has_hit or not body.is_in_group(target_group):
		return
	if linear_velocity.length() < MIN_HIT_SPEED:
		return
	_has_hit = true
	if body is RigidBody3D:
		var rigid := body as RigidBody3D
		var push := linear_velocity * mass * HIT_PUSH
		push.y = maxf(push.y, 0.4) # always a little lift so it tips instead of sliding
		rigid.sleeping = false
		# Hit slightly above its middle so it topples over.
		rigid.apply_impulse(push, Vector3(0.0, 0.12, 0.0))
	hit_target.emit(body)
