class_name PaperDoll
extends Node3D
## South Park-style paper cutout: a flat pixel sprite that always turns to
## face the camera, hops and wobbles side to side while its body moves, and
## breathes a little when standing still. Put it under a CharacterBody3D.
##
## Uses the three character sheets (see PixelArt.character_look):
##   idle  - body faces the camera (loops all the time)
##   run   - body faces away from the camera (loops while moving)
##   happy - play_happy(): the cutout flips to face the camera and celebrates

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
var _state := ""
var _anim_t := 0.0
var _happy_left := 0.0 ## seconds of happy left; < 0 = until stop_happy()
var _tint := Color.WHITE
var _alpha := 1.0
var _hurt_t := 99.0 ## time since hurt() (>= HURT_TIME = not hurt)

const HURT_TIME := 0.5 ## the squish wobbles out over this long
const HURT_SQUISH := 0.38 ## how flat it goes at first (0.38 = 38% wider, 38% shorter)
const HURT_RED := Color(1.7, 0.28, 0.28) ## flash colour (over 1 = glows a bit)
## The red flashes: on, off, on (seconds since the hit).
const HURT_FLASHES := [Vector2(0.0, 0.1), Vector2(0.16, 0.24)]
## Tinting can't turn dark pixels (hair, outlines) red, so the flash also lays a
## red silhouette of the current frame over the sprite.
const FLASH_SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix;
uniform sampler2D tex : source_color, filter_nearest;
uniform float frames = 1.0;
uniform float frame = 0.0;
uniform vec4 col : source_color = vec4(1.0, 0.12, 0.12, 0.7);
void fragment() {
	float a = texture(tex, vec2((UV.x + frame) / frames, UV.y)).a;
	if (a < 0.5) { discard; }
	ALBEDO = col.rgb;
	ALPHA = col.a;
}
"""
static var _flash_shader: Shader
var _flash: MeshInstance3D
var _flash_mat: ShaderMaterial


func _ready() -> void:
	_sprite = Sprite3D.new()
	_sprite.pixel_size = pixel_size
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_sprite.shaded = false
	_sprite.double_sided = true
	add_child(_sprite)

	# Red silhouette for the hurt flash (follows the sprite's squish and wobble).
	if _flash_shader == null:
		_flash_shader = Shader.new()
		_flash_shader.code = FLASH_SHADER_CODE
	_flash_mat = ShaderMaterial.new()
	_flash_mat.shader = _flash_shader
	_flash = MeshInstance3D.new()
	_flash.mesh = QuadMesh.new()
	_flash.material_override = _flash_mat
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.position.z = 0.01 # just in front of the sprite
	_flash.visible = false
	_sprite.add_child(_flash)

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
	# Only in low detail mode (no real sun shadows then); Settings shows/hides it.
	shadow.add_to_group("blob_shadow")
	add_child(shadow)


## Use a look from PixelArt.character_look() / placeholder_look().
func set_look(look: Dictionary) -> void:
	_look = look
	pixel_size = look.pixel_size
	_sprite.pixel_size = pixel_size
	_height = look.frame_h * pixel_size
	_foot = look.foot_pad * pixel_size
	_state = ""
	_set_state("idle")


## Single still images (placeholder tayas): front = idle and happy, back = run.
func set_textures(front: Texture2D, back: Texture2D = null) -> void:
	var f := {"texture": front, "frames": 1, "fps": 0.0}
	var b := {"texture": back, "frames": 1, "fps": 0.0} if back else f
	set_look({"idle": f, "run": b, "happy": f, "frame_h": front.get_height(), "foot_pad": 0,
		"pixel_size": pixel_size})


## Turn to the camera and celebrate. duration < 0 keeps it up until stop_happy().
func play_happy(duration: float = 1.2) -> void:
	_happy_left = duration
	_set_state("happy")


func stop_happy() -> void:
	_happy_left = 0.0


func is_happy() -> bool:
	return _state == "happy"


func set_tint(color: Color) -> void:
	_tint = color
	_apply_colour()


## Half-transparent (e.g. while the camera aims over this character's shoulder).
func set_see_through(on: bool) -> void:
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED if on else SpriteBase3D.ALPHA_CUT_DISCARD
	_alpha = 0.35 if on else 1.0
	_apply_colour()


## Took a hit (wrong answer, tsinelas): squish flat and spring back, flashing red.
func hurt() -> void:
	_hurt_t = 0.0


func _hurting() -> bool:
	return _hurt_t < HURT_TIME


func _apply_colour() -> void:
	var col := _tint
	var flashing := false
	if _hurting():
		for f: Vector2 in HURT_FLASHES:
			if _hurt_t >= f.x and _hurt_t < f.y:
				flashing = true
	if flashing:
		col = HURT_RED
	col.a = _alpha
	if _sprite == null:
		return
	_sprite.modulate = col
	_flash.visible = flashing and _sprite.texture != null
	if _flash.visible:
		var frames := maxi(_sprite.hframes, 1)
		var tex := _sprite.texture
		(_flash.mesh as QuadMesh).size = Vector2(tex.get_width() / float(frames), tex.get_height()) * _sprite.pixel_size
		_flash_mat.set_shader_parameter("tex", tex)
		_flash_mat.set_shader_parameter("frames", float(frames))
		_flash_mat.set_shader_parameter("frame", float(_sprite.frame))
		_flash_mat.set_shader_parameter("col", Color(1.0, 0.12, 0.12, 0.7 * _alpha))


func _set_state(state: String) -> void:
	if state == _state or _look.is_empty():
		return
	_state = state
	_anim_t = 0.0
	var sheet: Dictionary = _look[state]
	_sprite.frame = 0
	_sprite.texture = sheet.texture
	_sprite.hframes = maxi(sheet.frames, 1)


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

	var facing_camera := true
	var cam := get_viewport().get_camera_3d()
	if cam and body:
		var to_cam := cam.global_position - global_position
		to_cam.y = 0.0
		if to_cam.length() > 0.01:
			# Manual billboard (turn around Y only) so the sprite can still tilt.
			global_rotation = Vector3(0.0, atan2(to_cam.x, to_cam.z), 0.0)
			var facing := -body.global_basis.z
			facing.y = 0.0
			facing_camera = facing.dot(to_cam) >= 0.0

	# Pick the sheet: happy wins while it lasts, then idle (front) or run (back).
	if _happy_left > 0.0:
		_happy_left = maxf(_happy_left - delta, 0.0)
	if _state == "happy" and _happy_left == 0.0:
		_state = "" # force a refresh below
	if _state != "happy":
		_set_state("idle" if facing_camera else "run")

	# Frame animation. Run loops while moving (faster when sprinting) and
	# rests on its first frame when standing still; idle and happy always loop.
	var sheet: Dictionary = _look[_state]
	if _state == "run":
		if _moving > 0.15:
			_anim_t += delta * sheet.fps * clampf(speed / 5.0, 0.6, 1.8)
		else:
			_anim_t = 0.0
	else:
		_anim_t += delta * sheet.fps
	_sprite.frame = int(_anim_t) % _sprite.hframes

	var hop := absf(sin(_phase)) * hop_height * _moving
	if _state == "happy":
		hop += absf(sin(_phase * 1.5)) * 0.12 # little celebration bounce
	var breathe := sin(_phase * 0.5) * 0.015 * (1.0 - _moving)
	# Hurt: flattened, then a damped wobble back to normal.
	var squish := 0.0
	if _hurting():
		_hurt_t += delta
		var k := clampf(_hurt_t / HURT_TIME, 0.0, 1.0)
		squish = HURT_SQUISH * exp(-4.5 * k) * cos(k * PI * 3.0) * (1.0 - k)
		_apply_colour()
		if not _hurting():
			_apply_colour() # back to normal colours
	var sy := 1.0 + breathe - squish
	_sprite.scale = Vector3(1.0 - breathe + squish, sy, 1.0)
	# Centre of the frame, lowered by the empty rows under the feet (the feet
	# stay on the ground while squished).
	_sprite.position = Vector3(0.0, (_height * 0.5 - _foot) * sy + hop, 0.0)
	_sprite.rotation.z = sin(_phase) * deg_to_rad(wobble_deg) * _moving
