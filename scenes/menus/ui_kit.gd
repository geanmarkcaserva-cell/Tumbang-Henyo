class_name UiKit
extends RefCounted
## Menu and HUD styling.
##
## Look: dark "glass" panels and buttons over the live 3D court, white type in
## the Hr Clunky title font, one warm accent colour for what matters (primary
## actions, the selected item, hover). Main-menu entries are plain text.
##   - button(): dark glass button. fill GOLD = primary action (solid accent).
##   - text_button(): no box at all, just text that lights up on hover.
##   - set_fill(): restyle a button; selected = chosen item (accent bar + text).
##   - box(): the glass panel used behind lists, editors and cards.

const LOGO := preload("res://art/ui/logo.png")
## Hand-drawn bubble font for titles, buttons and captions, always in white
## (Hr Clunky, rebuilt by art/source/fonts/make_title_font.py: letters enlarged
## and lined up on a common baseline, the wide gaps tightened, the hollow
## outlines filled in solid). It has letters and basic punctuation only, so
## digits and symbols fall back to a bolded default font. Descriptions keep the
## default font.
const TITLE_FONT_PATH := "res://art/ui/fonts/HrClunky-Tight.ttf"
static var _title_font: Font

# Kept so older calls still read: BLUE / CYAN = normal glass button, GOLD = primary.
const BLUE := Color(0.43, 0.73, 0.86)
const CYAN := Color(0.69, 0.91, 0.93)
const GOLD := Color(0.98, 0.74, 0.26)

const ACCENT := Color(1.0, 0.8, 0.34) ## warm sunset gold
const ACCENT_HOVER := Color(1.0, 0.87, 0.5)
const ACCENT_PRESSED := Color(0.88, 0.66, 0.22)
const GLASS := Color(0.03, 0.04, 0.07, 0.62)
const GLASS_HOVER := Color(0.05, 0.06, 0.1, 0.82)
const GLASS_PRESSED := Color(0.0, 0.0, 0.0, 0.9)
const HAIRLINE := Color(1, 1, 1, 0.1)
const TEXT := Color(1, 1, 1)
const TEXT_DIM := Color(1, 1, 1, 0.4)
const TEXT_ON_ACCENT := Color(0.12, 0.09, 0.05)
const TEXT_OUTLINE := Color(0.06, 0.07, 0.11)
const PANEL_DARK := GLASS
const CORNER := 12


static func title_font() -> Font:
	if _title_font == null:
		var f: FontFile = load(TITLE_FONT_PATH)
		if f.fallbacks.is_empty():
			# Digits and symbols: the default font, bolded to sit with the chunky letters.
			var bold := FontVariation.new()
			bold.base_font = ThemeDB.fallback_font
			bold.variation_embolden = 0.7
			f.fallbacks = [bold]
		_title_font = f
	return _title_font


## Use the title font on any Control (Label, Button, ...).
static func use_title_font(c: Control) -> void:
	c.add_theme_font_override("font", title_font())


## A label in the title font (headings, captions, big status text).
static func title(text: String, font_size: int = 56, color: Color = Color.WHITE, outline: int = 10) -> Label:
	var l := label(text, font_size, color, outline)
	use_title_font(l)
	return l


## Glass panel: dark see-through card with a hairline edge and a soft shadow.
## (The colour arguments are from the old flat boxes and are ignored.)
static func box(_fill: Color = GLASS, _border: Color = HAIRLINE, _border_w: int = 1, _radius: int = 16) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = GLASS
	s.border_color = HAIRLINE
	s.set_border_width_all(1)
	s.set_corner_radius_all(18)
	s.shadow_color = Color(0, 0, 0, 0.3)
	s.shadow_size = 18
	s.shadow_offset = Vector2(0, 6)
	s.content_margin_left = 34
	s.content_margin_right = 34
	s.content_margin_top = 26
	s.content_margin_bottom = 26
	return s


static func button(text: String, fill: Color = BLUE, font_size: int = 56, min_size: Vector2 = Vector2(520, 120)) -> Button:
	var b := Button.new()
	b.text = text
	# Slimmer than the old art buttons: same width, less height.
	b.custom_minimum_size = Vector2(min_size.x, roundf(min_size.y * 0.78))
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", int(font_size * 0.9))
	b.add_theme_constant_override("outline_size", 0)
	b.add_theme_constant_override("shadow_offset_x", 0)
	b.add_theme_constant_override("shadow_offset_y", 3)
	set_fill(b, fill, false)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	use_title_font(b)
	UiFx.hookup_button(b) # bouncy hover / press
	return b


