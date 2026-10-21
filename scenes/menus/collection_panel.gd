class_name CollectionPanel
extends Control
## Main menu -> Collection, in three tabs:
## - Hidden items: the five easter eggs. Found ones turn slowly on a little
##   stand with their name and story; missing ones are a dark "?" with a hint
##   of which round they show up in. Finding all five opens the secret rounds.
## - Characters and Tsinelas: everything in the shop, yours in full colour,
##   the rest as dark silhouettes with what it takes to get them.
## Tap any card for its page: a big picture, the name and the full story.

signal back_pressed

var _count: Label
var _row: HBoxContainer
var _footer: Label
var _cards: Array = []
var _grid: GridContainer
var _sub: Label
var _tab := "items"
var _tabs := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = UiFx.DESIGN
	var card := PanelContainer.new()
	card.position = Vector2(110, 90)
	card.custom_minimum_size = Vector2(1700, 900)
	card.add_theme_stylebox_override("panel", UiKit.box())
	add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	card.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var title := UiKit.title("Collection", 72, Color.WHITE, 14)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_count = UiKit.title("", 44, UiKit.ACCENT, 8)
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_count)
	v.add_child(UiKit.accent_rule())
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 14)
	v.add_child(tabs)
	for t in [["items", "Hidden items"], ["characters", "Characters"], ["slippers", "Slippers"]]:
		var b := UiKit.button(t[1], UiKit.BLUE, 30, Vector2(260, 76))
		var id: String = t[0]
		b.pressed.connect(func():
			_tab = id
			refresh())
		tabs.add_child(b)
		_tabs[id] = b
	_sub = UiKit.label("", 28, Color(1, 1, 1, 0.75))
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub.custom_minimum_size = Vector2(1620, 0)
	v.add_child(_sub)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 18)
	_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_row)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 18)
	_grid.add_theme_constant_override("v_separation", 18)
	_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_grid)
	_footer = UiKit.title("", 34, UiKit.ACCENT, 8)
	_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_footer.custom_minimum_size = Vector2(1620, 0)
	v.add_child(_footer)
	var back := UiKit.button("Back", UiKit.BLUE, 44, Vector2(250, 110))
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(func(): back_pressed.emit())
	v.add_child(back)
	refresh()


func refresh() -> void:
	if _row == null:
		return
	_close_detail()
	for c in _row.get_children() + _grid.get_children():
		c.get_parent().remove_child(c)
		c.queue_free()
	for id in _tabs:
		UiKit.set_fill(_tabs[id], UiKit.BLUE, id == _tab)
	_row.visible = _tab == "items"
	_grid.visible = _tab != "items"
	if _tab == "characters":
		_fill_shop(Economy.CHARACTERS, true)
		return
	if _tab == "slippers":
		_fill_shop(Economy.SLIPPERS, false)
		return
	_sub.text = "Hidden things turn up around the neighborhood in some rounds - often up on a roof. Grab them before you reach the finish!"
	var got := 0
	for it in EasterEggs.ITEMS:
		var found := Economy.has_collected(it.id)
		if found:
			got += 1
		_row.add_child(_item_card(it, found))
	_count.text = "%d / %d" % [got, EasterEggs.ITEMS.size()]
	if got >= EasterEggs.ITEMS.size():
		_footer.text = "All found! After you beat Mama, your friends will ask you to keep playing until 7:00 PM..."
		_footer.add_theme_color_override("font_color", UiKit.ACCENT)
	else:
		_footer.text = "Find all %d to unlock a secret..." % EasterEggs.ITEMS.size()
		_footer.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))


## Characters or tsinelas: owned ones in colour, the rest as silhouettes.
func _fill_shop(list: Array, characters: bool) -> void:
	var got := 0
	for it in list:
		var mine := Economy.owns(it.id)
		if mine:
			got += 1
		_grid.add_child(_shop_card(it, mine, characters))
	_count.text = "%d / %d" % [got, list.size()]
	_sub.text = ("Everyone in the barkada you can play as. Buy them in character select." if characters
		else "Every pair of slippers you can throw. Buy them in weapon select.")
	if got >= list.size():
		_footer.text = "You have them all!"
		_footer.add_theme_color_override("font_color", UiKit.ACCENT)
	else:
		_footer.text = "%d still to get..." % (list.size() - got)
		_footer.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))


