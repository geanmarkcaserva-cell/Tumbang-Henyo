class_name SettingsPanel
extends PanelContainer
## The settings card used by the main menu and the pause menu:
## Volume, Music, SFX sliders, Low detail and Fullscreen switches, Back,
## a Controls page to rebind keys (press a row, then the new key), and Touch
## buttons > Arrange to move and resize the on-screen controls.
## Everything applies right away and is saved by the Settings autoload.

signal back_pressed

const ON_COLOR := Color(1.0, 0.86, 0.35)

var _toggles := {}
var _main: VBoxContainer
var _controls: VBoxContainer
var _key_buttons := {} ## action -> Button
var _waiting := "" ## action waiting for its new key
var _controls_note: Label


func _init() -> void:
	add_theme_stylebox_override("panel", UiKit.box(UiKit.PANEL_DARK, Color(0.3, 0.3, 0.32), 10, 8))
	custom_minimum_size = Vector2(860, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 22)
	add_child(v)
	_main = v
	_build_controls()

	var title := UiKit.title("Settings", 76, Color.WHITE, 12)
	v.add_child(title)
	v.add_child(UiKit.accent_rule())

	v.add_child(_slider_row("Volume", Settings.volume, Settings.set_volume))
	v.add_child(_slider_row("Music", Settings.music, Settings.set_music))
	v.add_child(_slider_row("SFX", Settings.sfx, Settings.set_sfx, true))
	v.add_child(_toggle_row("Low detail mode", "low", Settings.low_detail,
			func(on: bool): Settings.set_low_detail(on),
			"Fewer plants, no shadows, lower 3D resolution. Faster on phones."))
	if Settings.can_fullscreen():
		v.add_child(_toggle_row("Fullscreen", "full", Settings.fullscreen,
				func(on: bool): Settings.set_fullscreen(on)))
	v.add_child(_toggle_row("Touch controls", "touch", Settings.touch_controls,
			func(on: bool): Settings.set_touch_controls(on),
			"On-screen joystick and buttons for phones and touchscreens."))

	if not OS.has_feature("mobile"): # keyboard and mouse keys
		var keys := HBoxContainer.new()
		keys.add_theme_constant_override("separation", 24)
		var kl := UiKit.title("Controls", 42, Color.WHITE, 8)
		kl.custom_minimum_size = Vector2(450, 0)
		keys.add_child(kl)
		var remap := UiKit.button("Remap keys", UiKit.BLUE, 32, Vector2(300, 76))
		remap.pressed.connect(func(): _show_controls(true))
		keys.add_child(remap)
		v.add_child(keys)

	# Touch buttons: move and resize the on-screen controls (phones, or PC with touch on).
	var touch_row := HBoxContainer.new()
	touch_row.add_theme_constant_override("separation", 24)
	var tl := UiKit.title("Touch buttons", 42, Color.WHITE, 8)
	tl.custom_minimum_size = Vector2(450, 0)
	touch_row.add_child(tl)
	var arrange := UiKit.button("Arrange", UiKit.BLUE, 32, Vector2(300, 76))
	arrange.pressed.connect(func(): TouchLayoutEditor.open(get_tree()))
	touch_row.add_child(arrange)
	v.add_child(touch_row)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 20)
	v.add_child(bottom)
	var back := UiKit.button("Back", UiKit.BLUE, 40, Vector2(240, 96))
	back.pressed.connect(func(): back_pressed.emit())
	bottom.add_child(back)
	# Plays the guided first round again on the next game.
	var replay := UiKit.button("Replay tutorial", UiKit.BLUE, 40, Vector2(400, 96))
	replay.disabled = not Economy.tutorial_done
	replay.pressed.connect(func():
		Economy.tutorial_done = false
		Economy.tips_seen.clear()
		Economy.save_profile()
		replay.text = "Plays next game"
		replay.disabled = true
		UiFx.bounce(replay, 1.1))
	bottom.add_child(replay)


# --- Controls page ---------------------------------------------------------------

func _build_controls() -> void:
	_controls = VBoxContainer.new()
	_controls.add_theme_constant_override("separation", 16)
	_controls.visible = false
	add_child(_controls)
	_controls.add_child(UiKit.title("Controls", 76, Color.WHITE, 12))
	_controls.add_child(UiKit.accent_rule())
	_controls_note = UiKit.label("Click a key, then press the new key (Esc cancels).", 26, Color(1, 1, 1, 0.65))
	_controls.add_child(_controls_note)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(800, 610) # all twelve rows fit without scrolling
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_controls.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)
	for a in Settings.REMAPPABLE:
		var l := UiKit.title(a[1], 36, Color.WHITE, 8)
		l.custom_minimum_size = Vector2(430, 0)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(l)
		var b := UiKit.button("", UiKit.BLUE, 30, Vector2(300, 58))
		b.pressed.connect(_start_rebind.bind(a[0]))
		grid.add_child(b)
		_key_buttons[a[0]] = b
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 20)
	_controls.add_child(bottom)
	var back := UiKit.button("Back", UiKit.BLUE, 40, Vector2(240, 96))
	back.pressed.connect(func(): _show_controls(false))
	bottom.add_child(back)
	var reset := UiKit.button("Reset to defaults", UiKit.BLUE, 36, Vector2(420, 96))
	reset.pressed.connect(func():
		_waiting = ""
		Settings.reset_keys()
		_refresh_keys()
		_controls_note.text = "Back to the default keys.")
	bottom.add_child(reset)
	_refresh_keys()


