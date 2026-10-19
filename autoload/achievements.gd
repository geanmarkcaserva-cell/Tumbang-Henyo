extends CanvasLayer
## Achievements: the list, what's unlocked (saved in user://achievements.cfg),
## running totals for the "do X times" ones, and the Steam-style popup that
## slides in at the bottom right with a trophy when one unlocks.
##
## Unlock from anywhere: Achievements.unlock("bullseye").
## Count towards one: Achievements.add_stat("correct_total").

signal unlocked(id: String)

const SAVE_PATH := "user://achievements.cfg"
## Testing: wipe every achievement each time the game starts, so they can
## all be earned again. Set to false for release.
const RESET_ON_LAUNCH := true
const SHOW_TIME := 4.2 ## seconds each popup stays up
const SLIDE_TIME := 0.35
const CHIME_PATH := "res://art/Audio/sfx/achievement.wav"

## tier: bronze / silver / gold / platinum. secret: name and text hidden until unlocked.
## stat + goal: unlocks by itself when that running total reaches goal.
const LIST := [
	# Getting started
	{"id": "first_steps", "name": "First Steps", "desc": "Finish the tutorial.", "tier": "bronze"},
	{"id": "tama", "name": "Tama!", "desc": "Answer your first question right.", "tier": "bronze"},
	{"id": "tumba", "name": "Tumba!", "desc": "Knock down the lata.", "tier": "bronze"},
	{"id": "takbo", "name": "Takbo!", "desc": "Clear your first round.", "tier": "bronze"},
	{"id": "regular", "name": "Suki", "desc": "Play 10 runs.", "tier": "bronze", "stat": "runs", "goal": 10},
	# Quiz skill
	{"id": "speed_reader", "name": "Speed Reader", "desc": "Answer right with 12 seconds or more left.", "tier": "bronze"},
	{"id": "henyo", "name": "Henyo", "desc": "Answer 10 questions in a row right in one run.", "tier": "silver"},
	{"id": "scholar", "name": "Scholar", "desc": "Answer 100 questions right.", "tier": "platinum", "stat": "correct_total", "goal": 100},
	# Throwing
	{"id": "bullseye", "name": "Bullseye!", "desc": "Land a perfect, clean hit on the lata.", "tier": "silver"},
	{"id": "sharpshooter", "name": "Sharpshooter", "desc": "Land 5 bullseyes in one run.", "tier": "gold"},
	{"id": "ten_hit_wonder", "name": "10 Hit Wonder", "desc": "Land 10 bullseyes in one run.", "tier": "platinum"},
	{"id": "windy", "name": "Against the Wind", "desc": "Knock down the lata in strong wind.", "tier": "silver"},
	# Running
	{"id": "flawless", "name": "Walang Mintis", "desc": "Clear a round with no wrong answer, no miss and no hit.", "tier": "silver"},
	{"id": "untouchable", "name": "Untouchable", "desc": "Clear a round against 3 or more tayas without a tsinelas hitting you.", "tier": "silver"},
	{"id": "elite", "name": "Elite Escape", "desc": "Clear a round with an elite taya on the court.", "tier": "silver"},
	{"id": "last_breath", "name": "Last Breath", "desc": "Clear a round with 15 Awra or less.", "tier": "silver"},
	# Story
	{"id": "mamas_home", "name": "Mama's Home", "desc": "Stay out until 6:00 PM.", "tier": "gold", "secret": true},
	{"id": "nakauwi", "name": "Nakauwi Na!", "desc": "Make it home before Mama catches you.", "tier": "gold", "secret": true},
	{"id": "hanger_dodger", "name": "Hanger Dodger", "desc": "Get home without a hanger or walis hitting you.", "tier": "platinum", "secret": true},
	# Score and shop
	{"id": "big_score", "name": "High Scorer", "desc": "Score 10,000 points in one run.", "tier": "gold"},
	{"id": "legend", "name": "Alamat", "desc": "Score 15,000 points in one run.", "tier": "platinum"},
	{"id": "collector", "name": "Tansan Collector", "desc": "Have 1,000 tansan.", "tier": "platinum"},
	{"id": "shopper", "name": "Suki ng Tindahan", "desc": "Buy something from the shop.", "tier": "bronze"},
	# Class and teacher
	{"id": "quiz_maker", "name": "Quiz Maker", "desc": "Save your own custom quiz.", "tier": "bronze"},
	{"id": "classmate", "name": "Classmate", "desc": "Join a class game.", "tier": "bronze"},
	{"id": "teacher", "name": "Guro", "desc": "Host a class game.", "tier": "silver"},
	{"id": "class_champ", "name": "Class Champion", "desc": "Finish first in a class game.", "tier": "gold"},
]

## True during the tutorial's practice round: nothing unlocks and no totals
## count, so achievements are only earned in real play.
var paused := false

var _unlocked := {} ## id -> unix time
var _stats := {} ## stat name -> running total
var _queue: Array = []
var _showing := false

var _toast: PanelContainer
var _toast_icon: TrophyIcon
var _toast_name: Label
var _toast_desc: Label
var _toast_head: Label
var _chime: AudioStreamPlayer


func _ready() -> void:
	layer = 110 # over everything, fades included
	process_mode = Node.PROCESS_MODE_ALWAYS
	if RESET_ON_LAUNCH:
		reset_all()
	else:
		_load()
	_build_toast()
	_chime = AudioStreamPlayer.new()
	_chime.stream = load(CHIME_PATH)
	_chime.bus = &"SFX"
	_chime.volume_db = -2.0
	add_child(_chime)


