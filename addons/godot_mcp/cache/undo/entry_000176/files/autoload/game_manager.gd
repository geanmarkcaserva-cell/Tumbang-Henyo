extends Node
## Holds the player's choices between screens and moves between them.

const THEMES := [
	{"id": "history", "name": "History"},
	{"id": "mythology", "name": "Mythology"},
	{"id": "rrm", "name": "RRM", "full": "Risk Reduction Management"},
	{"id": "science", "name": "Science"},
]

const BOOT_LOADING := "res://scenes/menus/boot_loading.tscn"
const MAIN_MENU := "res://scenes/menus/main_menu.tscn"
const TIPS_LOADING := "res://scenes/menus/tips_loading.tscn"
const GAME := "res://scenes/game/game.tscn"

var selected_theme := "history"


func theme_name(theme_id: String) -> String:
	for t in THEMES:
		if t.id == theme_id:
			return t.get("full", t.name)
	return theme_id


## True when this theme has a run saved mid-way. The save system arrives on
## days 8-10, so for now there is never one and Continue stays hidden.
func has_saved_run(_theme_id: String) -> bool:
	return false


## Leave the menus and start a run in this theme (via the tips loading screen).
func start_run(theme_id: String) -> void:
	selected_theme = theme_id
	get_tree().change_scene_to_file(TIPS_LOADING)


func go_to_main_menu() -> void:
	get_tree().change_scene_to_file(MAIN_MENU)
