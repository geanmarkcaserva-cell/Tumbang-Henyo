class_name PaperDoll
extends Node3D
## South Park-style paper cutout: a flat pixel sprite that always turns to
## face the camera, hops and wobbles side to side while its body moves, and
## breathes a little when standing still. Shows the back view when the body
## faces away from the camera. Put it under a CharacterBody3D.
##
## Sheets are horizontal strips (see PixelArt.character_look): the front strip
## loops all the time, the back (run) strip loops while the body is moving.

@export var pixel_size := 0.08
@export var hop_height := 0.16 ## metres at full speed
@export var wobble_deg := 9.0
@export var shadow_radius := 0.42

var _look := {}
var _sprite: Sprite3D
var _phase := 0.0
var _moving := 0.0
var _height := 1.76
var _foot := 0.0
var _front_t := 0.0
var _back_t := 0.0
var _showing_front := true


func _ready() -> void:
	_sprite = Sprite3D.new()
	_sprite.pixel_size = pixel_size
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_sprite.shaded = false
	_sprite.double_sided = true
	add_child(_sprite)

	# Soft round shadow on the ground keeps the cutout from floating.
	var shadow := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = shadow_radius
	disc.bottom_radius = shadow_radius
	disc.height = 0.01
	disc.radial_segments = 24
	shadow.mesh = disc
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0, 0, 0, 0.32)
	shadow.material_override = mat
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadow.position.y = 0.045
	add_child(shadow)


## Use a look from PixelArt.character_look() / placeholder_look().
func set_look(look: Dictionary) -> void:
	_look = look
	pixel_size = look.pixel_size
	_sprite.pixel_size = pixel_size
	_height = look.frame_h * pixel_size
	_foot = look.foot_pad * pixel_size
	_show(true)


## Single still images (placeholder tayas).
func set_textures(front: Texture2D, back: Texture2D = null) -> void:
	set_look({"front": front, "back": back, "front_frames": 1, "back_frames": 1, "front_fps": 0.0,
		"back_fps": 0.0, "frame_h": front.get_height(), "foot_pad": 0, "pixel_size": pixel_size})


func set_tint(color: Color) -> void:
	_sprite.modulate = color


func _show(front: bool) -> void:
	_showing_front = front or _look.back == null
	var frames: int = _look.front_frames if _showing_front else _look.back_frames
	_sprite.frame = 0
	_sprite.texture = _look.front if _showing_front else _look.back
	_sprite.hframes = maxi(frames, 1)


func _process(delta: float) -> void:
	if _look.is_empty():
		return
	var body := get_parent() as Node3D
	var speed := 0.0
	if body is CharacterBody3D:
		var v: Vector3 = body.velocity
		speed = Vector2(v.x, v.z).length()
	_moving = move_toward(_moving, clampf(speed / 5.0, 0.0, 1.0), delta * 6.0)
	_phase += delta * (4.0 + speed * 2.2)

	var cam := get_viewport().get_camera_3d()
	if cam and body:
		var to_cam := cam.global_position - global_position
		to_cam.y = 0.0
		if to_cam.length() > 0.01:
			# Manual billboard (turn around Y only) so the sprite can still tilt.
			global_rotation = Vector3(0.0, atan2(to_cam.x, to_cam.z), 0.0)
			var facing := -body.global_basis.z
			facing.y = 0.0
			var want_front: bool = _look.back == null or facing.dot(to_cam) >= 0.0
			if want_front != _showing_front:
				_show(want_front)

	# Frame animation: the front sheet always loops; the run sheet loops
	# while moving (faster when sprinting) and rests on frame 0 when still.
	if _showing_front:
		_front_t += delta * _look.front_fps
		_sprite.frame = int(_front_t) % _sprite.hframes
	else:
		if _moving > 0.15:
			_back_t += delta * _look.back_fps * clampf(speed / 5.0, 0.6, 1.8)
		else:
			_back_t = 0.0
		_sprite.frame = int(_back_t) % _sprite.hframes

	var hop := absf(sin(_phase)) * hop_height * _moving
	var breathe := sin(_phase * 0.5) * 0.015 * (1.0 - _moving)
	_sprite.scale = Vector3(1.0 - breathe, 1.0 + breathe, 1.0)
	# Centre of the frame, lowered by the empty rows under the feet.
	_sprite.position = Vector3(0.0, _height * 0.5 - _foot + hop, 0.0)
	_sprite.rotation.z = sin(_phase) * deg_to_rad(wobble_deg) * _moving
