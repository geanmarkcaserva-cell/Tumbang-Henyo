class_name CustomTutorial
extends Control
## A short animated tour of the custom quiz screen. The player's own
## character and their friends act out each step on a little stage, using
## only their idle / run / happy sheets; the props (papers, the AI chat
## bubble, the quiz box, labels) are drawn here.
##
## Custom quiz is still in beta: questions go in by copy and paste only, so
## the tour says so on its first page.
##
## Opens by itself the first time the custom screen is opened in a session.
## "Close" hides it until the next session; "Don't show again" for good (until
## Settings > Show all tutorials again). Settings > Force show all tutorials
## opens it every time.

signal closed

const DISMISS_ID := "custom_quiz_tour" ## kept in Economy.tips_seen
const GROUND := 300.0 ## the stage floor, in stage pixels
const ACTOR_H := 170.0
const STAGE := Vector2(1100, 330)
const GREEN := Color(0.4, 0.85, 0.5)
const YELLOW := Color(1.0, 0.8, 0.3)
const RED := Color(1.0, 0.45, 0.4)
const GREY := Color(0.55, 0.57, 0.62)

const PAGES := [
	{"title": "Custom Quiz is in beta",
		"body": "Turn any lesson into a game! While it's in beta, questions go in by copy and paste. File upload isn't ready yet."},
	{"title": "1. Copy the AI prompt",
		"body": "Tap COPY AI PROMPT. Open ChatGPT, Gemini or Claude, paste it and add your lesson notes."},
	{"title": "2. Paste the answer here",
		"body": "Tap Copy on the AI's answer, come back and tap PASTE QUESTIONS. The game checks every question for you."},
	{"title": "Easy, medium, hard",
		"body": "Write Easy, Medium or Hard on a line above your questions. No labels? The first ones play as easy, the last ones as hard."},
	{"title": "Play or host a class",
		"body": "PLAY to practice on your own, or HOST CLASS so your students join with a code and answer together."},
	{"title": "Practice mode, with Records",
		"body": "Custom quizzes are for learning, so they don't give any bottlecaps. Every game you finish is saved in RECORDS with the set's name and description, so you can look back at your scores."},
]

## Shown already in this session (Close keeps it shut until the next one).
static var shown_this_session := false

var page := 0
var _panel: PanelContainer
var _stage: Control
var _title: Label
var _body: Label
var _dots: Label
var _back: Button
var _next: Button
var _cast: Array[String] = [] ## character ids: the player's own first, then friends


## Should the tour open by itself now?
static func should_auto_open() -> bool:
	if Settings.force_tutorials:
		return true
	return not shown_this_session and not Economy.tips_seen.has(DISMISS_ID)


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP # nothing behind it can be clicked
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	_panel = PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.05, 0.06, 0.1, 0.98)
	box.border_color = UiKit.ACCENT
	box.set_border_width_all(2)
	box.border_width_top = 5
	box.set_corner_radius_all(26)
	box.shadow_color = Color(0, 0, 0, 0.4)
	box.shadow_size = 24
	box.content_margin_left = 40
	box.content_margin_right = 40
	box.content_margin_top = 26
	box.content_margin_bottom = 26
	_panel.add_theme_stylebox_override("panel", box)
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	_panel.add_child(v)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	v.add_child(header)
	var tour := UiKit.title("HOW IT WORKS", 30, Color(UiKit.ACCENT, 0.9), 0)
	tour.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(tour)
	header.add_child(beta_chip())
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(gap)
	_dots = UiKit.label("", 30, UiKit.ACCENT, 0)
	_dots.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_dots)

	var stage_box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.14, 0.2)
	sb.set_corner_radius_all(18)
	stage_box.add_theme_stylebox_override("panel", sb)
	v.add_child(stage_box)
	var holder := Control.new()
	holder.custom_minimum_size = STAGE
	holder.clip_contents = true
	stage_box.add_child(holder)
	var floor_line := ColorRect.new()
	floor_line.color = Color(1, 1, 1, 0.08)
	floor_line.position = Vector2(0, GROUND)
	floor_line.size = Vector2(STAGE.x, STAGE.y - GROUND)
	holder.add_child(floor_line)
	_stage = Control.new() # rebuilt on every page (its tweens die with it)
	_stage.size = STAGE
	holder.add_child(_stage)

	_title = UiKit.title("", 52, Color.WHITE, 8)
	v.add_child(_title)
	_body = UiKit.label("", 32, Color(1, 1, 1, 0.88), 0)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(STAGE.x, 96)
	v.add_child(_body)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 18)
	v.add_child(footer)
	var never := UiKit.button("Don't show again", UiKit.BLUE, 30, Vector2(330, 84))
	never.pressed.connect(func(): close(true))
	footer.add_child(never)
	var close_btn := UiKit.button("Close", UiKit.BLUE, 30, Vector2(200, 84))
	close_btn.pressed.connect(func(): close(false))
	footer.add_child(close_btn)
	var gap2 := Control.new()
	gap2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(gap2)
	_back = UiKit.button("Back", UiKit.BLUE, 30, Vector2(180, 84))
	_back.pressed.connect(func(): _go(page - 1))
	footer.add_child(_back)
	_next = UiKit.button("Next", UiKit.GOLD, 34, Vector2(240, 84))
	_next.pressed.connect(func():
		if page >= PAGES.size() - 1:
			close(false)
		else:
			_go(page + 1))
	footer.add_child(_next)


