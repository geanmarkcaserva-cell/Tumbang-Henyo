extends Node
## Loads every question CSV in res://data/questions/ and hands out
## questions by theme and tier, without repeats inside a run.
##
## CSV columns: id,theme,tier,question,choice_a,choice_b,choice_c,answer,explanation
## answer is a, b or c.

const QUESTIONS_DIR := "res://data/questions/"
const ANSWER_LETTERS := "abc"

var _by_theme := {} # theme id -> Array of question dictionaries
var _used := {} # question id -> true, for the current run


func _ready() -> void:
	_load_all()


## Call when a new run starts so questions can repeat across runs.
func reset_run() -> void:
	_used.clear()


func get_themes() -> Array:
	return _by_theme.keys()


## Returns {id, theme, tier, question, choices: [a, b, c], answer: 0-2, explanation}
## or an empty dictionary when the theme has no questions.
func next_question(theme: String, tier: String = "") -> Dictionary:
	var pool: Array = _by_theme.get(theme, [])
	var candidates := pool.filter(func(q): return not _used.has(q.id) and (tier == "" or q.tier == tier))
	if candidates.is_empty():
		# Every matching question was used this run: allow repeats again.
		for q in pool:
			_used.erase(q.id)
		candidates = pool.filter(func(q): return tier == "" or q.tier == tier)
	if candidates.is_empty():
		return {}
	var question: Dictionary = candidates.pick_random()
	_used[question.id] = true
	return question


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
