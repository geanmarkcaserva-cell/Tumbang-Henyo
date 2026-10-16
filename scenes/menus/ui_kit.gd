class_name UiKit
extends RefCounted
## Placeholder menu styling based on the menu mockups: rounded light-blue
## buttons with a dark-blue border and white outlined text. Swap for the
## final art once the UI PNGs are exported.

const BLUE := Color(0.43, 0.73, 0.86)
const CYAN := Color(0.69, 0.91, 0.93)
const GOLD := Color(0.98, 0.74, 0.26)
const BORDER := Color(0.24, 0.5, 0.67)
const SELECTED_BORDER := Color(1.0, 0.86, 0.3)
const TEXT_OUTLINE := Color(0.08, 0.14, 0.22)
const PANEL_DARK := Color(0.2, 0.2, 0.22, 0.8)


static func box(fill: Color, border: Color = BORDER, border_w: int = 6, radius: int = 18) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 28
	s.content_margin_right = 28
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	return s


static func button(text: String, fill: Color = BLUE, font_size: int = 56, min_size: Vector2 = Vector2(520, 120)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(key, Color.WHITE)
	b.add_theme_color_override("font_outline_color", TEXT_OUTLINE)
	b.add_theme_constant_override("outline_size", 10)
	set_fill(b, fill, false)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


## Recolour a button, optionally with the gold "selected" border.
static func set_fill(b: Button, fill: Color, selected: bool) -> void:
	var border := SELECTED_BORDER if selected else BORDER
	var w := 10 if selected else 6
	b.add_theme_stylebox_override("normal", box(fill, border, w))
	b.add_theme_stylebox_override("hover", box(fill.lightened(0.12), border, w))
	b.add_theme_stylebox_override("pressed", box(fill.darkened(0.12), border, w))
	b.add_theme_stylebox_override("disabled", box(fill.darkened(0.35), border, w))


static func label(text: String, font_size: int = 40, color: Color = Color.WHITE, outline: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_color_override("font_outline_color", TEXT_OUTLINE)
		l.add_theme_constant_override("outline_size", outline)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A full-screen container that lets clicks through to its children only.
static func full_rect() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
