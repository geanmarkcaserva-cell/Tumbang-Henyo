class_name CustomQuiz
extends RefCounted
## Custom mode: players bring their own questions and answer keys.
## Works fully offline, on PC and Android. Sets are saved in user://custom_sets/.
##
## Accepted input (typed, pasted, or opened from a .txt / .csv / .docx file):
##
##   1. Sino ang pambansang bayani ng Pilipinas?
##   a) Jose Rizal *
##   b) Andres Bonifacio
##   c) Apolinario Mabini
##   Why: Optional explanation shown after answering.
##
##   2. Ano ang kabisera ng Pilipinas?
##   Answer: Maynila
##
## - A new question starts at a numbered line ("1." / "1)"), a "Q:" line, or
##   after a blank line.
## - Mark the right choice with * (or "(correct)"), or add "Answer: b".
## - No choices, just "Answer: <text>"? The game makes the two wrong
##   choices from the other questions' answers (identification style).
## - More than 3 choices: the right one plus 2 random wrong ones are used.
## - CSV with the game's own columns (question, choice_a, choice_b, choice_c,
##   answer, explanation) also works, e.g. exported from Google Sheets.

const DIR := "user://custom_sets/"
const THEME_PREFIX := "custom:"
const CHOICES := 3

const HELP := """Paste or type your questions. Example:

1. Sino ang pambansang bayani ng Pilipinas?
a) Jose Rizal *
b) Andres Bonifacio
c) Apolinario Mabini
Why: (optional) explanation after answering

2. Ano ang kabisera ng Pilipinas?
Answer: Maynila

3. Saang probinsya ang Bulkang Mayon?
Answer: Albay

- Put * after the right choice, or write  Answer: b
- Only an answer, no choices? The game makes the wrong
  choices from your other answers.
- You can also open a .txt, .csv or Word (.docx) file."""

## For the AI PROMPT button: the player pastes this into ChatGPT, Claude,
## Gemini etc. together with their notes, then pastes the answer back here.
const AI_PROMPT := """Make a quiz for a school game from my notes below.

Rules:
- Write 15 multiple-choice questions. Use only facts from my notes.
- Use the same language as my notes (Filipino, English or Taglish).
- Each question has exactly 3 choices: a), b) and c). Exactly one is correct.
- Put an asterisk * right after the correct choice.
- Add a line starting with "Why:" that explains the answer in one short sentence.
- Keep each question under 25 words and each choice under 8 words.
- Wrong choices must be believable. No "all of the above" or "none of the above".
- Mix which letter is correct.
- Number the questions and leave one blank line between them.
- Reply with ONLY the questions in plain text: no title, no intro, no bold, no markdown.

Format example:
1. Sino ang pambansang bayani ng Pilipinas?
a) Jose Rizal *
b) Andres Bonifacio
c) Apolinario Mabini
Why: Si Rizal ang itinanghal na pambansang bayani dahil sa kanyang mga akda.

My notes:
[paste your notes or lesson here, or attach the file]"""

static var _choice_re := RegEx.create_from_string("^\\(?([a-dA-D])[\\).:]\\s*(.+)$")
static var _number_re := RegEx.create_from_string("^(?:[Qq](?:uestion)?\\s*\\d*\\s*[:.)]|\\d+\\s*[.)])\\s*(.*)$")
static var _key_re := RegEx.create_from_string("^(?i)(correct answer|correct|answer key|answer|ans|sagot|tamang sagot|key|why|explanation|paliwanag|reason|rationale)\\s*[:\\-]\\s*(.*)$")
## Markdown escapes from chat "copy" buttons: 1\\.  \\*  a\\)  ->  1.  *  a)
static var _escape_re := RegEx.create_from_string("\\\\([\\\\`*_{}\\[\\]()#+\\-.!|>~])")
## Choices squashed onto the question's line: "...? a) X b) Y * c) Z Why: ..."
static var _inline_paren_re := RegEx.create_from_string("\\s+(?=\\(?[a-dA-D]\\)\\s)")
static var _inline_dot_re := RegEx.create_from_string("\\s+(?=[a-dA-D]\\.\\s)")
static var _inline_key_re := RegEx.create_from_string("(?i)\\s+(?=(?:why|answer|correct answer|sagot|explanation|paliwanag)\\s*:)")


