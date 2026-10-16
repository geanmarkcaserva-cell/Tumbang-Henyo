class_name PaperDoll
extends Node3D
## South Park-style paper cutout: a flat pixel sprite that always turns to
## face the camera, hops and wobbles side to side while its body moves, and
## breathes a little when standing still. Shows the back view when the body
## faces away from the camera. Put it under a CharacterBody3D.

@export var pixel_size := 0.08
@export var hop_height := 0.16 ## metres at full speed
@export var wobble_deg := 9.0
@export var shadow_radius := 0.42

var _front: Texture2D
var _back: Texture2D
var _sprite: Sprite3D
var _phase := 0.0
var _moving := 0.0
var _height := 1.76


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


func set_textures(front: Texture2D, back: Texture2D = null) -> void:
	_front = front
	_back = back
	_height = front.get_height() * pixel_size
	_sprite.texture = front


func set_tint(color: Color) -> void:
	_sprite.modulate = color


func _process(delta: float) -> void:
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
			var show_front := _back == null or facing.dot(to_cam) >= 0.0
			_sprite.texture = _front if show_front else _back

	var hop := absf(sin(_phase)) * hop_height * _moving
	var breathe := sin(_phase * 0.5) * 0.015 * (1.0 - _moving)
	_sprite.scale = Vector3(1.0 - breathe, 1.0 + breathe, 1.0)
	_sprite.position = Vector3(0.0, _height * 0.5 + hop, 0.0)
	_sprite.rotation.z = sin(_phase) * deg_to_rad(wobble_deg) * _moving
