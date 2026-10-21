class_name ClassQuestionView
extends VBoxContainer
## The teacher's view of a class game's question: the same question and
## choices the students have on their screens (in the same order), the
## countdown, how many picked each choice and every student's pick (green
## right, red wrong). Between questions it shows how many students are back
## at the line, with a button to send the next question right away.

const LETTERS := ["A", "B", "C"]
const RIGHT := Color(0.45, 0.9, 0.5)
const WRONG := Color(1.0, 0.45, 0.42)

var _head: Label
var _timer: Label
var _question: Label
var _rows: Array = [] ## {panel, letter, text, count, box}
var _status: Label
var _picks: HFlowContainer
var _next: Button


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	var top := HBoxContainer.new()
	add_child(top)
	_head = UiKit.title("", 40, Color.WHITE, 8)
	_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_head)
	_timer = UiKit.title("", 44, UiKit.ACCENT, 8)
	top.add_child(_timer)
	_question = UiKit.label("", 30, Color.WHITE, 0)
	_question.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_question.custom_minimum_size = Vector2(700, 0)
	add_child(_question)
	for i in 3:
		var panel := PanelContainer.new()
		var box := StyleBoxFlat.new()
		box.bg_color = Color(1, 1, 1, 0.06)
		box.border_color = Color(1, 1, 1, 0.12)
		box.set_border_width_all(2)
		box.set_corner_radius_all(16)
		box.content_margin_left = 18
		box.content_margin_right = 18
		box.content_margin_top = 8
		box.content_margin_bottom = 8
		panel.add_theme_stylebox_override("panel", box)
		add_child(panel)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		panel.add_child(row)
		var letter := UiKit.title(LETTERS[i], 30, UiKit.ACCENT, 6)
		letter.custom_minimum_size = Vector2(34, 0)
		row.add_child(letter)
		var text := UiKit.label("", 26, Color.WHITE, 0)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(text)
		var count := UiKit.title("", 30, Color.WHITE, 6)
		count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(count)
		_rows.append({"panel": panel, "letter": letter, "text": text, "count": count, "box": box})
	_status = UiKit.label("", 24, Color(1, 1, 1, 0.65), 0)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(700, 0)
	add_child(_status)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(700, 120)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	_picks = HFlowContainer.new()
	_picks.add_theme_constant_override("h_separation", 8)
	_picks.add_theme_constant_override("v_separation", 8)
	_picks.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_picks)
	_next = UiKit.button("Send next question", UiKit.BLUE, 30, Vector2(380, 76))
	_next.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_next.pressed.connect(func():
		if Lobby.q_open:
			Lobby.end_question()
		else:
			Lobby.release_question())
	add_child(_next)
	Lobby.question_changed.connect(refresh)
	Lobby.wait_changed.connect(refresh)
	Lobby.players_changed.connect(refresh)
	refresh()


func refresh() -> void:
	if _head == null:
		return
	var idx := Lobby.q_index
	var has_q := idx >= 0 and Lobby.question_count() > 0
	for r in _rows:
		(r.panel as Control).visible = has_q
	if not has_q:
		_head.text = "First question"
		_timer.text = ""
		_question.text = "It goes out to everyone as soon as the whole class is at the throw line."
		_status.text = _wait_text()
		_fill_picks({}, [0, 1, 2], {})
		_next.text = "Send it now"
		_next.visible = Lobby.match_on
		return
	var q := Lobby.class_question(idx)
	var order := Lobby.choice_order(idx)
	_head.text = "Question %d" % (idx + 1)
	_question.text = String(q.get("question", ""))
	var counts := {}
	for a in Lobby.q_answers.values():
		counts[int(a.choice)] = int(counts.get(int(a.choice), 0)) + 1
	var answer := int(q.get("answer", -1))
	for i in 3:
		var r: Dictionary = _rows[i]
		var original: int = order[i]
		(r.text as Label).text = String(q.choices[original])
		(r.count as Label).text = str(counts.get(original, 0))
		var box: StyleBoxFlat = r.box
		var reveal := not Lobby.q_open and original == answer # the right one, once it closes
		box.bg_color = Color(RIGHT, 0.18) if reveal else Color(1, 1, 1, 0.06)
		box.border_color = RIGHT if reveal else Color(1, 1, 1, 0.12)
	if Lobby.q_open:
		_timer.text = "%ds" % ceili(maxf(Lobby.q_left, 0.0))
		_status.text = "%d of %d answered" % [Lobby.q_answers.size(), Lobby.q_takers.size()]
		_next.text = "End this question"
	else:
		_timer.text = "Closed"
		_status.text = _wait_text()
		_next.text = "Send next question"
	_next.visible = Lobby.match_on
	_fill_picks(Lobby.q_answers, order, Lobby.q_takers)


func _wait_text() -> String:
	if not Lobby.match_on:
		return ""
	var active := 0
	for p in Lobby.players.values():
		if not p.get("left", false) and not p.get("out", false):
			active += 1
	return "At the throw line, ready for the next one: %d / %d" % [Lobby.q_ready.size(), active]


## A chip per student who got the question: name and the letter they picked,
## green when right, red when wrong, grey while they're still thinking.
func _fill_picks(answers: Dictionary, order: Array, takers: Dictionary) -> void:
	for c in _picks.get_children():
		c.queue_free()
	var ids := takers.keys()
	for id in answers:
		if not ids.has(id):
			ids.append(id)
	for id in ids:
		var p: Dictionary = Lobby.players.get(id, {})
		if p.is_empty():
			continue
		var text := String(p.name)
		var col := Color(1, 1, 1, 0.45)
		if answers.has(id):
			var a: Dictionary = answers[id]
			if int(a.choice) < 0:
				text += "  -  no answer"
				col = WRONG
			else:
				text += "  -  " + LETTERS[order.find(int(a.choice))]
				col = RIGHT if a.correct else WRONG
		else:
			text += "  ..."
		_picks.add_child(_chip(text, col))


func _chip(text: String, col: Color) -> Control:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(col.r, col.g, col.b, 0.16)
	s.border_color = Color(col.r, col.g, col.b, 0.7)
	s.set_border_width_all(2)
	s.set_corner_radius_all(14)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", s)
	var l := UiKit.label(text, 22, col.lightened(0.3), 0)
	l.add_theme_font_override("font", UiKit.key_font())
	p.add_child(l)
	return p
