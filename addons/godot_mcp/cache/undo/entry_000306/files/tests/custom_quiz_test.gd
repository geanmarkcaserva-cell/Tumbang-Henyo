extends Node
## Quick check of the CustomQuiz reader. Run this scene and read the output.

const SAMPLE := """1. Sino ang pambansang bayani ng Pilipinas?
a) Jose Rizal *
b) Andres Bonifacio
c) Apolinario Mabini
Why: Siya ang sumulat ng Noli at Fili.
2) Ano ang kabisera ng Pilipinas?
Answer: Maynila

Q: Anong taon idineklara ang kalayaan?
A. 1896
B. 1898
C. 1946
D. 1901
Answer: b

Saang probinsya ang Bulkang Mayon?
Sagot: Albay

5. Ilang rehiyon ang Pilipinas?
a) 17
b) 18

6. Walang sagot ito?
a) oo
b) hindi
c) siguro
"""


func _ready() -> void:
	var out := ""
	var r := CustomQuiz.parse(SAMPLE, "custom:test")
	out += "questions: %d  errors: %d\n" % [r.questions.size(), r.errors.size()]
	for q in r.questions:
		out += "- %s  %s  answer=%s  why=%s\n" % [q.question, q.choices, q.choices[q.answer], q.explanation]
	for e in r.errors:
		out += "ERR %s\n" % e
	var csv := "id,theme,tier,question,choice_a,choice_b,choice_c,answer,explanation\n1,x,easy,Ano ang 2+2?,3,4,5,b,Basic math\n"
	var c := CustomQuiz.parse(csv, "custom:csv")
	out += "csv questions: %d %s errors %s\n" % [c.questions.size(), c.questions[0].choices if c.questions.size() > 0 else [], c.errors]
	var f := FileAccess.open("user://custom_quiz_test.txt", FileAccess.WRITE)
	f.store_string(out)
	f.close()
	get_tree().quit()
