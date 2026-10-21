class_name AccountPanel
extends Control
## Main menu -> Account: the local accounts on this device (up to
## Accounts.MAX_ACCOUNTS). Left: the list, with "+ New account". Right: the
## picked account's card (stats, trophies) with Play as / Rename / Delete, a
## way into its achievements, and "Change picture" (profile picture: a
## colour plus a character face, a tsinelas or a Collection item it has).
##
## With no account yet (first launch, or the last one was deleted) it opens in
## "welcome" mode: just the create box, no way back until an account exists.

signal back_pressed
signal achievements_pressed
signal welcomed ## the first account was made from the welcome box

const NAME_HINT := "Your name, e.g. Juan"

var _selected := "" ## account shown on the right
var _list: VBoxContainer
var _count: Label
var _new_btn: Button
var _back_btn: Button
var _cards: Control ## list + details (hidden in welcome mode)
var _avatar: TextureRect
var _initial: Label
var _name: Label
var _since: Label
var _playing_tag: Label
var _stats: GridContainer
var _play_btn: Button
var _ach_btn: Button
var _rename_btn: Button
var _delete_btn: Button
var _delete_armed := false

# The name box (create / rename / welcome).
var _editor: Control
var _ed_title: Label
var _ed_hint: Label
var _ed_field: LineEdit
var _ed_error: Label
var _ed_ok: Button
var _ed_cancel: Button
var _ed_mode := "" ## "create", "rename" or "welcome"

# The picture picker.
var _pic: Control
var _pic_preview: TextureRect
var _pic_colors: HBoxContainer
var _pic_grid: VBoxContainer
var _pic_crop: Button
const SWATCHES := [Color(0.98, 0.72, 0.25), Color(0.4, 0.75, 1.0), Color(0.55, 0.9, 0.5), Color(1.0, 0.5, 0.6),
		Color(0.75, 0.6, 1.0), Color(1.0, 0.45, 0.25), Color(0.3, 0.85, 0.8), Color(0.92, 0.92, 0.95)]

static var _avatar_cache := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = UiFx.DESIGN
	size = UiFx.DESIGN
	_cards = Control.new()
	_cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cards.size = UiFx.DESIGN
	add_child(_cards)
	_build_list()
	_build_details()
	_build_editor()
	_build_picker()
	Accounts.changed.connect(refresh)
	refresh()


## True while the name box has the keyboard (Esc should cancel the box, not leave).
func is_typing() -> bool:
	return _editor.visible


## Esc / Back: close the name box or picture picker if open; otherwise leave (if allowed).
func cancel() -> bool:
	if _pic.visible:
		_pic.visible = false
		return true
	if _editor.visible:
		if _ed_mode != "welcome":
			_close_editor()
		return true
	return false


# --- Layout -----------------------------------------------------------------------------

func _build_list() -> void:
	var card := PanelContainer.new()
	card.position = Vector2(110, 80)
	card.custom_minimum_size = Vector2(680, 920)
	card.add_theme_stylebox_override("panel", UiKit.box())
	_cards.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	card.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var title := UiKit.title("Accounts", 68, Color.WHITE, 14)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_count = UiKit.title("", 40, UiKit.ACCENT, 8)
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_count)
	v.add_child(UiKit.accent_rule())
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 12)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_list)
	_new_btn = UiKit.button("+ New account", UiKit.GOLD, 38, Vector2(612, 110))
	_new_btn.pressed.connect(func(): _open_editor("create"))
	v.add_child(_new_btn)
	_back_btn = UiKit.button("Back", UiKit.BLUE, 44, Vector2(250, 110))
	_back_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_back_btn.pressed.connect(func(): back_pressed.emit())
	v.add_child(_back_btn)