# --- Public ---------------------------------------------------------------------

func unlock(id: String) -> void:
	if paused or _unlocked.has(id) or find(id).is_empty():
		return
	_unlocked[id] = int(Time.get_unix_time_from_system())
	_save()
	unlocked.emit(id)
	_queue.append(id)
	if not _showing:
		_show_next()


func is_unlocked(id: String) -> bool:
	return _unlocked.has(id)


## Add to a running total (e.g. "runs", "correct_total") and unlock whatever
## reaches its goal.
func add_stat(stat_id: String, amount: int = 1) -> void:
	if paused:
		return
	_stats[stat_id] = int(_stats.get(stat_id, 0)) + amount
	_save()
	for a in LIST:
		if a.get("stat", "") == stat_id and int(_stats[stat_id]) >= int(a.goal):
			unlock(a.id)


func get_stat(stat_id: String) -> int:
	return int(_stats.get(stat_id, 0))


func find(id: String) -> Dictionary:
	for a in LIST:
		if a.id == id:
			return a
	return {}


func unlocked_count() -> int:
	return _unlocked.size()


## When it was unlocked (unix seconds), 0 if not.
func unlocked_at(id: String) -> int:
	return int(_unlocked.get(id, 0))


# --- Popup ------------------------------------------------------------------------

func _show_next() -> void:
	if _queue.is_empty():
		_showing = false
		return
	_showing = true
	var a := find(_queue.pop_front())
	_toast_icon.tier = a.tier
	var tier_col: Color = TrophyIcon.TIERS[a.tier]
	(_toast.get_theme_stylebox("panel") as StyleBoxFlat).border_color = Color(tier_col, 0.9)
	_toast_head.add_theme_color_override("font_color", tier_col)
	_toast_name.text = a.name
	_toast_desc.text = a.desc
	_toast_head.text = "ACHIEVEMENT UNLOCKED"
	_place_toast()
	_chime.play()
	var vp := get_viewport().get_visible_rect().size
	var shown_y := _toast.position.y
	var hidden_y := vp.y + 20.0 if not _top() else -_toast.size.y - 20.0
	_toast.position.y = hidden_y
	_toast.visible = true
	_toast.modulate.a = 1.0
	var t := create_tween().set_ignore_time_scale(true)
	t.tween_property(_toast, "position:y", shown_y, SLIDE_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(_toast_icon, "scale", Vector2.ONE * 1.18, 0.18).set_delay(0.2)
	t.tween_property(_toast_icon, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)
	t.tween_interval(SHOW_TIME)
	t.tween_property(_toast, "position:y", hidden_y, SLIDE_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_callback(func():
		_toast.visible = false
		_show_next())


## Phones (touch controls on): top centre, clear of the thumb buttons.
## PC: bottom right, like Steam.
func _top() -> bool:
	return Settings.touch_controls


func _place_toast() -> void:
	var vp := get_viewport().get_visible_rect().size
	_toast.reset_size()
	var sz := _toast.size
	if _top():
		_toast.position = Vector2((vp.x - sz.x) * 0.5, 24.0)
	else:
		_toast.position = Vector2(vp.x - sz.x - 28.0, vp.y - sz.y - 28.0)


func _build_toast() -> void:
	_toast = PanelContainer.new()
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.07, 0.09, 0.13, 0.96)
	s.border_color = Color(1, 1, 1, 0.08)
	s.set_border_width_all(1)
	s.border_width_left = 6
	s.border_color = Color(1.0, 0.8, 0.3, 0.9)
	s.set_corner_radius_all(14)
	s.content_margin_left = 18
	s.content_margin_right = 26
	s.content_margin_top = 14
	s.content_margin_bottom = 14
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 18
	_toast.add_theme_stylebox_override("panel", s)
	_toast.custom_minimum_size = Vector2(560, 0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.add_child(row)
	_toast_icon = TrophyIcon.new()
	_toast_icon.custom_minimum_size = Vector2(96, 96)
	_toast_icon.pivot_offset = Vector2(48, 48)
	_toast_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_toast_icon)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.custom_minimum_size = Vector2(400, 0)
	row.add_child(col)
	_toast_head = UiKit.label("ACHIEVEMENT UNLOCKED", 18, Color(1.0, 0.8, 0.3), 0)
	_toast_head.add_theme_font_override("font", UiKit.key_font())
	col.add_child(_toast_head)
	_toast_name = UiKit.title("", 38, Color.WHITE, 6)
	col.add_child(_toast_name)
	_toast_desc = UiKit.label("", 22, Color(1, 1, 1, 0.7), 0)
	_toast_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_desc.custom_minimum_size = Vector2(400, 0)
	col.add_child(_toast_desc)
	_toast.visible = false
	add_child(_toast)


# --- Save -------------------------------------------------------------------------

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	_unlocked = cfg.get_value("achievements", "unlocked", {})
	_stats = cfg.get_value("achievements", "stats", {})


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("achievements", "unlocked", _unlocked)
	cfg.set_value("achievements", "stats", _stats)
	cfg.save(SAVE_PATH)


## Debug: clear everything (call from the editor's runtime tools).
func reset_all() -> void:
	_unlocked.clear()
	_stats.clear()
	_save()
