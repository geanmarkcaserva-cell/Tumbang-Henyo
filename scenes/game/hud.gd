extends CanvasLayer
## Greybox HUD: stamina bar and a controls hint.

@onready var _stamina_bar: ProgressBar = $Margin/VBox/StaminaBar
@onready var _status: Label = $Margin/VBox/Status


func set_stamina(value: float, max_value: float) -> void:
	_stamina_bar.max_value = max_value
	_stamina_bar.value = value


func show_status(text: String) -> void:
	_status.text = text