## Just text: no box, lights up in the accent colour on hover (main menu).
static func text_button(text: String, font_size: int = 64) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	for key in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		b.add_theme_stylebox_override(key, StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	b.add_theme_color_override("font_hover_color", ACCENT)
	b.add_theme_color_override("font_pressed_color", ACCENT_PRESSED)
	b.add_theme_color_override("font_hover_pressed_color", ACCENT_PRESSED)
	b.add_theme_color_override("font_disabled_color", TEXT_DIM)
	b.add_theme_color_override("font_outline_color", TEXT_OUTLINE)
	b.add_theme_constant_override("outline_size", 10)
	b.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	b.add_theme_constant_override("shadow_offset_x", 0)
	b.add_theme_constant_override("shadow_offset_y", 5)
	use_title_font(b)
	UiFx.hookup_button(b)
	return b


## Restyle a button. GOLD = primary action (solid accent, dark text); anything
## else = glass. selected = the chosen theme / set / setting: accent bar on the
## left and accent text.
static func set_fill(b: Button, fill: Color, selected: bool) -> void:
	var primary := fill == GOLD and not selected
	if primary:
		b.add_theme_stylebox_override("normal", _flat(ACCENT, Color(0, 0, 0, 0)))
		b.add_theme_stylebox_override("hover", _flat(ACCENT_HOVER, Color(0, 0, 0, 0)))
		b.add_theme_stylebox_override("pressed", _flat(ACCENT_PRESSED, Color(0, 0, 0, 0), 0, 3))
		b.add_theme_stylebox_override("hover_pressed", _flat(ACCENT_PRESSED, Color(0, 0, 0, 0), 0, 3))
		b.add_theme_stylebox_override("disabled", _flat(Color(ACCENT, 0.3), Color(0, 0, 0, 0)))
		_font_colours(b, TEXT_ON_ACCENT, TEXT_ON_ACCENT, Color(TEXT_ON_ACCENT, 0.5))
		b.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	elif selected:
		b.add_theme_stylebox_override("normal", _flat(GLASS_HOVER, HAIRLINE, 8))
		b.add_theme_stylebox_override("hover", _flat(GLASS_HOVER, HAIRLINE, 8))
		b.add_theme_stylebox_override("pressed", _flat(GLASS_PRESSED, HAIRLINE, 8, 3))
		b.add_theme_stylebox_override("hover_pressed", _flat(GLASS_PRESSED, HAIRLINE, 8, 3))
		b.add_theme_stylebox_override("disabled", _flat(GLASS, HAIRLINE, 8))
		_font_colours(b, ACCENT, ACCENT_HOVER, TEXT_DIM)
		b.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.4))
	else:
		b.add_theme_stylebox_override("normal", _flat(GLASS, HAIRLINE))
		b.add_theme_stylebox_override("hover", _flat(GLASS_HOVER, HAIRLINE, 6))
		b.add_theme_stylebox_override("pressed", _flat(GLASS_PRESSED, HAIRLINE, 6, 3))
		b.add_theme_stylebox_override("hover_pressed", _flat(GLASS_PRESSED, HAIRLINE, 6, 3))
		b.add_theme_stylebox_override("disabled", _flat(Color(GLASS, 0.35), Color(HAIRLINE, 0.05)))
		_font_colours(b, TEXT, TEXT, TEXT_DIM)
		b.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.4))


static func _font_colours(b: Button, normal: Color, hover: Color, disabled: Color) -> void:
	b.add_theme_color_override("font_color", normal)
	b.add_theme_color_override("font_focus_color", normal)
	b.add_theme_color_override("font_hover_color", hover)
	b.add_theme_color_override("font_pressed_color", hover)
	b.add_theme_color_override("font_hover_pressed_color", hover)
	b.add_theme_color_override("font_disabled_color", disabled)


## A rounded flat box. accent_bar > 0 draws an accent stripe on the left edge;
## push_down nudges the label down (pressed look).
static func _flat(bg: Color, edge: Color, accent_bar: int = 0, push_down: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = edge
	s.set_border_width_all(1 if edge.a > 0.0 else 0)
	if accent_bar > 0:
		s.border_width_left = accent_bar
		s.border_color = ACCENT # the whole edge takes the accent; only the left is thick
		s.border_width_top = 0
		s.border_width_right = 0
		s.border_width_bottom = 0
	s.set_corner_radius_all(CORNER)
	s.content_margin_left = 30
	s.content_margin_right = 30
	s.content_margin_top = 6 + push_down
	s.content_margin_bottom = 10 - push_down
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


## A thin accent line under a heading.
static func accent_rule(width: float = 120.0) -> ColorRect:
	var r := ColorRect.new()
	r.color = ACCENT
	r.custom_minimum_size = Vector2(width, 5)
	r.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## The 1920x1080 area the menu layouts are drawn in, kept in the middle of the
## screen: on wider screens (21:9) or taller ones the extra space is split
## evenly on both sides instead of all piling up on the right. Lets clicks
## through to its children only.
static func full_rect() -> Control:
	var c := Control.new()
	c.anchor_left = 0.5
	c.anchor_right = 0.5
	c.anchor_top = 0.5
	c.anchor_bottom = 0.5
	c.offset_left = -UiFx.DESIGN.x * 0.5
	c.offset_right = UiFx.DESIGN.x * 0.5
	c.offset_top = -UiFx.DESIGN.y * 0.5
	c.offset_bottom = UiFx.DESIGN.y * 0.5
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