## The little gold "BETA" tag (also used beside the screen title).
static func beta_chip(font_size: int = 24) -> PanelContainer:
	var chip := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = UiKit.ACCENT
	s.set_corner_radius_all(10)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 2
	s.content_margin_bottom = 2
	chip.add_theme_stylebox_override("panel", s)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(UiKit.title("BETA", font_size, UiKit.TEXT_ON_ACCENT, 0))
	return chip


func open(start_page: int = 0) -> void:
	shown_this_session = true
	_pick_cast()
	visible = true
	_go(start_page)
	_place.call_deferred()
	Sfx.play("ui_pop")


## dont_show_again: stays closed for good (Settings can bring it back).
func close(dont_show_again: bool = false) -> void:
	if not visible:
		return
	if dont_show_again and not Economy.tips_seen.has(DISMISS_ID):
		Economy.tips_seen.append(DISMISS_ID)
		Economy.save_profile()
	visible = false
	_new_stage() # stops the page's loop along with its actors
	closed.emit()


var _nav_frame := -1


func _input(event: InputEvent) -> void:
	if not visible or event.is_echo():
		return
	if event.is_action_type() and Engine.get_process_frames() == _nav_frame:
		return # one step per key press, even if it arrives twice
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause") \
			or event.is_action_pressed("ui_right") or event.is_action_pressed("ui_left"):
		_nav_frame = Engine.get_process_frames()
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		close(false)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_next.pressed.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left") and page > 0:
		_go(page - 1)
		get_viewport().set_input_as_handled()


func _place() -> void:
	_panel.reset_size()
	await get_tree().process_frame
	_panel.reset_size()
	_panel.position = ((size - _panel.size) * 0.5).round()
	_panel.pivot_offset = _panel.size * 0.5
	_panel.scale = Vector2.ONE * 0.85
	_panel.modulate.a = 0.0
	var t := _panel.create_tween().set_parallel(true)
	t.tween_property(_panel, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_panel, "modulate:a", 1.0, 0.15)


func _pick_cast() -> void:
	_cast.clear()
	_cast.append(Economy.equipped_character)
	for c in Economy.sprite_characters():
		if not _cast.has(c.id):
			_cast.append(c.id)
	while _cast.size() < 4: # never short of actors
		_cast.append(_cast[_cast.size() % maxi(_cast.size(), 1)])


func _go(p: int) -> void:
	page = clampi(p, 0, PAGES.size() - 1)
	_title.text = PAGES[page].title
	_body.text = PAGES[page].body
	_dots.text = "%d / %d" % [page + 1, PAGES.size()]
	_back.disabled = page == 0
	_next.text = "Got it!" if page == PAGES.size() - 1 else "Next"
	_new_stage()
	match page:
		0: _act_beta()
		1: _act_copy()
		2: _act_paste()
		3: _act_levels()
		4: _act_play()
		5: _act_records()


## A fresh, empty stage: the old page's actors, props and loop (its tween is
## bound to the stage) all go with it.
func _new_stage() -> void:
	var old := _stage
	_stage = Control.new()
	_stage.size = STAGE
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	old.get_parent().add_child(_stage)
	old.queue_free()


# --- The little plays -------------------------------------------------------------

func _actor(cast_i: int, x: float) -> SpriteActor:
	var a := SpriteActor.of(_cast[cast_i], ACTOR_H)
	a.position = Vector2(x, GROUND)
	_stage.add_child(a)
	return a