# --- Parsing ------------------------------------------------------------------

## Returns {questions: Array, errors: Array[String]}. Questions use the same
## shape as QuizDatabase: {id, theme, tier, question, choices, answer, explanation}.
static func parse(text: String, theme_id: String = "custom:preview") -> Dictionary:
	text = _clean_ai_text(text.replace("\r\n", "\n").replace("\r", "\n"))
	if _looks_like_csv(text):
		return _parse_csv(text, theme_id)
	var errors: Array[String] = []
	var blocks := _split_blocks(text)
	var raw: Array = []
	for b in blocks:
		var q := _parse_block(b.lines)
		q.line = b.line
		raw.append(q)
	# All typed answers, for making wrong choices in identification questions.
	var answer_pool: Array[String] = []
	for q in raw:
		if q.answer_text != "" and not answer_pool.has(q.answer_text):
			answer_pool.append(q.answer_text)
	var questions: Array = []
	for q in raw:
		if _is_chatter(q):
			continue # "Here is your quiz!" and similar lines from AI chats
		var built := _finish(q, answer_pool)
		if built.has("error"):
			errors.append("Question near line %d: %s" % [q.line, built.error])
			continue
		built.id = "%s#%d" % [theme_id, questions.size() + 1]
		built.theme = theme_id
		built.tier = "easy"
		questions.append(built)
	if questions.is_empty() and errors.is_empty():
		errors.append("No questions found yet. Tap FORMAT HELP for an example.")
	return {"questions": questions, "errors": errors}


## AI chats like to add markdown: **bold**, headings, bullets, code fences.
## Strip it so their answers paste in cleanly.
## Also undoes what chat "copy" buttons do: backslash escapes (1\. \*) and
## whole questions flattened onto one line.
static func _clean_ai_text(text: String) -> String:
	text = _escape_re.sub(text, "$1", true)
	var lines: Array[String] = []
	for raw in text.split("\n"):
		lines.append_array(_unflatten(raw))
	var out: Array[String] = []
	for raw in lines:
		var line := raw.strip_edges().replace("**", "").replace("__", "").replace("`", "")
		if line.begins_with("#"):
			line = line.lstrip("#").strip_edges()
		if line.begins_with("- ") or line.begins_with("• "):
			line = line.substr(2)
		line = line.replace("✅", "*").replace("(Correct)", "*").replace("(correct answer)", "*")
		out.append(line)
	return "\n".join(out)


static func _split_blocks(text: String) -> Array:
	var blocks: Array = []
	var current: Array[String] = []
	var start_line := 1
	var lines := text.split("\n")
	for i in lines.size():
		var line := lines[i].strip_edges()
		var starts_new := line == "" or (_number_re.search(line) != null and not current.is_empty() \
				and _choice_re.search(line) == null)
		if starts_new and not current.is_empty():
			blocks.append({"lines": current, "line": start_line})
			current = []
		if line != "":
			if current.is_empty():
				start_line = i + 1
			current.append(line)
	if not current.is_empty():
		blocks.append({"lines": current, "line": start_line})
	return blocks


static func _parse_block(lines: Array[String]) -> Dictionary:
	var q := {"question": "", "choices": [], "correct": -1, "answer_key": "", "answer_text": "",
			"explanation": "", "numbered": _number_re.search(lines[0]) != null}
	for line in lines:
		var key := _key_re.search(line)
		if key:
			var k := key.get_string(1).to_lower()
			var value := key.get_string(2).strip_edges()
			if k in ["why", "explanation", "paliwanag", "reason"]:
				q.explanation = value
			else:
				q.answer_key = value
			continue
		var choice := _choice_re.search(line)
		if choice and q.question != "":
			var c := _strip_mark(choice.get_string(2))
			if c.marked:
				q.correct = q.choices.size()
			q.choices.append(c.text)
			continue
		if q.choices.is_empty():
			# Question text (may wrap over several lines).
			var num := _number_re.search(line)
			var t := num.get_string(1) if num else line
			q.question = (q.question + " " + t).strip_edges()
	# "Answer: b" -> pick that choice; "Answer: some text" -> match or identification.
	if q.answer_key != "":
		var letter: String = String(q.answer_key).to_lower().trim_suffix(")").trim_suffix(".")
		if letter.length() == 1 and "abcd".contains(letter) and "abcd".find(letter) < q.choices.size():
			q.correct = "abcd".find(letter)
		else:
			var stripped: String = _strip_mark(q.answer_key).text
			for i in q.choices.size():
				if q.choices[i].to_lower() == stripped.to_lower():
					q.correct = i
			if q.correct < 0:
				q.answer_text = stripped
	if q.correct >= 0 and q.answer_text == "":
		q.answer_text = q.choices[q.correct]
	return q