func _build_details() -> void:
	var card := PanelContainer.new()
	card.position = Vector2(830, 80)
	card.custom_minimum_size = Vector2(980, 920)
	card.add_theme_stylebox_override("panel", UiKit.box())
	_cards.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	card.add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 26)
	v.add_child(head)
	_avatar = TextureRect.new()
	_avatar.custom_minimum_size = Vector2(150, 150)
	_avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(_avatar)
	_initial = UiKit.title("", 84, Color.WHITE, 10)
	_initial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_avatar.add_child(_initial)
	var who := VBoxContainer.new()
	who.alignment = BoxContainer.ALIGNMENT_CENTER
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(who)
	_name = UiKit.title("", 72, Color.WHITE, 14)
	_name.clip_text = true
	_name.custom_minimum_size = Vector2(600, 0)
	who.add_child(_name)
	_since = UiKit.label("", 26, Color(1, 1, 1, 0.6))
	_since.add_theme_font_override("font", UiKit.key_font())
	who.add_child(_since)
	_playing_tag = UiKit.title("Playing now", 30, UiKit.ACCENT, 6)
	who.add_child(_playing_tag)
	var pic_btn := UiKit.button("Change picture", UiKit.BLUE, 28, Vector2(300, 76))
	pic_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	pic_btn.pressed.connect(_open_picker)
	who.add_child(pic_btn)
	v.add_child(UiKit.accent_rule())

	_stats = GridContainer.new()
	_stats.columns = 2
	_stats.add_theme_constant_override("h_separation", 18)
	_stats.add_theme_constant_override("v_separation", 14)
	_stats.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_stats)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	v.add_child(row)
	_play_btn = UiKit.button("Play as this", UiKit.GOLD, 34, Vector2(300, 104))
	_play_btn.pressed.connect(func(): Accounts.switch_to(_selected))
	row.add_child(_play_btn)
	_ach_btn = UiKit.button("Achievements", UiKit.BLUE, 34, Vector2(300, 104))
	_ach_btn.pressed.connect(func(): achievements_pressed.emit())
	row.add_child(_ach_btn)
	_rename_btn = UiKit.button("Rename", UiKit.BLUE, 34, Vector2(250, 104))
	_rename_btn.pressed.connect(func(): _open_editor("rename"))
	row.add_child(_rename_btn)
	_delete_btn = UiKit.button("Delete", UiKit.BLUE, 34, Vector2(250, 104))
	_delete_btn.pressed.connect(_on_delete)
	row.add_child(_delete_btn)


func _build_editor() -> void:
	_editor = Control.new()
	_editor.size = UiFx.DESIGN
	_editor.visible = false
	add_child(_editor)
	# Dim everything behind, edge to edge even on wide screens.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.position = Vector2(-1500, -1000)
	dim.size = UiFx.DESIGN + Vector2(3000, 2000)
	_editor.add_child(dim)
	var card := PanelContainer.new()
	card.position = Vector2(510, 250)
	card.custom_minimum_size = Vector2(900, 0)
	card.add_theme_stylebox_override("panel", UiKit.box())
	_editor.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	card.add_child(v)
	_ed_title = UiKit.title("", 64, Color.WHITE, 12)
	v.add_child(_ed_title)
	v.add_child(UiKit.accent_rule())
	_ed_hint = UiKit.label("", 28, Color(1, 1, 1, 0.75))
	_ed_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ed_hint.custom_minimum_size = Vector2(830, 0)
	v.add_child(_ed_hint)
	_ed_field = LineEdit.new()
	_ed_field.placeholder_text = NAME_HINT
	_ed_field.max_length = Accounts.NAME_MAX
	_ed_field.custom_minimum_size = Vector2(0, 90)
	_ed_field.add_theme_font_size_override("font_size", 44)
	_ed_field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ed_field.select_all_on_focus = true
	_ed_field.text_changed.connect(func(_t): _ed_error.text = "")
	_ed_field.text_submitted.connect(func(_t): _submit())
	v.add_child(_ed_field)
	_ed_error = UiKit.label("", 26, Color(1, 0.55, 0.5))
	_ed_error.custom_minimum_size = Vector2(0, 36)
	v.add_child(_ed_error)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(row)
	_ed_cancel = UiKit.button("Cancel", UiKit.BLUE, 36, Vector2(250, 104))
	_ed_cancel.pressed.connect(_close_editor)
	row.add_child(_ed_cancel)
	_ed_ok = UiKit.button("Create", UiKit.GOLD, 36, Vector2(300, 104))
	_ed_ok.pressed.connect(_submit)
	row.add_child(_ed_ok)


# --- State ------------------------------------------------------------------------------

## Rebuild the list and the card; with no accounts left, go to welcome mode.
func refresh() -> void:
	if _list == null:
		return
	var accounts := Accounts.list()
	if accounts.is_empty():
		_selected = ""
		_cards.visible = false
		if _ed_mode != "welcome":
			_open_editor("welcome")
		return
	_cards.visible = true
	if _ed_mode == "welcome":
		_close_editor()
	if Accounts.find(_selected).is_empty():
		_selected = Accounts.current_id()
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	for a in accounts:
		_list.add_child(_account_row(a))
	_count.text = "%d / %d" % [accounts.size(), Accounts.MAX_ACCOUNTS]
	_new_btn.disabled = not Accounts.can_create()
	_new_btn.text = "+ New account" if Accounts.can_create() else "Full (%d max)" % Accounts.MAX_ACCOUNTS
	_show_details()


