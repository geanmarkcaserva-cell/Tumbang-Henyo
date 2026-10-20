class_name AvatarCropper
extends Control
## Change picture > Crop: frame your own profile picture. The picture sits
## under a round window the size of the badge; drag it around and zoom
## (mouse wheel, the slider, or + / -) until the circle shows what you want.
## Emits `saved` with the crop as [x, y, side] fractions of the picture (see
## Avatars.crop_rect), or `cancelled`.

signal saved(crop: Array)
signal cancelled

const VIEW := 620.0 ## the square work area
const HOLE := 500.0 ## the round window (= the badge)
const MAX_ZOOM := 8.0 ## at most this many times bigger than "whole picture fits"

var _src: Image
var _tex: ImageTexture
var _auto: Rect2i
var _area: Control
var _zoom: HSlider
var _scale := 1.0 ## screen pixels per picture pixel
var _pos := Vector2.ZERO ## picture's top-left inside the work area
var _fit := 1.0 ## scale at which the whole picture fits the window
var _dragging := false


## `src`: the whole picture; `start`: the square to begin with (the current
## crop, or the automatic one); `auto`: what Reset goes back to.
func setup(src: Image, start: Rect2i, auto: Rect2i) -> void:
	_src = src
	_auto = auto
	_tex = ImageTexture.create_from_image(src)
	_fit = HOLE / maxf(src.get_width(), src.get_height())
	_show_rect(start)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.position = Vector2(-1500, -1000)
	dim.size = UiFx.DESIGN + Vector2(3000, 2000)
	add_child(dim)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiKit.box())
	card.position = Vector2(560, 50)
	add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	card.add_child(v)
	v.add_child(UiKit.title("Crop picture", 52, Color.WHITE, 10))
	var hint := UiKit.label("Drag to move it, scroll or use the slider to zoom.", 26, Color(1, 1, 1, 0.75))
	v.add_child(hint)
	_area = Control.new()
	_area.custom_minimum_size = Vector2(VIEW, VIEW)
	_area.clip_contents = true
	_area.mouse_filter = Control.MOUSE_FILTER_STOP
	_area.draw.connect(_draw_area)
	_area.gui_input.connect(_area_input)
	v.add_child(_area)
	var zrow := HBoxContainer.new()
	zrow.add_theme_constant_override("separation", 12)
	v.add_child(zrow)
	var minus := UiKit.button("-", UiKit.BLUE, 40, Vector2(70, 64))
	minus.pressed.connect(func(): _zoom.value -= 0.25)
	zrow.add_child(minus)
	_zoom = HSlider.new()
	_zoom.min_value = 0.5
	_zoom.max_value = MAX_ZOOM
	_zoom.step = 0.01
	_zoom.custom_minimum_size = Vector2(420, 50)
	_zoom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_zoom.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_zoom.value_changed.connect(func(z: float): _set_scale(_fit * z))
	zrow.add_child(_zoom)
	var plus := UiKit.button("+", UiKit.BLUE, 40, Vector2(70, 64))
	plus.pressed.connect(func(): _zoom.value += 0.25)
	zrow.add_child(plus)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	v.add_child(row)
	var reset := UiKit.button("Reset", UiKit.BLUE, 34, Vector2(190, 90))
	reset.pressed.connect(func(): _show_rect(_auto))
	row.add_child(reset)
	var cancel := UiKit.button("Cancel", UiKit.BLUE, 34, Vector2(190, 90))
	cancel.pressed.connect(func():
		cancelled.emit()
		queue_free())
	row.add_child(cancel)
	var save := UiKit.button("Save", UiKit.GOLD, 38, Vector2(220, 90))
	save.pressed.connect(func():
		saved.emit(Avatars.crop_of(_src, _current_rect()))
		queue_free())
	row.add_child(save)
	UiFx.pop(card, 0.0, 0.8, 0.35)


## Frame `r` (picture pixels) exactly in the round window.
func _show_rect(r: Rect2i) -> void:
	_scale = HOLE / maxf(r.size.x, 1.0)
	var hole_tl := Vector2(VIEW - HOLE, VIEW - HOLE) * 0.5
	_pos = hole_tl - Vector2(r.position) * _scale
	if _zoom:
		_zoom.set_value_no_signal(_scale / _fit)
	if _area:
		_area.queue_redraw()


## Zoom about the middle of the window.
func _set_scale(s: float) -> void:
	var mid := Vector2(VIEW, VIEW) * 0.5
	var pic_mid := (mid - _pos) / _scale
	_scale = clampf(s, _fit * 0.5, _fit * MAX_ZOOM)
	_pos = mid - pic_mid * _scale
	_area.queue_redraw()


## The square of the picture inside the round window right now.
func _current_rect() -> Rect2i:
	var hole_tl := Vector2(VIEW - HOLE, VIEW - HOLE) * 0.5
	var tl := (hole_tl - _pos) / _scale
	var side := HOLE / _scale
	return Rect2i(Vector2i(roundi(tl.x), roundi(tl.y)), Vector2i(maxi(roundi(side), 1), maxi(roundi(side), 1)))


func _area_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom.value += 0.2
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom.value -= 0.2
	elif event is InputEventMouseMotion and _dragging:
		_pos += (event as InputEventMouseMotion).relative
		_area.queue_redraw()
	elif event is InputEventScreenDrag:
		_pos += (event as InputEventScreenDrag).relative
		_area.queue_redraw()


func _draw_area() -> void:
	if _tex == null:
		return
	_area.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_area.draw_rect(Rect2(Vector2.ZERO, Vector2(VIEW, VIEW)), Color(0.12, 0.13, 0.18))
	_area.draw_texture_rect(_tex, Rect2(_pos, Vector2(_src.get_width(), _src.get_height()) * _scale), false)
	# Darken everything outside the round window, then outline it.
	var mid := Vector2(VIEW, VIEW) * 0.5
	var r := HOLE * 0.5
	var band := VIEW
	_area.draw_arc(mid, r + band * 0.5, 0.0, TAU, 96, Color(0, 0, 0, 0.6), band)
	_area.draw_arc(mid, r, 0.0, TAU, 96, Color.WHITE, 4.0, true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		cancelled.emit()
		queue_free()