func _show_controls(on: bool) -> void:
	_waiting = ""
	_main.visible = not on
	_controls.visible = on
	_refresh_keys()
	reset_size()
	UiFx.pop_in(_controls if on else _main, 0.0)


func _refresh_keys() -> void:
	for action in _key_buttons:
		var b: Button = _key_buttons[action]
		b.text = Settings.key_name(action)
		UiKit.set_fill(b, UiKit.BLUE, false)


func _start_rebind(action: String) -> void:
	_refresh_keys()
	_waiting = action
	var b: Button = _key_buttons[action]
	b.text = "Press a key..."
	UiKit.set_fill(b, UiKit.GOLD, false)
	_controls_note.text = "Press the new key or mouse button. Esc cancels."


## While waiting for a key: the next key or mouse button becomes the binding.
func _input(event: InputEvent) -> void:
	if _waiting == "" or not is_visible_in_tree():
		return
	var new_event: InputEvent = null
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_waiting = ""
			_refresh_keys()
			_controls_note.text = "Cancelled."
			get_viewport().set_input_as_handled()
			return
		var k := InputEventKey.new()
		k.physical_keycode = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		new_event = k
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2]:
		var m := InputEventMouseButton.new()
		m.button_index = event.button_index
		new_event = m
	if new_event == null:
		return
	get_viewport().set_input_as_handled()
	var action := _waiting
	_waiting = ""
	var swapped := Settings.rebind(action, new_event)
	_refresh_keys()
	UiFx.bounce(_key_buttons[action], 1.12)
	Sfx.play("ui_equip")
	if swapped != "":
		_controls_note.text = "That key was on %s, so they swapped." % _label_of(swapped)
	else:
		_controls_note.text = "Saved."


func _label_of(action: String) -> String:
	for a in Settings.REMAPPABLE:
		if a[0] == action:
			return a[1]
	return action


## Refresh the switches (e.g. fullscreen changed with the keyboard).
func refresh() -> void:
	if _toggles.has("full"):
		_set_toggle(_toggles.full, Settings.fullscreen)
	_set_toggle(_toggles.low, Settings.low_detail)


func _slider_row(text: String, value: float, setter: Callable, preview_sfx: bool = false) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	var name_label := UiKit.title(text, 42, Color.WHITE, 8)
	name_label.custom_minimum_size = Vector2(250, 0)
	row.add_child(name_label)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.value = value * 100.0
	slider.custom_minimum_size = Vector2(420, 48)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style_slider(slider)
	row.add_child(slider)
	var pct := UiKit.label("%d%%" % int(value * 100.0), 34, ON_COLOR, 6)
	pct.custom_minimum_size = Vector2(100, 0)
	row.add_child(pct)
	slider.value_changed.connect(func(x: float):
		pct.text = "%d%%" % int(x)
		setter.call(x / 100.0))
	if preview_sfx:
		slider.drag_ended.connect(func(_changed: bool): Sfx.play("coin"))
	return row


func _toggle_row(text: String, key: String, on: bool, setter: Callable, hint: String = "") -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	box.add_child(row)
	var name_label := UiKit.title(text, 42, Color.WHITE, 8)
	name_label.custom_minimum_size = Vector2(450, 0)
	row.add_child(name_label)
	var b := UiKit.button("", UiKit.BLUE, 34, Vector2(180, 76))
	b.pressed.connect(func():
		var now: bool = not b.get_meta("on")
		_set_toggle(b, now)
		UiFx.bounce(b, 1.12)
		setter.call(now))
	row.add_child(b)
	_toggles[key] = b
	_set_toggle(b, on)
	if hint != "":
		box.add_child(UiKit.label(hint, 22, Color(1, 1, 1, 0.6)))
	return box


func _set_toggle(b: Button, on: bool) -> void:
	b.set_meta("on", on)
	b.text = "On" if on else "Off"
	UiKit.set_fill(b, UiKit.GOLD if on else UiKit.BLUE, false)


func _style_slider(s: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.18)
	track.set_corner_radius_all(8)
	track.content_margin_top = 7
	track.content_margin_bottom = 7
	var fill := StyleBoxFlat.new()
	fill.bg_color = ON_COLOR
	fill.set_corner_radius_all(8)
	fill.content_margin_top = 7
	fill.content_margin_bottom = 7
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	var knob := _knob(36, Color.WHITE)
	s.add_theme_icon_override("grabber", knob)
	s.add_theme_icon_override("grabber_highlight", _knob(40, Color(1.0, 0.95, 0.8)))


## A round slider knob with a dark outline.
static func _knob(d: int, fill: Color) -> Texture2D:
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var c := Vector2(d, d) * 0.5
	for y in d:
		for x in d:
			var r := Vector2(x + 0.5, y + 0.5).distance_to(c)
			if r <= d * 0.5 - 0.5:
				img.set_pixel(x, y, fill if r < d * 0.5 - 4.0 else UiKit.TEXT_OUTLINE)
	return ImageTexture.create_from_image(img)
