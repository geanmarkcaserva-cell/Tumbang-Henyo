class_name UiKit
extends RefCounted
## Menu styling: buttons use the hand-drawn button art from art/ui (made from
## art/assets UI/Button icon.png, plus cyan and gold recolours), with white
## outlined text. Panels are still flat boxes.

const BUTTON_BLUE := preload("res://art/ui/button_blue.png")
const BUTTON_CYAN := preload("res://art/ui/button_cyan.png")
const BUTTON_GOLD := preload("res://art/ui/button_gold.png")
const LOGO := preload("res://art/ui/logo.png")
## Size of the button art's frame (border + bevel) in pixels; the middle stretches.
const BUTTON_SLICE := 20

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
	UiFx.hookup_button(b) # bouncy hover / press
	return b


## Recolour a button: BLUE, CYAN or GOLD art. Selected buttons (the chosen
## theme or custom set) turn gold.
static func set_fill(b: Button, fill: Color, selected: bool) -> void:
	var tex: Texture2D = BUTTON_BLUE
	if selected or fill == GOLD:
		tex = BUTTON_GOLD
	elif fill == CYAN:
		tex = BUTTON_CYAN
	b.add_theme_stylebox_override("normal", button_box(tex, Color.WHITE))
	b.add_theme_stylebox_override("hover", button_box(tex, Color(1.12, 1.12, 1.12)))
	b.add_theme_stylebox_override("pressed", button_box(tex, Color(0.86, 0.86, 0.86), 4))
	b.add_theme_stylebox_override("disabled", button_box(tex, Color(0.55, 0.55, 0.6)))


## 9-slice stylebox from the button art. push_down moves the label down a
## little (pressed look).
static func button_box(tex: Texture2D, tint: Color, push_down: int = 0) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = tex
	s.texture_margin_left = BUTTON_SLICE
	s.texture_margin_right = BUTTON_SLICE
	s.texture_margin_top = BUTTON_SLICE
	s.texture_margin_bottom = BUTTON_SLICE
	s.modulate_color = tint
	s.content_margin_left = 28
	s.content_margin_right = 28
	s.content_margin_top = 8 + push_down
	s.content_margin_bottom = 16 - push_down
	return s


## The game logo (art/ui/logo.png), scaled to the given width.
static func logo(width: float) -> TextureRect:
	var t := TextureRect.new()
	t.texture = LOGO
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	t.size = Vector2(width, width * LOGO.get_height() / LOGO.get_width())
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


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
