extends CanvasLayer
## Greybox HUD: Awra, stamina, round number, status text, the quiz panel,
## and the throw UI (power gauge, crosshair, wind).

@onready var quiz: Control = $QuizPanel
@onready var _awra_bar: ProgressBar = $Margin/VBox/AwraBar
@onready var _awra_label: Label = $Margin/VBox/AwraLabel
@onready var _stamina_bar: ProgressBar = $Margin/VBox/StaminaBar
@onready var _round_label: Label = $RoundLabel
@onready var _status: Label = $Status
@onready var _throw_ui: Control = $ThrowUI
@onready var _power_gauge: Control = $ThrowUI/PowerGauge
@onready var _wind_arrow: Control = $Margin/VBox/WindRow/WindArrow
@onready var _wind_label: Label = $Margin/VBox/WindRow/WindLabel


func _ready() -> void:
	_throw_ui.visible = false


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


func show_throw_ui(on: bool) -> void:
	_throw_ui.visible = on
	if not on:
		_power_gauge.value = 0.0


func set_power(value: float) -> void:
	_power_gauge.value = value


## wind: horizontal wind in m/s. view_basis: the player's facing, so the
## arrow points the way the wind blows relative to the screen.
func update_wind(wind: Vector3, view_basis: Basis) -> void:
	var speed := Vector2(wind.x, wind.z).length()
	if speed < 0.05:
		_wind_label.text = "Wind: none"
		_wind_arrow.direction = Vector2.ZERO
		return
	var local := view_basis.inverse() * wind
	_wind_arrow.direction = Vector2(local.x, local.z).normalized()
	_wind_label.text = "Wind: %.1f m/s" % speed
