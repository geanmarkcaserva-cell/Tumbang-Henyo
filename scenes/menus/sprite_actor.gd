class_name SpriteActor
extends Control
## A character's own animation sheets (idle / run / happy, see
## PixelArt.character_look) drawn in the UI: tutorial actors, the helper
## badge on the custom quiz screen and the speaker on the coach card.
##
## The feet are at this control's origin, so move it like a person standing
## on the ground: position = where the feet are. It draws outside its own
## (zero) size, and never takes mouse input.

## On-screen height, in pixels, of a full-height character (PixelArt.MAX_HEIGHT).
@export var height := 200.0
## Mirror left/right (the front sheets face the viewer; use it to turn around).
var flip := false
var state := "idle"
var look: Dictionary = {}

var _t := 0.0
var _hold := 0.0 ## seconds of happy left before going back to idle


## A character from the catalog by id (Economy.CHARACTERS).
static func of(character_id: String, h: float = 200.0) -> SpriteActor:
	var a := SpriteActor.new()
	a.height = h
	a.set_character(character_id)
	return a


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST # crisp pixels


func set_character(character_id: String) -> void:
	look = PixelArt.character_look(Economy.find_item("character", character_id))
	queue_redraw()


## Switch sheet ("idle", "run", "happy"); restarts the animation on a change.
func play(new_state: String) -> void:
	_hold = 0.0
	if new_state != state:
		state = new_state
		_t = 0.0
		queue_redraw()


## Cheer for a moment, then back to idle.
func cheer(seconds: float = 1.2) -> void:
	play("happy")
	_hold = seconds


func _process(delta: float) -> void:
	_t += delta
	if _hold > 0.0:
		_hold -= delta
		if _hold <= 0.0:
			play("idle")
	queue_redraw()


func _draw() -> void:
	if look.is_empty() or not look.has(state):
		return
	var sheet: Dictionary = look[state]
	var tex: Texture2D = sheet.texture
	if tex == null:
		return
	var frames: int = maxi(int(sheet.frames), 1)
	var fw := float(tex.get_width()) / frames
	var fh := float(tex.get_height())
	var f := 0
	if float(sheet.fps) > 0.0:
		f = int(_t * float(sheet.fps)) % frames
	# Screen pixels per art pixel: same scale the 3D sprites use, so every
	# character keeps its size relative to the others.
	var k: float = height / PixelArt.MAX_HEIGHT * float(look.pixel_size)
	var foot: float = float(look.foot_pad) * k
	var dst := Rect2(-fw * k * 0.5, -fh * k + foot, fw * k, fh * k)
	if flip:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1, 1))
	draw_texture_rect_region(tex, dst, Rect2(f * fw, 0.0, fw, fh))
	if flip:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
