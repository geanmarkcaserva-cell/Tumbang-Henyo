class_name ParallaxBackdrop
extends Control
## The barangay skyline behind the loading screen, in layers that drift
## sideways at different speeds (far layers slowly, near layers faster) and
## lean a little toward the mouse or finger, so it feels deep.
##
## The art (art/loading/, 1920x1080 each) is scaled to cover any screen shape.
## Scrolling layers repeat as normal / mirrored copies so the seams always line up.

## Back to front: file, scroll speed (design px/s), how much it follows the pointer,
## start of its slide-in.
const LAYERS := [
	["sky", 0.0, 0.0, 0.0],
	["sun", 0.0, 6.0, 0.0],
	["clouds", 14.0, 10.0, 0.05],
	["trees", 22.0, 16.0, 0.12],
	["posts_back", 34.0, 22.0, 0.18],
	["houses", 52.0, 30.0, 0.24],
	["posts_front", 80.0, 44.0, 0.3],
]
const DIR := "res://art/loading/"
const ART := Vector2(1920, 1080)
const INTRO := 0.9 ## seconds for the layers to slide up into place

var _layers: Array = [] ## [{root: Control, copies: [TextureRect], speed, follow, delay}]
var _time := 0.0
var _scroll := 0.0
var _lean := Vector2.ZERO


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	set_meta("fx_skip", true)
	for l in LAYERS:
		var tex: Texture2D = load(DIR + l[0] + ".png")
		var root := Control.new()
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(root)
		var copies := []
		var count := 1 if l[1] == 0.0 else 4
		for i in count:
			var r := TextureRect.new()
			r.texture = tex
			r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			r.stretch_mode = TextureRect.STRETCH_SCALE
			r.flip_h = i % 2 == 1 # mirrored neighbour: the edges always match
			r.mouse_filter = Control.MOUSE_FILTER_IGNORE
			root.add_child(r)
			copies.append(r)
		_layers.append({"root": root, "copies": copies, "speed": l[1], "follow": l[2], "delay": l[3]})


func _process(delta: float) -> void:
	_time += delta
	_scroll += delta
	# Lean toward the pointer (mouse or last touch), eased.
	var vp := get_viewport_rect().size
	var p := get_viewport().get_mouse_position()
	var target := ((p / vp) - Vector2(0.5, 0.5)) * 2.0 if vp.x > 0 else Vector2.ZERO
	target = target.clamp(Vector2(-1, -1), Vector2(1, 1))
	_lean = _lean.lerp(target, minf(delta * 2.5, 1.0))
	_layout()


func _layout() -> void:
	var s := size
	var k := maxf(s.x / ART.x, s.y / ART.y) * 1.04 # cover the screen, a little spare for the lean
	var w := ART.x * k
	var h := ART.y * k
	var base := Vector2((s.x - w) * 0.5, (s.y - h) * 0.5)
	for l in _layers:
		# Slide up into place at the start, back layers first.
		var t := clampf((_time - l.delay) / INTRO, 0.0, 1.0)
		var ease := 1.0 - pow(1.0 - t, 3.0)
		var rise := (1.0 - ease) * 220.0 * k * (1.0 if l.speed > 0.0 else 0.0)
		var off: Vector2 = Vector2(-_lean.x, -_lean.y * 0.5) * float(l.follow) * k
		var y: float = base.y + rise + off.y
		if l.copies.size() == 1:
			var r: TextureRect = l.copies[0]
			r.position = Vector2(base.x + off.x, y)
			r.size = Vector2(w, h)
			continue
		var shift := fmod(_scroll * l.speed * k, w * 2.0) # one normal + one mirrored copy per period
		for i in l.copies.size():
			var r: TextureRect = l.copies[i]
			r.position = Vector2(base.x + off.x - shift + i * w, y)
			r.size = Vector2(w, h)
