class_name SettingsPanel
extends PanelContainer
## The settings card used by the main menu and the pause menu:
## Volume, Music, SFX sliders, Low detail and Fullscreen switches, Back.
## Everything applies right away and is saved by the Settings autoload.

signal back_pressed

const ON_COLOR := Color(1.0, 0.86, 0.35)

var _toggles := {}


func _init() -> void:
	add_theme_stylebox_override("panel", UiKit.box(UiKit.PANEL_DARK, Color(0.3, 0.3, 0.32), 10, 8))
	custom_minimum_size = Vector2(860, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 22)
	add_child(v)

	var title := UiKit.title("Settings", 76, Color.WHITE, 12)
	v.add_child(title)

	v.add_child(_slider_row("Volume", Settings.volume, Settings.set_volume))
	v.add_child(_slider_row("Music", Settings.music, Settings.set_music))
	v.add_child(_slider_row("SFX", Settings.sfx, Settings.set_sfx, true))
	v.add_child(_toggle_row("Low detail mode", "low", Settings.low_detail,
			func(on: bool): Settings.set_low_detail(on),
			"Fewer plants, no shadows, lower 3D resolution. Faster on phones."))
	if Settings.can_fullscreen():
		v.add_child(_toggle_row("Fullscreen", "full", Settings.fullscreen,
				func(on: bool): Settings.set_fullscreen(on)))

	var back := UiKit.button("< BACK", UiKit.BLUE, 40, Vector2(240, 96))
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(func(): back_pressed.emit())
	v.add_child(back)


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
		slider.drag_ended.connect(func(_changed: bool): Sfx.play("correct", -6.0))
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
	b.text = "ON" if on else "OFF"
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
