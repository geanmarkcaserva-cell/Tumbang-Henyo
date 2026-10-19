extends Node
## Test helper for class games: a fake student. Run a second copy headless:
##   godot --headless --path <project> res://tests/lobby_bot.tscn -- --no-mcp <LOBBY_ID> <Name> [host <set_id>]
## As a student it joins the lobby, then once the teacher starts it "plays":
## the score climbs every second, a bullseye now and then, and after a while
## it runs out of Awra. With "host <set_id>" it hosts a lobby instead and
## starts the game a few seconds after the first student joins.

var _args: PackedStringArray
var _score := 0
var _round := 1
var _awra := 100
var _perfect := 0
var _t := 0.0
var _playing := false
var _hosting := false
var _started := false


func _ready() -> void:
	_args = OS.get_cmdline_user_args()
	var rest: Array = []
	for a in _args:
		if a != "--no-mcp":
			rest.append(a)
	print("BOT args: ", rest)
	if rest.size() >= 3 and rest[0] == "host":
		_hosting = true
		var err := Lobby.host(rest[1])
		print("BOT hosting: ", Lobby.pretty_id(), " err=", err, " quiz=", Lobby.quiz_title)
		var f := FileAccess.open("res://addons/godot_mcp/cache/bot_lobby_id.txt", FileAccess.WRITE)
		f.store_string(Lobby.lobby_id)
		f.close()
		Lobby.players_changed.connect(func(): print("BOT board: ", Lobby.board()))
		return
	var id: String = rest[0] if rest.size() > 0 else ""
	var who: String = rest[1] if rest.size() > 1 else "Bot"
	Lobby.joined.connect(func(): print("BOT joined ", Lobby.pretty_id(), " quiz=", Lobby.quiz_title, " as ", Lobby.my_name))
	Lobby.join_failed.connect(func(m): print("BOT join failed: ", m); get_tree().quit())
	Lobby.match_started.connect(func(): print("BOT match started seed=", Lobby.match_seed); _playing = true)
	Lobby.match_ended.connect(func(): print("BOT match ended"); _playing = false)
	Lobby.left.connect(func(r): print("BOT left: ", r); get_tree().quit())
	Lobby.join(id, who)


func _process(delta: float) -> void:
	_t += delta
	if _t > 240.0:
		get_tree().quit()
	if _hosting:
		# Starts once 3 students are in (or a file says go), so there's time to look at the waiting room.
		if not _started and Lobby.players.size() >= 3 and (_t > 45.0 or FileAccess.file_exists("res://addons/godot_mcp/cache/bot_start.txt")):
			_started = true
			print("BOT starting match")
			Lobby.start_match()
		return
	if not _playing:
		return
	if fmod(_t, 1.0) < delta:
		_score += randi_range(80, 260)
		if randf() < 0.25:
			_round += 1
		if randf() < 0.15:
			_perfect += 1
		if randf() < 0.2:
			_awra = maxi(_awra - 20, 0)
		Lobby.report(_score, _round, _awra, _awra <= 0, _perfect)
		if _awra <= 0:
			_playing = false
			print("BOT out with ", _score)
