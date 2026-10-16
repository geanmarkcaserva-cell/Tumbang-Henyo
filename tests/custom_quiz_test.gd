extends Node
## Quick check of the CustomQuiz reader. Run this scene; results go to
## user://custom_quiz_test.txt. Test 1 reads whatever is on the clipboard.

const CODE_BLOCK := """Sure! Here's your quiz:

```text
1. What is a kernel?
A) A filter mask
B) A histogram
C) A gamma curve
Correct answer: A
Why: A kernel is a small matrix of weights.

2. Which filter averages neighbours?
A) Median
B) Mean
C) Max
Correct answer: B
```

Let me know if you want more!"""


func _ready() -> void:
	var out := _report("CLIPBOARD", CustomQuiz.parse(DisplayServer.clipboard_get(), "custom:clip"))
	out += _report("CODE BLOCK", CustomQuiz.parse(CODE_BLOCK, "custom:code"))
	var f := FileAccess.open("user://custom_quiz_test.txt", FileAccess.WRITE)
	f.store_string(out)
	f.close()
	get_tree().quit()


func _report(label: String, r: Dictionary) -> String:
	var out := "== %s: questions %d  errors %d\n" % [label, r.questions.size(), r.errors.size()]
	for q in r.questions:
		out += "- %s | %s | answer=%s | why=%s\n" % [q.question, q.choices, q.choices[q.answer], q.explanation]
	for e in r.errors:
		out += "ERR %s\n" % e
	return out
