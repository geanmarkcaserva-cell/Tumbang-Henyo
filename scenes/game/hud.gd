extends CanvasLayer
## Greybox HUD: Awra, stamina, round number, status text and the quiz panel.

@onready var quiz: Control = $QuizPanel
@onready var _awra_bar: ProgressBar = $Margin/VBox/AwraBar
@onready var _awra_label: Label = $Margin/VBox/AwraLabel
@onready var _stamina_bar: ProgressBar = $Margin/VBox/StaminaBar
@onready var _round_label: Label = $RoundLabel
@onready var _status: Label = $Status


func set_awra(value: int, max_value: int) -> void:
	_awra_bar.max_value = max_value
	_awra_bar.value = value
	_awra_label.text = "Awra  %d" % value


func set_stamina(value: float, max_value: float) -> void:
	_stamina_bar.max_value = max_value
	_stamina_bar.value = value


func set_round(number: int) -> void:
	_round_label.text = "Round %d" % number


func show_status(text: String) -> void:
	_status.text = text
