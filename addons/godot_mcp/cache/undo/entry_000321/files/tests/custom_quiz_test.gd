extends Node
## Quick check of the CustomQuiz reader against a typical AI chat answer.
## Run this scene; results go to user://custom_quiz_test.txt.

const AI_ANSWER := """Narito ang iyong quiz!

**1. Ano ang tawag sa paggalaw ng lupa dahil sa paglabas ng enerhiya sa ilalim nito?**
a) Lindol *
b) Bagyo
c) Baha
Why: Ang lindol ay sanhi ng biglang paglabas ng enerhiya sa crust ng mundo.

**2. Ano ang dapat gawin habang lumilindol?**
a) Tumakbo palabas agad
b) Duck, Cover and Hold ✅
c) Sumakay sa elevator
Why: Pinoprotektahan nito ang ulo at katawan mula sa nahuhulog na bagay.

### 3. Aling ahensya ang nagbibigay ng babala sa bagyo?
- a) PHIVOLCS
- b) PAGASA *
- c) DepEd
Why: Ang PAGASA ang nagmo-monitor ng panahon.

Sana makatulong ito sa iyong klase!"""


func _ready() -> void:
	var out := ""
	var r := CustomQuiz.parse(AI_ANSWER, "custom:test")
	out += "questions: %d  errors: %d\n" % [r.questions.size(), r.errors.size()]
	for q in r.questions:
		out += "- %s  %s  answer=%s  why=%s\n" % [q.question, q.choices, q.choices[q.answer], q.explanation]
	for e in r.errors:
		out += "ERR %s\n" % e
	var f := FileAccess.open("user://custom_quiz_test.txt", FileAccess.WRITE)
	f.store_string(out)
	f.close()
	get_tree().quit()
