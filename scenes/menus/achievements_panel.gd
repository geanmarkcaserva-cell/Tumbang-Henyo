class_name AchievementsPanel
extends Control
## Main menu -> Achievements: every trophy in two columns, unlocked ones in
## colour with the date, locked ones grey (secret ones as "???"), and a
## progress bar for the "do it N times" ones.

signal back_pressed

var _count: Label
var _bar: ProgressBar
var _grid: GridContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(1920, 1080)
	var card := PanelContainer.new()
	card.position = Vector2(150, 70)
	card.custom_minimum_size = Vector2(1620, 930)
	card.add_theme_stylebox_override("panel", UiKit.box(UiKit.PANEL_DARK, Color(0.3, 0.3, 0.32), 10, 8))
	add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	card.add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 24)
	v.add_child(head)
	var title := UiKit.title("Achievements", 72, Color.WHITE, 14)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(right)
	_count = UiKit.title("", 40, UiKit.ACCENT, 8)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_count)
	_bar = _progress_bar(Vector2(360, 16))
	right.add_child(_bar)
	v.add_child(UiKit.accent_rule())

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1560, 690)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 20)
	_grid.add_theme_constant_override("v_separation", 14)
	scroll.add_child(_grid)

	var back := UiKit.button("Back", UiKit.BLUE, 44, Vector2(250, 110))
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(func(): back_pressed.emit())
	v.add_child(back)
	Achievements.unlocked.connect(func(_id): refresh())
	refresh()


func refresh() -> void:
	if _grid == null:
		return
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	var total := Achievements.LIST.size()
	var got := Achievements.unlocked_count()
	_count.text = "%d / %d" % [got, total]
	_bar.value = float(got) / total * 100.0
	# Unlocked first (newest first), then locked in list order.
	var done := []
	var todo := []
	for a in Achievements.LIST:
		if Achievements.is_unlocked(a.id):
			done.append(a)
		else:
			todo.append(a)
	done.sort_custom(func(x, y): return Achievements.unlocked_at(x.id) > Achievements.unlocked_at(y.id))
	for a in done + todo:
		_grid.add_child(_row(a))


func _row(a: Dictionary) -> Control:
	var got := Achievements.is_unlocked(a.id)
	var secret: bool = a.get("secret", false) and not got
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(770, 120)
	var s := StyleBoxFlat.new()
	s.bg_color = Color(1, 1, 1, 0.07) if got else Color(0, 0, 0, 0.22)
	s.border_color = Color(TrophyIcon.TIERS[a.tier], 0.55) if got else Color(1, 1, 1, 0.06)
	s.set_border_width_all(2 if got else 1)
	s.set_corner_radius_all(18)
	s.content_margin_left = 14
	s.content_margin_right = 20
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", s)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)
	var icon := TrophyIcon.new()
	icon.custom_minimum_size = Vector2(92, 92)
	icon.tier = a.tier
	icon.locked = not got
	icon.spin = false
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var name_l := UiKit.title("???" if secret else a.name, 34, Color.WHITE if got else Color(1, 1, 1, 0.6), 6)
	col.add_child(name_l)
	var desc := UiKit.label("A secret. Keep playing to find it." if secret else a.desc, 22,
			Color(1, 1, 1, 0.75) if got else Color(1, 1, 1, 0.45), 0)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(560, 0)
	col.add_child(desc)
	if got:
		var when := Time.get_date_string_from_unix_time(Achievements.unlocked_at(a.id))
		var tag := UiKit.label("Unlocked %s  -  %s" % [when, String(a.tier).capitalize()], 18, Color(TrophyIcon.TIERS[a.tier], 0.9), 0)
		tag.add_theme_font_override("font", UiKit.key_font())
		col.add_child(tag)
	elif a.has("goal"):
		var cur := mini(Achievements.get_stat(a.stat), int(a.goal))
		var prow := HBoxContainer.new()
		prow.add_theme_constant_override("separation", 10)
		col.add_child(prow)
		var bar := _progress_bar(Vector2(300, 12))
		bar.value = float(cur) / float(a.goal) * 100.0
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		prow.add_child(bar)
		var pl := UiKit.label("%d / %d" % [cur, a.goal], 18, Color(1, 1, 1, 0.55), 0)
		prow.add_child(pl)
	return panel


func _progress_bar(sz: Vector2) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = sz
	b.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.1)
	bg.set_corner_radius_all(int(sz.y * 0.5))
	var fill := StyleBoxFlat.new()
	fill.bg_color = UiKit.ACCENT
	fill.set_corner_radius_all(int(sz.y * 0.5))
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fill)
	return b