func _shop_card(it: Dictionary, mine: bool, character: bool) -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(395, 250)
	var s := StyleBoxFlat.new()
	s.bg_color = Color(1, 1, 1, 0.07) if mine else Color(0, 0, 0, 0.25)
	s.border_color = Color(UiKit.ACCENT, 0.7) if mine else Color(1, 1, 1, 0.08)
	s.set_border_width_all(2)
	s.set_corner_radius_all(20)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", s)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	var pic := TextureRect.new()
	pic.custom_minimum_size = Vector2(370, 150)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if character:
		# The first front frame of the idle sheet.
		var sheet: Dictionary = PixelArt.character_look(it).idle
		var tex: Texture2D = sheet.texture
		var at := AtlasTexture.new()
		at.atlas = tex
		var fw := tex.get_width() / maxi(int(sheet.frames), 1)
		at.region = Rect2(0, 0, fw, tex.get_height())
		pic.texture = at
	else:
		pic.texture = PixelArt.slipper_texture(it)
	if not mine:
		pic.modulate = Color(0, 0, 0, 0.6) # silhouette
	v.add_child(pic)
	var name_l := UiKit.title(it.name if mine else "???", 34, Color.WHITE if mine else Color(1, 1, 1, 0.6), 8)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name_l)
	var info := ""
	if mine:
		info = "Owned" if character else ("Wind resistance: Immune" if float(it.get("wind_resist", 0.0)) >= 1.0
				else "Wind resistance: %d%%" % roundi(float(it.get("wind_resist", 0.0)) * 100.0))
	elif not Economy.requirement_met(it.id):
		info = Economy.requirement_text(it.id)
	else:
		info = "%d caps" % it.price
	var info_l := UiKit.label(info, 24, UiKit.ACCENT if mine else Color(1, 1, 1, 0.5))
	info_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(info_l)
	_tappable(p, func(): _open_detail("character" if character else "slipper", it, mine))
	return p


func _item_card(it: Dictionary, found: bool) -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(318, 560)
	var s := StyleBoxFlat.new()
	s.bg_color = Color(1, 1, 1, 0.07) if found else Color(0, 0, 0, 0.25)
	s.border_color = Color(it.glow, 0.7) if found else Color(1, 1, 1, 0.08)
	s.set_border_width_all(2)
	s.set_corner_radius_all(20)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 16
	s.content_margin_bottom = 16
	p.add_theme_stylebox_override("panel", s)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	if found:
		v.add_child(_turntable(it))
	else:
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(286, 250)
		v.add_child(holder)
		var icon := TextureRect.new()
		icon.texture = EasterEggs.icon(it.id, 10)
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		icon.modulate = Color(0, 0, 0, 0.55) # silhouette
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		holder.add_child(icon)
		var q := UiKit.title("?", 120, Color(1, 1, 1, 0.75), 12)
		q.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		holder.add_child(q)
	var name_l := UiKit.title(it.name if found else "???", 38, Color.WHITE if found else Color(1, 1, 1, 0.6), 8)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_l.custom_minimum_size = Vector2(286, 0)
	v.add_child(name_l)
	var desc := UiKit.label(it.desc if found else "Shows up in round %d." % it.round, 24,
			Color(1, 1, 1, 0.78) if found else Color(1, 1, 1, 0.45))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(286, 0)
	v.add_child(desc)
	if found:
		var tag := UiKit.label("Found", 22, Color(it.glow, 0.95))
		tag.add_theme_font_override("font", UiKit.key_font())
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(tag)
	_tappable(p, func(): _open_detail("item", it, found))
	return p