func _account_row(a: Dictionary) -> Control:
	var current: bool = a.id == Accounts.current_id()
	var b := UiKit.button(a.name, UiKit.BLUE, 40, Vector2(612, 122))
	UiKit.set_fill(b, UiKit.BLUE, a.id == _selected)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.icon = avatar_texture(a, 72)
	b.add_theme_constant_override("h_separation", 22)
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.pressed.connect(func():
		_selected = a.id
		_delete_armed = false
		refresh())
	if current:
		var tag := UiKit.title("Playing", 26, UiKit.ACCENT, 6)
		tag.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
		tag.offset_left = -150
		tag.offset_right = -22
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		b.add_child(tag)
	return b


func _show_details() -> void:
	var a := Accounts.find(_selected)
	if a.is_empty():
		return
	var current: bool = a.id == Accounts.current_id()
	_avatar.texture = avatar_texture(a, 150)
	_name.text = a.name
	_initial.text = String(a.name).left(1).to_upper()
	_initial.visible = String(a.get("avatar", {}).get("kind", "letter")) == "letter"
	_since.text = "Since " + Time.get_date_string_from_unix_time(int(a.get("created", 0)))
	_playing_tag.visible = current
	_play_btn.visible = not current
	_ach_btn.visible = current # only the active account's trophies are loaded
	_set_delete_armed(false)

	for c in _stats.get_children():
		_stats.remove_child(c)
		c.queue_free()
	var s := Accounts.stats_of(a.id)
	if current:
		s.caps = Economy.caps # live values (may not be saved yet)
		s.owned = Economy.owned.size()
	var best := "-"
	if int(s.best) > 0:
		best = "%d  (%s)" % [s.best, GameManager.theme_name(s.best_theme)]
	var tiles := [
		["Caps", str(s.caps)],
		["Trophies", "%d / %d" % [s.achievements, Achievements.LIST.size()]],
		["Games played", str(s.games)],
		["Made it home", str(s.wins)],
		["Best score", best],
		["Highest round", str(s.highest_round) if int(s.highest_round) > 0 else "-"],
		["Right answers", str(s.correct)],
		["Bullseyes", str(s.bullseyes)],
		["Items owned", str(s.owned)],
		["Collection", "%d / %d" % [s.eggs if not current else Economy.collection.size(), EasterEggs.ITEMS.size()]],
		["Time played", _duration(int(s.play_seconds))],
	]
	for t in tiles:
		_stats.add_child(_stat_tile(t[0], t[1]))


func _stat_tile(caption: String, value: String) -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(445, 84)
	var s := StyleBoxFlat.new()
	s.bg_color = Color(1, 1, 1, 0.06)
	s.set_corner_radius_all(14)
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", s)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 0)
	p.add_child(v)
	var c := UiKit.label(caption, 22, Color(1, 1, 1, 0.55))
	c.add_theme_font_override("font", UiKit.key_font())
	v.add_child(c)
	var val := UiKit.title(value, 38, Color.WHITE, 6)
	val.clip_text = true
	v.add_child(val)
	return p


static func _duration(seconds: int) -> String:
	if seconds <= 0:
		return "-"
	var h := seconds / 3600
	var m := (seconds % 3600) / 60
	if h > 0:
		return "%dh %02dm" % [h, m]
	return "%dm" % maxi(m, 1)


# --- Delete (two taps) ----------------------------------------------------------------

func _on_delete() -> void:
	if not _delete_armed:
		_set_delete_armed(true)
		get_tree().create_timer(3.0).timeout.connect(func(): _set_delete_armed(false))
		return
	_set_delete_armed(false)
	Sfx.play("ui_back")
	Accounts.delete(_selected)


func _set_delete_armed(on: bool) -> void:
	_delete_armed = on
	if _delete_btn == null:
		return
	_delete_btn.text = "Sure? Tap again" if on else "Delete"
	_delete_btn.custom_minimum_size.x = 340 if on else 250
	_delete_btn.add_theme_color_override("font_color", Color(1, 0.55, 0.5) if on else UiKit.TEXT)
	_delete_btn.add_theme_color_override("font_hover_color", Color(1, 0.55, 0.5) if on else UiKit.TEXT)


# --- Name box -------------------------------------------------------------------------------