func _prop(kind: String, text: String, color: Color, pos: Vector2, prop_size: Vector2 = Vector2.ZERO) -> Prop:
	var p := Prop.new()
	p.kind = kind
	p.text = text
	p.color = color
	if prop_size != Vector2.ZERO:
		p.size = prop_size
	p.position = pos
	p.pivot_offset = p.size * 0.5
	_stage.add_child(p)
	return p


## Where a paper sits when a character carries it over their head.
func _carry(x: float) -> Vector2:
	return Vector2(x - 42.0, GROUND - ACTOR_H - 118.0)


func _loop() -> Tween:
	return _stage.create_tween().set_loops()


## Beta: you copy and paste for now; the file can't come in yet.
func _act_beta() -> void:
	var me := _actor(0, 250)
	var friend := _actor(1, 820)
	var paper := _prop("doc", "PASTE", UiKit.BLUE, _carry(250))
	_prop("pill", "BETA", UiKit.ACCENT, Vector2(445, 60), Vector2(200, 76))
	var file := _prop("doc", "FILE", GREY, Vector2(615, GROUND - 110))
	var soon := _prop("pill", "SOON", GREY, Vector2(585, GROUND - 168), Vector2(150, 50))
	var t := _loop()
	t.tween_callback(func():
		soon.scale = Vector2.ZERO
		friend.play("idle"))
	t.tween_interval(0.5)
	t.tween_callback(me.cheer.bind(1.4))
	t.tween_property(paper, "position:y", paper.position.y - 26, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(paper, "position:y", paper.position.y, 0.25).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.7)
	# The file tries to come in... and can't, yet.
	t.tween_property(file, "rotation", 0.25, 0.08)
	t.tween_property(file, "rotation", -0.25, 0.12)
	t.tween_property(file, "rotation", 0.0, 0.08)
	t.tween_property(soon, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_callback(friend.cheer.bind(1.0))
	t.tween_interval(1.8)


## Step 1: the prompt goes from the game to the AI chat.
func _act_copy() -> void:
	var quiz := _prop("quiz", "", UiKit.ACCENT, Vector2(40, 110), Vector2(200, 160))
	var ai := _prop("ai", "AI chat", UiKit.BLUE, Vector2(860, 90), Vector2(190, 140))
	var me := _actor(0, 320)
	var paper := _prop("doc", "PROMPT", UiKit.ACCENT, Vector2(98, 80))
	var t := _loop()
	t.tween_callback(func():
		me.position.x = 320
		me.modulate.a = 1.0
		me.play("idle")
		paper.position = Vector2(98, 80)
		paper.scale = Vector2.ZERO
		paper.visible = true)
	t.tween_property(quiz, "scale", Vector2(1.08, 1.08), 0.12)
	t.tween_property(quiz, "scale", Vector2.ONE, 0.15)
	t.tween_property(paper, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.25)
	t.tween_property(paper, "position", _carry(320), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_callback(me.play.bind("run"))
	t.tween_property(me, "position:x", 740.0, 1.6)
	t.parallel().tween_property(paper, "position:x", _carry(740).x, 1.6)
	t.tween_callback(me.play.bind("idle"))
	t.tween_property(paper, "position", ai.position + Vector2(52, 20), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(paper, "scale", Vector2(0.3, 0.3), 0.35)
	t.tween_callback(func():
		paper.visible = false
		me.cheer(1.3))
	t.tween_property(ai, "scale", Vector2(1.12, 1.12), 0.12)
	t.tween_property(ai, "scale", Vector2.ONE, 0.2)
	t.tween_interval(1.4)
	t.tween_property(me, "modulate:a", 0.0, 0.25)


## Step 2: the AI's quiz comes back and the game checks it.
func _act_paste() -> void:
	var quiz := _prop("quiz", "", UiKit.ACCENT, Vector2(40, 110), Vector2(200, 160))
	var ai := _prop("ai", "AI chat", UiKit.BLUE, Vector2(860, 90), Vector2(190, 140))
	var friend := _actor(1, 760)
	var paper := _prop("doc", "QUIZ", GREEN, ai.position + Vector2(52, 20))
	var t := _loop()
	t.tween_callback(func():
		friend.position.x = 760
		friend.modulate.a = 1.0
		friend.play("idle")
		quiz.checked = false
		paper.position = ai.position + Vector2(52, 20)
		paper.scale = Vector2.ZERO
		paper.visible = true)
	t.tween_property(ai, "scale", Vector2(1.1, 1.1), 0.12)
	t.tween_property(ai, "scale", Vector2.ONE, 0.15)
	t.tween_property(paper, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(paper, "position", _carry(760), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_callback(friend.play.bind("run"))
	t.tween_property(friend, "position:x", 330.0, 1.6)
	t.parallel().tween_property(paper, "position:x", _carry(330).x, 1.6)
	t.tween_callback(friend.play.bind("idle"))
	t.tween_property(paper, "position", quiz.position + Vector2(58, 30), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(paper, "scale", Vector2(0.3, 0.3), 0.35)
	t.tween_callback(func():
		paper.visible = false
		quiz.checked = true
		friend.cheer(1.6)
		Sfx.play("ui_equip"))
	t.tween_property(quiz, "scale", Vector2(1.12, 1.12), 0.12)
	t.tween_property(quiz, "scale", Vector2.ONE, 0.2)
	t.tween_interval(1.7)
	t.tween_property(friend, "modulate:a", 0.0, 0.25)


## Levels: easy first, then medium, then hard, like a staircase.
func _act_levels() -> void:
	var me := _actor(0, 130)
	var friend := _actor(1, 960)
	var cards: Array[Prop] = [
		_prop("pill", "EASY", GREEN, Vector2(210, 150), Vector2(170, 66)),
		_prop("pill", "MEDIUM", YELLOW, Vector2(430, 105), Vector2(200, 66)),
		_prop("pill", "HARD", RED, Vector2(670, 60), Vector2(170, 66)),
	]
	var t := _loop()
	t.tween_callback(func():
		me.position.x = 130
		me.play("idle")
		for c in cards:
			c.scale = Vector2.ZERO)
	t.tween_interval(0.3)
	for c in cards:
		t.tween_property(c, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_callback(me.play.bind("run"))
		t.tween_property(me, "position:x", c.position.x + c.size.x * 0.5, 0.55)
		t.tween_callback(me.cheer.bind(0.5))
		t.tween_property(c, "scale", Vector2(1.12, 1.12), 0.1)
		t.tween_property(c, "scale", Vector2.ONE, 0.15)
		t.tween_interval(0.3)
	t.tween_callback(friend.cheer.bind(1.2))
	t.tween_interval(1.4)


## Play alone, or host: the class runs in with the code.
func _act_play() -> void:
	var play := _prop("pill", "PLAY", UiKit.ACCENT, Vector2(150, 50), Vector2(220, 76))
	var host := _prop("pill", "HOST CLASS", UiKit.BLUE, Vector2(520, 50), Vector2(300, 76))
	var code := _prop("pill", "CODE  7XK2", GREY, Vector2(840, 62), Vector2(230, 52))
	var me := _actor(0, 260)
	var teacher := _actor(1, 600)
	var kid1 := _actor(2, 1180)
	var kid2 := _actor(3, 1260)
	var t := _loop()
	t.tween_callback(func():
		code.scale = Vector2.ZERO
		kid1.position.x = 1180
		kid2.position.x = 1260
		kid1.play("idle")
		kid2.play("idle")
		me.play("idle"))
	t.tween_property(play, "scale", Vector2(1.12, 1.12), 0.12)
	t.tween_property(play, "scale", Vector2.ONE, 0.18)
	t.tween_callback(me.cheer.bind(1.4))
	t.tween_interval(0.6)
	t.tween_property(host, "scale", Vector2(1.12, 1.12), 0.12)
	t.tween_property(host, "scale", Vector2.ONE, 0.18)
	t.tween_property(code, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_callback(func():
		teacher.cheer(0.8)
		kid1.play("run")
		kid2.play("run"))
	t.tween_property(kid1, "position:x", 800.0, 1.1)
	t.parallel().tween_property(kid2, "position:x", 930.0, 1.3)
	t.tween_callback(func():
		kid1.cheer(1.6)
		kid2.cheer(1.6))
	t.tween_interval(1.9)


## No bottlecaps here; every finished game goes into Records.
func _act_records() -> void:
	var caps := _prop("pill", "+0 CAPS", GREY, Vector2(130, 60), Vector2(230, 64))
	var rec := _prop("pill", "RECORDS", UiKit.BLUE, Vector2(520, 50), Vector2(240, 76))
	var sheet := _prop("doc", "1,240", UiKit.ACCENT, Vector2(860, GROUND - 110))
	var me := _actor(0, 300)
	var t := _loop()
	t.tween_callback(func():
		sheet.scale = Vector2.ZERO
		me.play("idle"))
	t.tween_property(caps, "scale", Vector2(1.15, 1.15), 0.15)
	t.tween_property(caps, "scale", Vector2.ONE, 0.2)
	t.tween_interval(0.6)
	t.tween_property(rec, "scale", Vector2(1.12, 1.12), 0.12)
	t.tween_property(rec, "scale", Vector2.ONE, 0.18)
	t.tween_property(sheet, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_callback(me.cheer.bind(1.4))
	t.tween_interval(1.8)


# --- Props: papers, the AI chat, the quiz box, labels -----------------------------

class Prop:
	extends Control
	var kind := "doc"
	var text := ""
	var color := Color.WHITE
	var checked := false:
		set(v):
			checked = v
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size = Vector2(84, 104)

	func _draw() -> void:
		var font := UiKit.title_font()
		match kind:
			"doc": _paper(font)
			"ai": _chat(font)
			"quiz": _quiz(font)
			_: _pill(font)

	## A sheet of paper: folded corner, text lines, a coloured tag.
	func _paper(font: Font) -> void:
		var w := size.x
		var h := size.y
		var fold := 22.0
		var paper := PackedVector2Array([Vector2(0, 0), Vector2(w - fold, 0), Vector2(w, fold), Vector2(w, h), Vector2(0, h)])
		draw_colored_polygon(paper, Color(0.96, 0.95, 0.9))
		draw_colored_polygon(PackedVector2Array([Vector2(w - fold, 0), Vector2(w - fold, fold), Vector2(w, fold)]), Color(0.78, 0.77, 0.72))
		var outline := paper.duplicate()
		outline.append(Vector2.ZERO)
		draw_polyline(outline, Color(0, 0, 0, 0.35), 2.0)
		for i in 3:
			var y := 22.0 + i * 13.0
			draw_line(Vector2(12, y), Vector2(w - (28 if i == 0 else 12), y), Color(0.55, 0.56, 0.6), 4.0)
		var tag := Rect2(6, h - 34, w - 12, 26)
		draw_style_box(_round(color, 8), tag)
		draw_string(font, Vector2(tag.position.x, tag.position.y + 20), text, HORIZONTAL_ALIGNMENT_CENTER, tag.size.x, 17, UiKit.TEXT_ON_ACCENT)

	## A chat bubble with a little tail.
	func _chat(font: Font) -> void:
		var body := Rect2(0, 0, size.x, size.y - 26)
		draw_style_box(_round(Color(0.12, 0.2, 0.28), 26, color), body)
		draw_colored_polygon(PackedVector2Array([Vector2(34, body.end.y - 2), Vector2(70, body.end.y - 2), Vector2(26, size.y)]), Color(0.12, 0.2, 0.28))
		draw_string(font, Vector2(0, 58), "AI", HORIZONTAL_ALIGNMENT_CENTER, size.x, 46, Color.WHITE)
		draw_string(font, Vector2(0, 92), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, Color(1, 1, 1, 0.7))

	## The game's own quiz box; a green tick once the questions are in.
	func _quiz(font: Font) -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(_round(Color(0.03, 0.04, 0.07, 0.9), 16, Color(0.4, 0.4, 0.42)), r)
		draw_rect(Rect2(14, 4, size.x - 28, 5), color)
		draw_string(font, Vector2(0, 40), "Custom quiz", HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, Color.WHITE)
		for i in 4:
			var y := 62.0 + i * 20.0
			draw_line(Vector2(22, y), Vector2(size.x - (60 if i % 2 else 30), y), Color(1, 1, 1, 0.25), 5.0)
		if checked:
			var c := Vector2(size.x - 34, size.y - 30)
			draw_circle(c, 26, GREEN)
			draw_polyline(PackedVector2Array([c + Vector2(-12, 0), c + Vector2(-3, 10), c + Vector2(13, -10)]), Color.WHITE, 6.0)
			draw_string(font, Vector2(14, size.y - 18), "15 ready", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, GREEN)

	## A rounded label, like the game's buttons and tags.
	func _pill(font: Font) -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(_round(color, int(size.y * 0.3)), r)
		var fs := int(size.y * 0.5)
		draw_string(font, Vector2(0, size.y * 0.5 + fs * 0.36), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, UiKit.TEXT_ON_ACCENT)

	static func _round(fill: Color, radius: int, border: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = fill
		s.set_corner_radius_all(radius)
		if border.a > 0.0:
			s.border_color = border
			s.set_border_width_all(3)
		return s