## A see-through button over the whole card: tap (or click) to open its page.
func _tappable(card: PanelContainer, on_tap: Callable) -> void:
	var hit := Button.new()
	hit.focus_mode = Control.FOCUS_NONE
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(1, 1, 1, 0.06)
	hover.set_corner_radius_all(20)
	var none := StyleBoxEmpty.new()
	for k in ["normal", "pressed", "focus", "disabled"]:
		hit.add_theme_stylebox_override(k, none)
	hit.add_theme_stylebox_override("hover", hover)
	hit.pressed.connect(func():
		Sfx.play("ui_click")
		on_tap.call())
	card.add_child(hit)


# --- Detail page -------------------------------------------------------------------

var _detail: Control


## A big look at one thing: its picture (a hidden item turns on its stand, a
## character plays their idle animation), name and full description. Things
## you don't have yet stay a silhouette with a hint of how to get them.
func _open_detail(kind: String, it: Dictionary, mine: bool) -> void:
	_close_detail()
	_detail = Control.new()
	_detail.size = UiFx.DESIGN
	add_child(_detail)
	var dim := Button.new() # tap outside the card to close
	dim.focus_mode = Control.FOCUS_NONE
	var dim_box := StyleBoxFlat.new()
	dim_box.bg_color = Color(0, 0, 0, 0.78)
	for k in ["normal", "hover", "pressed", "focus"]:
		dim.add_theme_stylebox_override(k, dim_box)
	dim.position = Vector2(-1500, -1000)
	dim.size = UiFx.DESIGN + Vector2(3000, 2000)
	dim.pressed.connect(_close_detail)
	_detail.add_child(dim)
	var card := PanelContainer.new()
	var solid := (UiKit.box() as StyleBoxFlat).duplicate() as StyleBoxFlat
	solid.bg_color = Color(0.1, 0.11, 0.15, 0.98) # solid: nothing behind shows through
	card.add_theme_stylebox_override("panel", solid)
	card.position = Vector2(260, 200)
	card.custom_minimum_size = Vector2(1400, 680)
	card.size = Vector2(1400, 680) # long stories scroll instead of growing the card
	_detail.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	card.add_child(row)
	# Picture.
	var frame := PanelContainer.new()
	var fs := StyleBoxFlat.new()
	fs.bg_color = Color(0, 0, 0, 0.25)
	fs.set_corner_radius_all(24)
	frame.add_theme_stylebox_override("panel", fs)
	frame.custom_minimum_size = Vector2(560, 560)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(frame)
	frame.add_child(_detail_picture(kind, it, mine))
	# Words.
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	v.add_child(UiKit.label({"item": "Hidden item", "character": "Character", "slipper": "Slipper"}[kind], 28, UiKit.ACCENT))
	var name_l := UiKit.title(it.name if mine else "???", 72, Color.WHITE, 14)
	v.add_child(name_l)
	v.add_child(UiKit.accent_rule())
	var story := CharacterStories.of(it.id) if kind == "character" and mine else ""
	var desc := UiKit.label(_detail_text(kind, it, mine), 30 if story != "" else 34, Color(1, 1, 1, 0.9 if mine else 0.6))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(700, 0)
	v.add_child(desc)
	for line in _detail_facts(kind, it, mine):
		v.add_child(UiKit.title(line, 34, UiKit.ACCENT if mine else Color(1, 1, 1, 0.55), 6))
	if story != "":
		# Their story: scrolls inside the card (the card keeps its size).
		var head := UiKit.label("Their story", 26, UiKit.ACCENT, 0)
		head.add_theme_font_override("font", UiKit.key_font())
		v.add_child(head)
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.custom_minimum_size = Vector2(700, 250)
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(scroll)
		var body := UiKit.label(story, 27, Color(1, 1, 1, 0.82), 0)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(680, 0)
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_theme_constant_override("line_spacing", 6)
		scroll.add_child(body)
	else:
		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(spacer)
	var close := UiKit.button("Close", UiKit.BLUE, 40, Vector2(240, 100))
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(_close_detail)
	v.add_child(close)
	UiFx.pop(card, 0.0, 0.85, 0.3)


