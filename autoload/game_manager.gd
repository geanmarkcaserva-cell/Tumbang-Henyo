extends Node
## Holds the player's choices between screens, moves between them, and keeps
## a local leaderboard per theme until the online one is live.

const THEMES := [
	{"id": "history", "name": "History"},
	{"id": "mythology", "name": "Mythology"},
	{"id": "rrm", "name": "RRM", "full": "Risk Reduction Management"},
	{"id": "science", "name": "Science"},
]

const BOOT_LOADING := "res://scenes/menus/boot_loading.tscn"
const MAIN_MENU := "res://scenes/menus/main_menu.tscn"
const TIPS_LOADING := "res://scenes/menus/tips_loading.tscn"
const TRAILER := "res://scenes/menus/trailer.tscn" ## plays when the game opens, before the main menu
const TRAILER_VIDEO := "res://art/video/trailer.ogv"
const GAME := "res://scenes/game/game.tscn"

const BOARD_PATH := "user://leaderboard.cfg"
const BOARD_SIZE := 7

var selected_theme := "history"
## Where the trailer goes when it ends (set by the boot screen: the main menu,
## already loaded).
var after_trailer: PackedScene
## The name on the device leaderboard: the current account's.
var player_name: String:
	get:
		return Accounts.current_name()


func theme_name(theme_id: String) -> String:
	if theme_id == Lobby.quiz_theme and Lobby.quiz_title != "":
		return Lobby.quiz_title # a class game's set lives on the teacher's device
	if CustomQuiz.is_custom(theme_id):
		return CustomQuiz.title_of(theme_id)
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
	Transition.change_scene(TIPS_LOADING) # fades out, unpauses, fades in


func go_to_main_menu() -> void:
	Transition.change_scene(MAIN_MENU)


# --- Local leaderboard -----------------------------------------------------------

## Top scores for a theme, best first: [{name, score, rounds}, ...]
func local_board(theme_id: String) -> Array:
	var cfg := ConfigFile.new()
	if cfg.load(BOARD_PATH) != OK:
		return []
	return cfg.get_value("boards", theme_id, [])


func best_score(theme_id: String) -> int:
	var board := local_board(theme_id)
	return board[0].score if board.size() > 0 else 0


## Add a finished run. Returns its rank (1 = best) or 0 if it didn't place.
func submit_score(theme_id: String, score: int, rounds: int) -> int:
	if score <= 0:
		return 0
	var board := local_board(theme_id)
	var entry := {"name": player_name, "score": score, "rounds": rounds, "time": Time.get_unix_time_from_system()}
	board.append(entry)
	board.sort_custom(func(a, b): return a.score > b.score)
	board = board.slice(0, BOARD_SIZE)
	var cfg := ConfigFile.new()
	cfg.load(BOARD_PATH)
	cfg.set_value("boards", theme_id, board)
	cfg.save(BOARD_PATH)
	return board.find(entry) + 1
