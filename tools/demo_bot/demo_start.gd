extends Node
## Entry scene for a filmed demo process: puts the bot under /root (so it lives
## across scene changes) and lets it take over.

func _ready() -> void:
	var bot := Node.new()
	bot.name = "DemoBot"
	bot.set_script(load("res://tools/demo_bot/demo_bot.gd"))
	get_tree().root.add_child.call_deferred(bot)
