extends Node
## Entry scene for a filmed pitch clip: puts the pitch bot under /root.

func _ready() -> void:
	var bot := Node.new()
	bot.name = "PitchBot"
	bot.set_script(load("res://tools/demo_bot/pitch_bot.gd"))
	get_tree().root.add_child.call_deferred(bot)
