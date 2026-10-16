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
	var r := CustomQuiz.parse(SAMPLE, "custom:test")
	print("questions: ", r.questions.size(), "  errors: ", r.errors.size())
	for q in r.questions:
		print("- ", q.question, "  ", q.choices, "  answer=", q.choices[q.answer], "  why=", q.explanation)
	for e in r.errors:
		print("ERR ", e)
	var csv := "id,theme,tier,question,choice_a,choice_b,choice_c,answer,explanation\n1,x,easy,Ano ang 2+2?,3,4,5,b,Basic math\n"
	var c := CustomQuiz.parse(csv, "custom:csv")
	print("csv questions: ", c.questions.size(), " ", c.questions[0].choices if c.questions.size() > 0 else [], " errors ", c.errors)
	get_tree().quit()