func _open_editor(mode: String) -> void:
	_ed_mode = mode
	_editor.visible = true
	_ed_error.text = ""
	match mode:
		"welcome":
			_ed_title.text = "Welcome!"
			_ed_hint.text = "Make an account to keep your caps, items, scores and trophies. " \
					+ "Up to %d players can have their own on this device." % Accounts.MAX_ACCOUNTS
			_ed_field.text = ""
			_ed_ok.text = "Let's go!"
		"create":
			_ed_title.text = "New account"
			_ed_hint.text = "A fresh start: its own caps, items, scores and trophies."
			_ed_field.text = ""
			_ed_ok.text = "Create"
		"rename":
			_ed_title.text = "Rename"
			_ed_hint.text = "The new name shows on the leaderboard and in class games."
			_ed_field.text = Accounts.find(_selected).get("name", "")
			_ed_ok.text = "Save"
	_ed_cancel.visible = mode != "welcome"
	UiFx.pop(_editor.get_child(1), 0.0, 0.7, 0.4)
	_ed_field.grab_focus.call_deferred()


func _close_editor() -> void:
	_ed_mode = ""
	_editor.visible = false
	_ed_field.release_focus()


func _submit() -> void:
	var was_welcome := _ed_mode == "welcome"
	var ignore := _selected if _ed_mode == "rename" else ""
	var err := Accounts.check_name(_ed_field.text, ignore)
	if err != "":
		_ed_error.text = err
		Sfx.play("ui_error")
		UiFx.shake(_ed_field)
		return
	if _ed_mode == "rename":
		Accounts.rename(_selected, _ed_field.text)
	else:
		var id := Accounts.create(_ed_field.text)
		if id == "":
			_ed_error.text = "No room for more accounts."
			return
		_selected = id
	Sfx.play("ui_equip")
	_close_editor()
	refresh()
	if was_welcome:
		welcomed.emit()


# --- Avatars ------------------------------------------------------------------------------

## The account's profile picture (see Avatars). A plain "letter" badge gets
## the first letter drawn on top by whoever shows it.
static func avatar_texture(a: Dictionary, px: int) -> Texture2D:
	return Avatars.texture(a, px)


# --- Picture picker --------------------------------------------------------------------

func _build_picker() -> void:
	_pic = Control.new()
	_pic.size = UiFx.DESIGN
	_pic.visible = false
	add_child(_pic)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.position = Vector2(-1500, -1000)
	dim.size = UiFx.DESIGN + Vector2(3000, 2000)
	_pic.add_child(dim)
	var card := PanelContainer.new()
	card.position = Vector2(250, 60)
	card.custom_minimum_size = Vector2(1420, 960)
	card.add_theme_stylebox_override("panel", UiKit.box())
	_pic.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	card.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 30)
	v.add_child(head)
	_pic_preview = TextureRect.new()
	_pic_preview.custom_minimum_size = Vector2(150, 150)
	_pic_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pic_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(_pic_preview)
	var hv := VBoxContainer.new()
	hv.alignment = BoxContainer.ALIGNMENT_CENTER
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hv)
	hv.add_child(UiKit.title("Profile picture", 64, Color.WHITE, 12))
	_pic_colors = HBoxContainer.new()
	_pic_colors.add_theme_constant_override("separation", 14)
	hv.add_child(_pic_colors)
	# Frame the chosen picture yourself (any angle, any zoom).
	_pic_crop = UiKit.button("Crop", UiKit.BLUE, 40, Vector2(200, 110))
	_pic_crop.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_pic_crop.pressed.connect(_open_cropper)
	head.add_child(_pic_crop)
	var done := UiKit.button("Done", UiKit.GOLD, 40, Vector2(240, 110))
	done.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	done.pressed.connect(func(): _pic.visible = false)
	head.add_child(done)
	v.add_child(UiKit.accent_rule())
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1350, 700)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_pic_grid = VBoxContainer.new()
	_pic_grid.add_theme_constant_override("separation", 10)
	scroll.add_child(_pic_grid)


func _open_picker() -> void:
	_fill_picker()
	_pic.visible = true
	UiFx.pop(_pic.get_child(1), 0.0, 0.8, 0.4)


