extends Node3D
## Greybox game scene: wires the player, HUD, lata and finish line together.
## The round state machine (quiz -> throw -> run) replaces this on days 2-4.

@onready var _player: CharacterBody3D = $Player
@onready var _hud: CanvasLayer = $HUD
@onready var _lata: RigidBody3D = $Arena/Lata
@onready var _finish: Area3D = $Arena/FinishLine
@onready var _spawn: Marker3D = $Arena/PlayerSpawn


func _ready() -> void:
	_player.global_position = _spawn.global_position
	_player.stamina_changed.connect(_hud.set_stamina)
	_lata.knocked_down.connect(_on_lata_knocked_down)
	_finish.body_entered.connect(_on_finish_body_entered)


func _on_lata_knocked_down() -> void:
	print("Lata down!")
	_hud.show_status("Lata down! Run to the finish line!")


func _on_finish_body_entered(body: Node3D) -> void:
	if body == _player:
		print("Reached the finish line!")
		_hud.show_status("Finish line reached!")
