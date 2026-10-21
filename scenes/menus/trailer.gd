extends Control
## The trailer, played when the game opens (after the boot screen, before the
## main menu). It has its own soundtrack (the menu song, then the running song
## once the slipper flies). Skip with the arrow in the bottom left (or Esc /
## Enter / Space); either way it goes on to the main menu.

const VIDEO := "res://art/video/trailer.ogv"
const NEXT := "res://scenes/menus/main_menu.tscn"

var _player: VideoStreamPlayer
var _skip: Button
var _leaving := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Music.stop(0.4) # the trailer brings its own music
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# 16:9, letterboxed on screens of any other shape.
	var frame := AspectRatioContainer.new()
	frame.ratio = 16.0 / 9.0
	frame.stretch_mode = AspectRatioContainer.STRETCH_FIT
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(frame)
	_player = VideoStreamPlayer.new()
	_player.expand = true
	_player.stream = load(VIDEO)
	_player.finished.connect(_leave)
	frame.add_child(_player)
	_build_skip()
	_player.play()


func _build_skip() -> void:
	_skip = Button.new()
	_skip.focus_mode = Control.FOCUS_NONE
	_skip.anchor_left = 0.0
	_skip.anchor_right = 0.0
	_skip.anchor_top = 1.0
	_skip.anchor_bottom = 1.0
	_skip.offset_left = 36.0
	_skip.offset_right = 36.0 + 190.0
	_skip.offset_top = -36.0 - 76.0
	_skip.offset_bottom = -36.0
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0.45 if state == "normal" else 0.7)
		sb.border_color = Color(1, 1, 1, 0.35 if state == "normal" else 0.7)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(38)
		_skip.add_theme_stylebox_override(state, sb)
	_skip.pressed.connect(_leave)
	add_child(_skip)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	_skip.add_child(row)
	var label := UiKit.label("Skip", 30, Color.WHITE, 0)
	label.add_theme_font_override("font", UiKit.key_font())
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	var arrow := SkipArrow.new()
	arrow.custom_minimum_size = Vector2(40, 28)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(arrow)
	# Fades in a moment after the trailer starts.
	_skip.modulate.a = 0.0
	create_tween().tween_property(_skip, "modulate:a", 1.0, 0.4).set_delay(0.6)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_leave()


func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	Sfx.play("ui_click")
	create_tween().tween_property(_player, "volume_db", -40.0, 0.4)
	Transition.change_scene(GameManager.after_trailer if GameManager.after_trailer else NEXT)


## Two solid chevrons: >>
class SkipArrow extends Control:
	func _draw() -> void:
		var h := size.y
		var w := size.x * 0.5
		for i in 2:
			var x := i * w
			draw_colored_polygon(PackedVector2Array([Vector2(x, 0), Vector2(x + w, h * 0.5), Vector2(x, h)]), Color.WHITE)