static func _strip_mark(s: String) -> Dictionary:
	var marked := false
	var t := s.strip_edges()
	for mark in ["(correct)", "(tama)", "✓", "✔", "*"]:
		if t.begins_with(mark) or t.ends_with(mark):
			marked = true
			t = t.trim_prefix(mark).trim_suffix(mark).strip_edges()
	return {"text": t, "marked": marked}


## Turn a parsed block into a 3-choice question, or {error}.
static func _finish(q: Dictionary, answer_pool: Array[String]) -> Dictionary:
	if q.question == "":
		return {"error": "no question text"}
	var choices: Array = q.choices.duplicate()
	var correct: int = q.correct
	if choices.is_empty():
		# Identification: the answer plus two other answers from the set.
		if q.answer_text == "":
			return {"error": "\"%s\" has no choices and no Answer: line" % _short(q.question)}
		var others := answer_pool.filter(func(a): return a.to_lower() != q.answer_text.to_lower())
		if others.size() < CHOICES - 1:
			return {"error": "\"%s\" needs choices, or at least 3 questions with answers in the set" % _short(q.question)}
		others.shuffle()
		choices = [q.answer_text, others[0], others[1]]
		correct = 0
	elif correct < 0:
		return {"error": "\"%s\" has no right answer marked (add * or Answer: a)" % _short(q.question)}
	if choices.size() < CHOICES:
		# Two choices given: borrow one wrong choice from the other answers.
		var fill := answer_pool.filter(func(a): return not choices.has(a))
		fill.shuffle()
		while choices.size() < CHOICES and not fill.is_empty():
			choices.append(fill.pop_back())
		if choices.size() < CHOICES:
			return {"error": "\"%s\" needs 3 choices" % _short(q.question)}
	elif choices.size() > CHOICES:
		# Keep the right one and two random wrong ones.
		var right: String = choices[correct]
		var wrong := choices.filter(func(c): return c != right)
		wrong.shuffle()
		choices = [right, wrong[0], wrong[1]]
		correct = 0
	return {"question": q.question, "choices": choices, "answer": correct, "explanation": q.explanation}


## A block with no choices and no answer that isn't numbered and isn't a
## question is just talk (intros, outros, headings) - skip it quietly.
static func _is_chatter(q: Dictionary) -> bool:
	if not q.choices.is_empty() or q.answer_key != "":
		return false
	return not q.numbered and not String(q.question).ends_with("?")


static func _short(s: String) -> String:
	return s if s.length() <= 40 else s.substr(0, 38) + "..."


static func _looks_like_csv(text: String) -> bool:
	var first := text.get_slice("\n", 0).to_lower()
	return first.contains("question") and first.contains("choice_a") and first.contains(",")


static func _parse_csv(text: String, theme_id: String) -> Dictionary:
	# Same columns as res://data/questions/*.csv; reuse the plain-text parser by
	# rewriting rows into the text format.
	var path := "user://__custom_import.csv"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	f = FileAccess.open(path, FileAccess.READ)
	var header := Array(f.get_csv_line()).map(func(h): return String(h).strip_edges().to_lower())
	var out := ""
	var n := 0
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < header.size():
			continue
		var rec := {}
		for i in header.size():
			rec[header[i]] = row[i].strip_edges()
		n += 1
		out += "%d. %s\na) %s\nb) %s\nc) %s\nAnswer: %s\n" % [n, rec.get("question", ""),
				rec.get("choice_a", ""), rec.get("choice_b", ""), rec.get("choice_c", ""), rec.get("answer", "")]
		if rec.get("explanation", "") != "":
			out += "Why: %s\n" % rec.explanation
		out += "\n"
	f.close()
	DirAccess.remove_absolute(path)
	return parse(out, theme_id)


