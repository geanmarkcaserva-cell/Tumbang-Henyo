extends Node
## Loads every question CSV in res://data/questions/ and hands out
## questions by theme and tier, going through the whole bank before repeating.
##
## CSV columns: id,theme,tier,question,choice_a,choice_b,choice_c,answer,explanation
## answer is a, b or c.

const QUESTIONS_DIR := "res://data/questions/"
const ANSWER_LETTERS := "abc"

const TIERS := ["easy", "medium", "hard"]
const SEEN_PATH := "user://quiz_seen.cfg"

var _by_theme := {} # theme id -> Array of question dictionaries
## Question id -> true once asked. Kept across runs (and saved) so a theme's
## whole bank is gone through before any question comes back.
var _used := {}


func _ready() -> void:
	_load_all()
	_load_seen()


## Call when a new run starts. Questions already seen stay seen, so the next
## run carries on through the bank. A class game (fresh = true) starts clean so
## every player's shared seed gives the same questions.
func reset_run(fresh: bool = false) -> void:
	if fresh:
		_used.clear()


## Tier for a round: easy early on, then medium, then hard.
func tier_for_round(round_number: int) -> String:
	if round_number <= 5:
		return "easy"
	if round_number <= 10:
		return "medium"
	return "hard"


func get_themes() -> Array:
	return _by_theme.keys()


## Custom mode: replace the questions of a player-made set (see CustomQuiz).
func set_custom_questions(theme: String, questions: Array) -> void:
	_by_theme[theme] = questions


## Every question of a theme (e.g. to send a custom set to a class lobby).
func questions_of(theme: String) -> Array:
	return _by_theme.get(theme, []).duplicate(true)


## A random fact for the loading screen, taken from a question's explanation.
func random_tip(theme: String) -> String:
	var pool: Array = _by_theme.get(theme, []).filter(func(q): return q.explanation != "")
	if pool.is_empty():
		return ""
	return pool.pick_random().explanation


## Returns {id, theme, tier, question, choices: [a, b, c], answer: 0-2, explanation}
## or an empty dictionary when the theme has no questions.
func next_question(theme: String, tier: String = "") -> Dictionary:
	var pool: Array = _by_theme.get(theme, [])
	if pool.is_empty():
		return {}
	var unused := pool.filter(func(q): return not _used.has(q.id))
	if unused.is_empty():
		# The whole bank has been asked: start it over.
		for q in pool:
			_used.erase(q.id)
		unused = pool.duplicate()
	# The asked tier first, then the nearest one that still has new questions.
	var candidates: Array = []
	var want := TIERS.find(tier)
	if want < 0:
		candidates = unused
	else:
		for step in TIERS.size():
			for t in [want - step, want + step]:
				if t >= 0 and t < TIERS.size() and candidates.is_empty():
					candidates = unused.filter(func(q): return q.tier == TIERS[t])
			if not candidates.is_empty():
				break
		if candidates.is_empty():
			candidates = unused
	var question: Dictionary = candidates.pick_random()
	_used[question.id] = true
	_save_seen()
	return question


func _load_seen() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SEEN_PATH) != OK:
		return
	for id in cfg.get_value("quiz", "seen", PackedStringArray()):
		_used[id] = true


func _save_seen() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("quiz", "seen", PackedStringArray(_used.keys()))
	cfg.save(SEEN_PATH)


func _load_all() -> void:
	var dir := DirAccess.open(QUESTIONS_DIR)
	if dir == null:
		push_error("QuizDatabase: cannot open %s" % QUESTIONS_DIR)
		return
	for file_name in dir.get_files():
		if file_name.ends_with(".csv"):
			_load_csv(QUESTIONS_DIR + file_name)
	for theme in _by_theme:
		print("QuizDatabase: %d questions in '%s'" % [_by_theme[theme].size(), theme])


func _load_csv(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("QuizDatabase: cannot read %s" % path)
		return
	var header := file.get_csv_line()
	var line_number := 1
	while not file.eof_reached():
		var row := file.get_csv_line()
		line_number += 1
		if row.size() < header.size():
			continue # blank or short line
		var rec := {}
		for i in header.size():
			rec[header[i].strip_edges()] = row[i].strip_edges()
		var answer_index := ANSWER_LETTERS.find(String(rec.get("answer", "")).to_lower())
		if answer_index < 0:
			push_warning("QuizDatabase: %s line %d has no valid answer (a, b or c)" % [path, line_number])
			continue
		var question := {
			"id": rec.get("id", "%s:%d" % [path, line_number]),
			"theme": rec.get("theme", ""),
			"tier": rec.get("tier", "easy"),
			"question": rec.get("question", ""),
			"choices": [rec.get("choice_a", ""), rec.get("choice_b", ""), rec.get("choice_c", "")],
			"answer": answer_index,
			"explanation": rec.get("explanation", ""),
		}
		if not _by_theme.has(question.theme):
			_by_theme[question.theme] = []
		_by_theme[question.theme].append(question)