func _fill_picker() -> void:
	var a := Accounts.find(_selected)
	if a.is_empty():
		return
	_pic_preview.texture = avatar_texture(a, 150)
	var current_av: Dictionary = a.get("avatar", {"kind": "letter"})
	_pic_crop.disabled = String(current_av.get("kind", "letter")) == "letter"
	for c in _pic_colors.get_children():
		c.queue_free()
	for col in SWATCHES:
		var b := Button.new()
		b.custom_minimum_size = Vector2(64, 64)
		b.focus_mode = Control.FOCUS_NONE
		var sb := StyleBoxFlat.new()
		sb.bg_color = col
		sb.set_corner_radius_all(32)
		var chosen: bool = (a.get("color", Color()) as Color).is_equal_approx(col)
		sb.border_color = Color.WHITE if chosen else Color(0, 0, 0, 0.35)
		sb.set_border_width_all(5 if chosen else 2)
		for k in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(k, sb)
		var swatch: Color = col
		b.pressed.connect(func():
			Accounts.set_color(_selected, swatch)
			_fill_picker())
		_pic_colors.add_child(b)
	for c in _pic_grid.get_children():
		_pic_grid.remove_child(c)
		c.queue_free()
	var unlocks := Accounts.unlocks_of(_selected)
	var owned: Array = unlocks.owned
	var found: Array = unlocks.collection
	_pic_section("Letter", [{"kind": "letter"}], a, current_av, func(_av): return true)
	var chars := []
	for it in Economy.CHARACTERS:
		chars.append({"kind": "character", "id": it.id, "free": it.price == 0})
	_pic_section("Characters", chars, a, current_av, func(av): return av.free or owned.has(av.id))
	var slips := []
	for it in Economy.SLIPPERS:
		slips.append({"kind": "slipper", "id": it.id, "free": it.price == 0})
	_pic_section("Slippers", slips, a, current_av, func(av): return av.free or owned.has(av.id))
	var eggs := []
	for it in EasterEggs.ITEMS:
		eggs.append({"kind": "item", "id": it.id})
	_pic_section("Collection", eggs, a, current_av, func(av): return found.has(av.id))


## Crop: drag and zoom the current picture under a round window.
func _open_cropper() -> void:
	var a := Accounts.find(_selected)
	var av: Dictionary = a.get("avatar", {"kind": "letter"})
	var src := Avatars.source(av)
	if src == null:
		return
	var auto: Rect2i
	if String(av.kind) == "character":
		auto = Avatars.face_rect(src)
	else:
		var side := maxi(src.get_width(), src.get_height())
		auto = Rect2i((src.get_width() - side) / 2, (src.get_height() - side) / 2, side, side)
	var start := Avatars.crop_rect(src, av.crop) if (av.get("crop", []) as Array).size() == 3 else auto
	var cropper := AvatarCropper.new()
	_pic.add_child(cropper)
	cropper.setup(src, start, auto)
	cropper.saved.connect(func(crop: Array):
		var framed := av.duplicate()
		framed["crop"] = crop
		Accounts.set_avatar(_selected, framed)
		Sfx.play("ui_equip")
		_fill_picker())


func _pic_section(title: String, options: Array, account: Dictionary, current_av: Dictionary, unlocked: Callable) -> void:
	var t := UiKit.title(title, 36, UiKit.ACCENT, 6)
	_pic_grid.add_child(t)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 14)
	row.add_theme_constant_override("v_separation", 14)
	row.custom_minimum_size = Vector2(1330, 0)
	_pic_grid.add_child(row)
	for av in options:
		var ok: bool = unlocked.call(av)
		var pick := {"kind": av.kind}
		if av.has("id"):
			pick.id = av.id
		var b := Button.new()
		b.custom_minimum_size = Vector2(132, 132)
		b.focus_mode = Control.FOCUS_NONE
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.expand_icon = true
		var shown := account.duplicate()
		shown.avatar = pick
		b.icon = avatar_texture(shown, 112)
		var selected: bool = String(current_av.get("kind", "letter")) == pick.kind and String(current_av.get("id", "")) == String(pick.get("id", ""))
		UiKit.set_fill(b, UiKit.BLUE, selected)
		if not ok:
			b.disabled = true
			b.modulate = Color(0.3, 0.3, 0.35, 0.9)
			b.tooltip_text = "Locked"
			var lock := UiKit.title("?" if pick.kind == "item" else "Locked", 26 if pick.kind != "item" else 60, Color.WHITE, 6)
			lock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			b.add_child(lock)
		elif pick.kind == "letter":
			var l := UiKit.title(String(account.name).left(1).to_upper(), 64, Color.WHITE, 8)
			l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(l)
		b.pressed.connect(func():
			Accounts.set_avatar(_selected, pick)
			Sfx.play("ui_equip")
			_fill_picker())
		row.add_child(b)