func _close_detail() -> void:
	if is_instance_valid(_detail):
		_detail.queue_free()
	_detail = null


func _detail_picture(kind: String, it: Dictionary, mine: bool) -> Control:
	if kind == "item" and mine:
		return _turntable(it, Vector2(540, 540))
	var pic := TextureRect.new()
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pic.custom_minimum_size = Vector2(520, 520)
	match kind:
		"item":
			pic.texture = EasterEggs.icon(it.id, 20)
			pic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		"slipper":
			pic.texture = PixelArt.slipper_texture(it)
		"character":
			var sheet: Dictionary = PixelArt.character_look(it).idle
			var at := AtlasTexture.new()
			at.atlas = sheet.texture
			var frames := maxi(int(sheet.frames), 1)
			var fw: float = float((sheet.texture as Texture2D).get_width()) / frames
			at.region = Rect2(0, 0, fw, (sheet.texture as Texture2D).get_height())
			pic.texture = at
			if mine and frames > 1:
				# Their idle animation, looping.
				var t := Timer.new()
				t.wait_time = 1.0 / maxf(float(sheet.fps), 1.0)
				t.autostart = true
				var f := [0]
				t.timeout.connect(func():
					f[0] = (f[0] + 1) % frames
					at.region = Rect2(fw * f[0], 0, fw, at.region.size.y))
				pic.add_child(t)
	if not mine:
		pic.modulate = Color(0, 0, 0, 0.6) # silhouette
	return pic


func _detail_text(kind: String, it: Dictionary, mine: bool) -> String:
	if mine:
		return it.desc
	match kind:
		"item":
			return "Still hidden somewhere in the neighborhood. It shows up in round %d - keep your eyes on the rooftops." % it.round
		"character":
			return "Still locked. Get them in character select to read their story."
	return "Still locked. Buy them in weapon select to see what they can do."


func _detail_facts(kind: String, it: Dictionary, mine: bool) -> Array:
	var out := []
	match kind:
		"item":
			out.append("Found!" if mine else "Round %d" % it.round)
		"slipper":
			var r := float(it.get("wind_resist", 0.0))
			out.append("Wind resistance: " + ("Immune" if r >= 1.0 else "%d%%" % roundi(r * 100.0)))
	if kind != "item":
		if mine:
			out.append("Owned")
		elif not Economy.requirement_met(it.id):
			out.append(Economy.requirement_text(it.id) + "  -  %d caps" % it.price)
		else:
			out.append("%d caps" % it.price)
	return out


func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(_detail) and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close_detail()


## The real (placeholder) 3D model turning on a little stand, in its own
## small world so the menu's court doesn't light it.
func _turntable(it: Dictionary, size: Vector2 = Vector2(286, 250)) -> Control:
	var box := SubViewportContainer.new()
	box.custom_minimum_size = size
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.stretch = true
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	box.add_child(vp)
	var world := Node3D.new()
	vp.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.8, 0.85)
	e.ambient_light_energy = 0.6
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.6, 0.0)
	sun.light_energy = 1.3
	world.add_child(sun)
	var glow := OmniLight3D.new()
	glow.light_color = it.glow
	glow.light_energy = 1.5
	glow.omni_range = 3.0
	glow.position = Vector3(0.0, 0.3, 0.9)
	world.add_child(glow)
	var spin := Spinner.new()
	world.add_child(spin)
	var m := EasterEggs.model(it.id)
	var aabb := _bounds(m)
	var longest := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	var k := 0.75 / maxf(longest, 0.01)
	m.scale = Vector3.ONE * k
	m.position = -aabb.get_center() * k
	spin.add_child(m)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 0.25, 1.35)
	cam.rotation.x = -0.18
	cam.fov = 40.0
	world.add_child(cam)
	return box


static func _bounds(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var xf := Transform3D()
		var n: Node = m
		while n != root and n is Node3D:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var box := xf * m.mesh.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


class Spinner extends Node3D:
	func _process(delta: float) -> void:
		rotation.y += delta * 1.2
