class_name TouchLayoutEditor
extends CanvasLayer
## Settings > Touch buttons: move the on-screen joystick and buttons wherever
## suits your thumbs, and make them bigger or smaller. Shows the running
## controls (joystick, Jump, Sprint, Look back) or the throwing one (Throw);
## drag any of them. Done saves (Settings.set_touch_layout), Reset puts
## everything back. Works from the main menu and from the pause menu.

signal closed

var _tc: TouchControls
var _size: HSlider
var _tab_run: Button
var _tab_throw: Button


## Open the editor over everything.
static func open(tree: SceneTree) -> TouchLayoutEditor:
	var ed := TouchLayoutEditor.new()
	tree.root.add_child(ed)
	return ed


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP # nothing behind gets the clicks
	add_child(dim)

	_tc = TouchControls.new()
	_tc.editing = true
	_tc.layout = Settings.touch_layout.duplicate()
	_tc.scale_mult = Settings.touch_scale
	add_child(_tc)
	_tc.context = "run"

	# Bar along the top: what to do, which set, size, reset, done.
	var root := UiKit.full_rect()
	add_child(root)
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UiKit.box())
	bar.position = Vector2(160, 30)
	bar.custom_minimum_size = Vector2(1600, 0)
	root.add_child(bar)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	bar.add_child(v)
	var title := UiKit.title("Touch buttons", 56, Color.WHITE, 10)
	v.add_child(title)
	var hint := UiKit.label("Drag the joystick and buttons where your thumbs like them.", 28, Color(1, 1, 1, 0.8))
	v.add_child(hint)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	v.add_child(row)
	_tab_run = UiKit.button("Running", UiKit.BLUE, 30, Vector2(230, 84))
	_tab_run.pressed.connect(func(): _show_set("run"))
	row.add_child(_tab_run)
	_tab_throw = UiKit.button("Throwing", UiKit.BLUE, 30, Vector2(230, 84))
	_tab_throw.pressed.connect(func(): _show_set("throw"))
	row.add_child(_tab_throw)
	var size_l := UiKit.title("Size", 34, Color.WHITE, 6)
	size_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(size_l)
	_size = HSlider.new()
	_size.min_value = 0.7
	_size.max_value = 1.4
	_size.step = 0.05
	_size.value = _tc.scale_mult
	_size.custom_minimum_size = Vector2(300, 50)
	_size.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_size.value_changed.connect(func(k: float): _tc.set_editing_scale(k))
	row.add_child(_size)
	var reset := UiKit.button("Reset", UiKit.BLUE, 30, Vector2(200, 84))
	reset.pressed.connect(func():
		_tc.layout = {}
		_size.value = 1.0
		_tc.set_editing_scale(1.0))
	row.add_child(reset)
	var done := UiKit.button("Done", UiKit.GOLD, 34, Vector2(220, 84))
	done.pressed.connect(_done)
	row.add_child(done)
	_show_set("run")
	UiFx.pop_in(root)


func _show_set(ctx: String) -> void:
	_tc.context = ctx
	UiKit.set_fill(_tab_run, UiKit.BLUE, ctx == "run")
	UiKit.set_fill(_tab_throw, UiKit.BLUE, ctx == "throw")
	_tc.queue_redraw()


func _done() -> void:
	Settings.set_touch_layout(_tc.layout, _tc.scale_mult)
	Sfx.play("ui_equip")
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()
		queue_free() # Esc: leave without saving
