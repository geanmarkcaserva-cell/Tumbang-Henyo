class_name RecordsPanel
extends Control
## Custom quiz -> Records: the scores of past custom quiz games on this
## device (CustomRecords), newest first. Each shows the set's title and
## description, who played and when, the score, how far they got, how many
## answers were right, and how it ended. "This set" shows the set open in
## the editor, "All sets" everything. Clear asks twice.

signal closed

var _set_id := ""
var _set_title := ""
var _show_all := false
var _list: VBoxContainer
var _scroll: ScrollContainer
var _sub: Label
var _tab_set: Button
var _tab_all: Button
var _clear: Button
var _clear_armed := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(1560, 900)
	card.add_theme_stylebox_override("panel", UiKit.box())
	center.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	card.add_child(v)
	v.add_child(UiKit.title("Records", 68, Color.WHITE, 14))
	v.add_child(UiKit.accent_rule())
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 14)
	v.add_child(tabs)
	_tab_set = UiKit.button("This set", UiKit.BLUE, 30, Vector2(260, 76))
	_tab_set.pressed.connect(func():
		_show_all = false
		refresh())
	tabs.add_child(_tab_set)
	_tab_all = UiKit.button("All sets", UiKit.BLUE, 30, Vector2(260, 76))
	_tab_all.pressed.connect(func():
		_show_all = true
		refresh())
	tabs.add_child(_tab_all)
	_sub = UiKit.label("", 26, Color(1, 1, 1, 0.7))
	_sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tabs.add_child(_sub)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 20)
	v.add_child(bottom)
	var close := UiKit.button("Close", UiKit.BLUE, 40, Vector2(250, 106))
	close.pressed.connect(hide_panel)
	bottom.add_child(close)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(gap)
	_clear = UiKit.button("Clear records", UiKit.BLUE, 28, Vector2(320, 90))
	_clear.add_theme_color_override("font_color", Color(1.0, 0.62, 0.58))
	_clear.pressed.connect(_on_clear)
	bottom.add_child(_clear)


## Open on the set open in the editor (set_id "" = a new, unsaved set: all sets).
func open(set_id: String, set_title: String) -> void:
	_set_id = set_id
	_set_title = set_title
	_show_all = set_id == ""
	refresh()
	visible = true
	UiFx.pop_in(self)


func hide_panel() -> void:
	visible = false
	closed.emit()


func refresh() -> void:
	_clear_armed = false
	_clear.text = "Clear records"
	_tab_set.disabled = _set_id == ""
	UiKit.set_fill(_tab_set, UiKit.BLUE, not _show_all)
	UiKit.set_fill(_tab_all, UiKit.BLUE, _show_all)
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var records := CustomRecords.list("" if _show_all else _set_id)
	_sub.text = ("%d game%s" % [records.size(), "" if records.size() == 1 else "s"]) + \
			("" if _show_all else "  in  " + _set_title)
	_clear.disabled = records.is_empty()
	if records.is_empty():
		var none := UiKit.label("No games yet. Play this set and your score shows up here." if not _show_all
				else "No custom quiz games yet.", 30, Color(1, 1, 1, 0.65))
		_list.add_child(none)
		return
	for r in records:
		_list.add_child(_row(r))
	_scroll.scroll_vertical = 0


func _row(r: Dictionary) -> Control:
	var p := PanelContainer.new()
	var box := UiKit.box()
	box.shadow_size = 0
	box.content_margin_top = 16
	box.content_margin_bottom = 16
	box.content_margin_left = 24
	box.content_margin_right = 24
	p.add_theme_stylebox_override("panel", box)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 24)
	p.add_child(h)
	# Left: what was played, by whom, when.
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 2)
	h.add_child(left)
	var title := UiKit.title(String(r.get("title", "Custom quiz")), 34, Color.WHITE, 6)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.custom_minimum_size = Vector2(820, 0)
	left.add_child(title)
	var desc := String(r.get("desc", ""))
	if desc != "":
		var d := UiKit.label(desc, 24, Color(1, 1, 1, 0.8))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(820, 0)
		left.add_child(d)
	var when := Time.get_datetime_string_from_unix_time(int(r.get("time", 0)), true).left(16)
	var who := "%s  -  %s%s" % [String(r.get("player", "")), when, "  -  class game" if r.get("class", false) else ""]
	left.add_child(UiKit.label(who, 22, Color(1, 1, 1, 0.55)))
	# Right: the numbers.
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(470, 0)
	right.add_theme_constant_override("separation", 2)
	h.add_child(right)
	var score := UiKit.title(_thousands(int(r.get("score", 0))), 44, UiKit.ACCENT, 8)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(score)
	var asked := int(r.get("asked", 0))
	var correct := int(r.get("correct", 0))
	var pct := "  (%d%%)" % roundi(100.0 * correct / asked) if asked > 0 else ""
	var line := UiKit.label("Rounds cleared %d  -  %d / %d right%s" % [int(r.get("rounds", 0)), correct, asked, pct], 24, Color.WHITE)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(line)
	var result := String(r.get("result", ""))
	var tag := UiKit.label({"home": "Made it home!", "caught": "Caught", "left": "Left early"}.get(result, ""), 22,
			{"home": Color(0.55, 1.0, 0.6), "caught": Color(1.0, 0.7, 0.5), "left": Color(1, 1, 1, 0.55)}.get(result, Color.WHITE))
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(tag)
	return p


func _on_clear() -> void:
	if not _clear_armed:
		_clear_armed = true
		_clear.text = "Tap again to clear"
		return
	CustomRecords.clear("" if _show_all else _set_id)
	refresh()


static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out