# --- Files (.txt / .csv / .docx) ----------------------------------------------

## Read a file the player picked into plain text ("" + error message on failure).
static func read_file(path: String) -> Dictionary:
	var ext := path.get_extension().to_lower()
	if ext == "docx":
		return _read_docx(path)
	if ext in ["txt", "csv", "md", ""]:
		var text := FileAccess.get_file_as_string(path)
		if text == "" and FileAccess.get_open_error() != OK:
			return {"text": "", "error": "Couldn't open the file (%s)." % error_string(FileAccess.get_open_error())}
		return {"text": text, "error": ""}
	if ext == "pdf":
		return {"text": "", "error": "PDF can't be read yet. Copy the text from the PDF and paste it here."}
	return {"text": "", "error": "Use a .txt, .csv or Word (.docx) file."}


## A .docx is a zip; the text lives in word/document.xml, one <w:p> per paragraph.
static func _read_docx(path: String) -> Dictionary:
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		return {"text": "", "error": "Couldn't open the Word file."}
	var xml := zip.read_file("word/document.xml").get_string_from_utf8()
	zip.close()
	if xml == "":
		return {"text": "", "error": "That Word file looks empty."}
	xml = xml.replace("</w:p>", "\n").replace("<w:tab/>", " ").replace("<w:br/>", "\n")
	var text := RegEx.create_from_string("<[^>]+>").sub(xml, "", true)
	text = text.replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">") \
			.replace("&quot;", "\"").replace("&apos;", "'")
	return {"text": text, "error": ""}


# --- Saved sets ---------------------------------------------------------------

static func list_sets() -> Array:
	var sets: Array = []
	var dir := DirAccess.open(DIR)
	if dir == null:
		return sets
	for file_name in dir.get_files():
		if file_name.ends_with(".json"):
			var data := _load(file_name.get_basename())
			if not data.is_empty():
				sets.append({"id": file_name.get_basename(), "title": data.title, "count": data.count})
	sets.sort_custom(func(a, b): return a.title.naturalnocasecmp_to(b.title) < 0)
	return sets


## Save (create or overwrite). Returns the set id.
static func save_set(title: String, text: String, set_id: String = "") -> String:
	DirAccess.make_dir_recursive_absolute(DIR)
	if set_id == "":
		set_id = "set_%d" % Time.get_unix_time_from_system()
	var count: int = parse(text).questions.size()
	var f := FileAccess.open(DIR + set_id + ".json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"title": title.strip_edges(), "text": text, "count": count}))
	f.close()
	return set_id


static func load_text(set_id: String) -> Dictionary:
	return _load(set_id)


static func delete_set(set_id: String) -> void:
	DirAccess.remove_absolute(DIR + set_id + ".json")


static func theme_id(set_id: String) -> String:
	return THEME_PREFIX + set_id


static func is_custom(theme: String) -> bool:
	return theme.begins_with(THEME_PREFIX)


static func title_of(theme: String) -> String:
	var data := _load(theme.trim_prefix(THEME_PREFIX))
	return data.get("title", "Custom")


## Parse a saved set and hand its questions to QuizDatabase. Returns the count.
static func activate(set_id: String) -> int:
	var data := _load(set_id)
	if data.is_empty():
		return 0
	var theme := theme_id(set_id)
	var result := parse(data.text, theme)
	QuizDatabase.set_custom_questions(theme, result.questions)
	return result.questions.size()


static func _load(set_id: String) -> Dictionary:
	var path := DIR + set_id + ".json"
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	data.title = String(data.get("title", "Custom")) if String(data.get("title", "")) != "" else "Untitled set"
	return data
