class_name NameTag
extends Node3D
## A small floating name box over someone's head: a dark rounded pill with a
## gold dot and the name in white. Always faces the camera.

const FONT_SIZE := 44
const PX := 0.0042 ## metres per pixel
const PAD := Vector2(26, 13)
const DOT := 12
const FILL := Color(0.05, 0.06, 0.09, 0.8)
const EDGE := Color(1, 1, 1, 0.14)

var text := ""
var accent := Color(1.0, 0.8, 0.34)
var max_distance := 28.0 ## hidden beyond this, so the streets don't fill with labels

static var _pills := {}


func _ready() -> void:
	var font := UiKit.key_font()
	var text_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var size := Vector2i(int(text_w + PAD.x * 2.0 + DOT + 12), int(FONT_SIZE + PAD.y * 2.0))
	var bg := Sprite3D.new()
	bg.texture = _pill(size, accent)
	bg.pixel_size = PX
	bg.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bg.shaded = false
	bg.render_priority = 0
	bg.visibility_range_end = max_distance
	add_child(bg)
	var label := Label3D.new()
	label.text = text
	label.font = font
	label.font_size = FONT_SIZE
	label.pixel_size = PX
	label.outline_size = 0
	label.modulate = Color.WHITE
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.render_priority = 1
	label.position.x = 0.0
	label.offset = Vector2((DOT + 12) * 0.5, 0.0)
	label.visibility_range_end = max_distance
	add_child(label)


## Rounded pill (cached by size and colour).
static func _pill(size: Vector2i, dot_color: Color) -> Texture2D:
	var key := "%d_%d_%s" % [size.x, size.y, dot_color.to_html()]
	if _pills.has(key):
		return _pills[key]
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var r := size.y * 0.5
	var dot_c := Vector2(PAD.x + DOT * 0.5, size.y * 0.5)
	for y in size.y:
		for x in size.x:
			var p := Vector2(x + 0.5, y + 0.5)
			var cx := clampf(p.x, r, size.x - r)
			var d := p.distance_to(Vector2(cx, r)) # distance from the pill's spine
			if d > r:
				continue
			var c := FILL
			if d > r - 2.0:
				c = EDGE.blend(Color(FILL, FILL.a)) # hairline edge
				c.a = maxf(FILL.a, 0.85)
			if p.distance_to(dot_c) <= DOT * 0.5:
				c = dot_color
			c.a *= clampf(r - d, 0.0, 1.0) # soft outer edge
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	_pills[key] = tex
	return tex
