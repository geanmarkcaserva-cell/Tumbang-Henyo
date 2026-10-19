extends Node3D
## Bullseye! The round's first throw, with no mistakes before it, flying
## clean into the lata (no bounce off the ground or anything else first).
##
## While the tsinelas flies, this looks a moment ahead along its arc. When it
## is about to hit the lata clean, time slows right down and a camera locks
## onto the tsinelas for a close-up of the impact, then eases back to normal.
## If the throw only clips the lata through the forgiving hitbox (so it
## wasn't predicted), the slow-mo starts at the moment of the hit instead.

signal bullseye ## a perfect, clean hit
signal finished ## the cinematic is over and the normal camera is back

const LOOKAHEAD := 0.3 ## game seconds ahead to check for a hit
const SLOW := 0.12 ## time scale during the close-up
const EASE_IN := 0.12 ## real seconds to slow down
const EASE_OUT := 0.3 ## real seconds to speed back up
const HOLD_AFTER_HIT := 1.25 ## real seconds of slow-mo after the impact
const GIVE_UP := 0.7 ## game seconds in slow-mo with no hit: it's not happening
const CAN_RADIUS := 0.12

var _slipper ## the thrown tsinelas (tsinelas.gd)
var _lata: Node3D
var _wind := Vector3.ZERO
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _watching := false
var _cine := false
var _hit := false
var _cine_time := 0.0 ## game seconds since the slow-mo started
var _cam: Camera3D
var _prev_cam: Camera3D
var _approach := Vector3.FORWARD ## flat direction the tsinelas flies in
var _focus := Vector3.ZERO
var _orbit := 0.0
var _last_us := 0
var _time_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _exit_tree() -> void:
	Engine.time_scale = 1.0


func is_running() -> bool:
	return _cine


## Follow this throw. Only call it for a throw that can still be a bullseye.
func watch(slipper: Node3D, lata: Node3D, wind_accel: Vector3) -> void:
	cancel()
	_slipper = slipper
	_lata = lata
	_wind = wind_accel
	_watching = true
	_hit = false
	slipper.hit_target.connect(_on_hit, CONNECT_ONE_SHOT)


## Stop at once (new attempt, game over...).
func cancel() -> void:
	_watching = false
	if _cine:
		_end(true)


func _physics_process(delta: float) -> void:
	if _cine:
		_cine_time += delta
		if not _hit and (_cine_time > GIVE_UP or not is_instance_valid(_slipper) or not _slipper.is_clean()):
			_watching = false
			_end(false) # predicted, but it didn't connect clean after all
		return
	if not _watching:
		return
	if not is_instance_valid(_slipper) or not _slipper.is_clean():
		_watching = false # touched the ground first: no bullseye this time
		return
	if _about_to_hit():
		_start()


## Will the tsinelas, on its current arc, reach the lata in the next moment
## without touching the ground first?
func _about_to_hit() -> bool:
	var p: Vector3 = _slipper.global_position
	var v: Vector3 = _slipper.linear_velocity
	var a := Vector3(0.0, -_gravity, 0.0) + _wind
	var target := _lata.global_position
	var reach: float = _slipper.hit_radius + CAN_RADIUS
	var prev := p
	var t := 0.0
	while t < LOOKAHEAD:
		t += 1.0 / 120.0
		var next := p + v * t + 0.5 * a * t * t
		if next.y < 0.03:
			return false
		if _segment_distance(prev, next, target) <= reach:
			return true
		prev = next
	return false


func _on_hit(_body: Node3D) -> void:
	if not _watching and not _cine:
		return
	if not is_instance_valid(_slipper) or not _slipper.is_clean():
		if _cine:
			_end(false)
		return
	_hit = true
	_watching = false
	if not _cine:
		_start() # clipped it through the hitbox: slow-mo from the impact
	bullseye.emit()
	await get_tree().create_timer(HOLD_AFTER_HIT, false, false, true).timeout
	if _cine:
		_end(false)


func _start() -> void:
	_cine = true
	_cine_time = 0.0
	_orbit = 0.0
	_prev_cam = get_viewport().get_camera_3d()
	var v: Vector3 = _slipper.linear_velocity
	_approach = Vector3(v.x, 0.0, v.z).normalized()
	if _approach.length() < 0.1:
		_approach = Vector3.FORWARD
	_focus = _slipper.global_position
	_cam = Camera3D.new()
	_cam.fov = 48.0
	_cam.near = 0.03
	add_child(_cam)
	_cam.global_position = _desired_cam_position()
	_cam.look_at(_focus, Vector3.UP)
	_cam.make_current()
	_last_us = Time.get_ticks_usec()
	_tween_time_scale(SLOW, EASE_IN)


func _end(instant: bool) -> void:
	_cine = false
	if instant:
		if _time_tween:
			_time_tween.kill()
		Engine.time_scale = 1.0
		_restore_camera()
		finished.emit()
		return
	_tween_time_scale(1.0, EASE_OUT)
	await _time_tween.finished
	if _cine:
		return # a new one started meanwhile
	_restore_camera()
	finished.emit()


func _restore_camera() -> void:
	if is_instance_valid(_prev_cam):
		_prev_cam.make_current()
	if is_instance_valid(_cam):
		_cam.queue_free()
	_cam = null


func _tween_time_scale(to: float, seconds: float) -> void:
	if _time_tween:
		_time_tween.kill()
	_time_tween = create_tween().set_ignore_time_scale(true)
	_time_tween.tween_property(Engine, "time_scale", to, seconds).set_trans(Tween.TRANS_SINE)


func _process(_delta: float) -> void:
	if not _cine or _cam == null:
		return
	# Real (unscaled) time, so the camera glides smoothly in slow motion.
	var now := Time.get_ticks_usec()
	var dt := clampf((now - _last_us) / 1000000.0, 0.0, 0.05)
	_last_us = now
	if get_tree().paused:
		return
	_orbit += dt * 0.55 # a slow swing around the shot
	var subject: Vector3 = _focus
	if is_instance_valid(_slipper):
		subject = _slipper.global_position
	# Before the hit: stay on the tsinelas. After: drift toward the flying lata.
	if _hit and is_instance_valid(_lata):
		subject = subject.lerp(_lata.global_position, 0.5)
	_focus = _focus.lerp(subject, 1.0 - exp(-14.0 * dt))
	_cam.global_position = _cam.global_position.lerp(_desired_cam_position(), 1.0 - exp(-9.0 * dt))
	if _cam.global_position.distance_to(_focus) > 0.05:
		_cam.look_at(_focus, Vector3.UP)


## Just behind and to the side of the tsinelas, a little above, swinging round.
func _desired_cam_position() -> Vector3:
	var side := _approach.cross(Vector3.UP).normalized()
	var offset := (-_approach * 1.3 + side * 0.9).rotated(Vector3.UP, _orbit) + Vector3.UP * 0.32
	var pos := _focus + offset
	pos.y = maxf(pos.y, 0.15) # never under the court
	return pos


static func _segment_distance(a: Vector3, b: Vector3, p: Vector3) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.000001:
		return a.distance_to(p)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return (a + ab * t).distance_to(p)
