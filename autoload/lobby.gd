extends Node
## Class games over the same WiFi: a teacher hosts a lobby for one of their
## custom quiz sets, students join with the lobby ID, everyone plays their own
## game with the teacher's questions, and scores meet on a live leaderboard.
##
## No server or internet needed. The teacher's device is the host:
##   - The lobby ID (e.g. "K7P-2QX") hides the last two numbers of the host's
##     WiFi address plus a random part, so a student's device can work out the
##     address and knock on it directly. It also shouts on the network
##     (UDP broadcast) in case the address guess is off.
##   - The host answers "here I am", then the student connects (ENet) and gets
##     the quiz, the player list and, once the teacher starts, the go signal.
##   - Each student sends their score/round/Awra when they change; the host
##     keeps the board and sends it to everyone.

signal players_changed ## the roster / leaderboard changed
signal joined ## student: connected and got the quiz
signal join_failed(message: String)
signal match_started ## student: start playing; host: the board goes live
signal match_ended ## the teacher ended the game
signal left(reason: String) ## student: lost the lobby (teacher closed it, WiFi dropped...)

enum Role { NONE, HOST, CLIENT }

const GAME_PORT := 47914
const FIND_PORT := 47913
const PROTOCOL := 1
const MAX_STUDENTS := 64
const ALPHABET := "23456789ABCDEFGHJKLMNPQRSTUVWXYZ" ## no 0/O, 1/I lookalikes
const FIND_TIMEOUT := 7.0
const FIND_EVERY := 0.4
const BOARD_EVERY := 0.4 ## seconds between leaderboard updates from the host

var role := Role.NONE
var lobby_id := "" ## 6 characters, shown as "ABC-DEF"
var quiz_title := ""
var quiz_theme := "" ## QuizDatabase theme id for the lobby's questions
var match_on := false
var match_seed := 0
var my_name := ""
## peer id -> {name, score, round, awra, out, perfect, left}
var players := {}

var _udp: PacketPeerUDP
var _questions: Array = []
var _finding := false
var _find_left := 0.0
var _find_tick := 0.0
var _find_targets: Array[String] = []
var _board_dirty := false
var _board_tick := 0.0
var _last_report := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func is_host() -> bool:
	return role == Role.HOST


func is_client() -> bool:
	return role == Role.CLIENT


## A student in a running class game (the game reports scores and shows the board).
func in_match() -> bool:
	return role == Role.CLIENT and match_on


func pretty_id(id: String = lobby_id) -> String:
	return id.substr(0, 3) + "-" + id.substr(3) if id.length() == 6 else id


## Board rows, best first: [{id, name, score, round, awra, out, perfect, left, me}]
func board() -> Array:
	var rows := []
	for id in players:
		var p: Dictionary = players[id].duplicate()
		p.id = id
		p.me = multiplayer.multiplayer_peer != null and id == multiplayer.get_unique_id() and role == Role.CLIENT
		rows.append(p)
	rows.sort_custom(func(a, b):
		if a.score != b.score:
			return a.score > b.score
		return a.round > b.round)
	return rows


## My place on the board (1 = first), 0 if unknown.
func my_rank() -> int:
	var rows := board()
	for i in rows.size():
		if rows[i].me:
			return i + 1
	return 0


# --- Teacher -------------------------------------------------------------------

## Open a lobby for a custom quiz set. Returns "" or an error message.
func host(set_id: String) -> String:
	close()
	var count := CustomQuiz.activate(set_id)
	if count == 0:
		return "That quiz has no questions yet."
	quiz_theme = CustomQuiz.theme_id(set_id)
	quiz_title = CustomQuiz.title_of(quiz_theme)
	_questions = QuizDatabase.questions_of(quiz_theme)
	var ip := _lan_ip()
	if ip == "":
		return "No WiFi network found. Connect this device to the class WiFi first."
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(GAME_PORT, MAX_STUDENTS)
	if err != OK:
		return "Couldn't open the lobby (port %d is busy). Close other copies of the game and try again." % GAME_PORT
	multiplayer.multiplayer_peer = peer
	_udp = PacketPeerUDP.new()
	if _udp.bind(FIND_PORT) != OK:
		push_warning("Lobby: discovery port %d busy; students must be on the same subnet." % FIND_PORT)
	role = Role.HOST
	lobby_id = _make_id(ip)
	players.clear()
	match_on = false
	print("Lobby: hosting %s on %s:%d (%d questions)" % [pretty_id(), ip, GAME_PORT, _questions.size()])
	players_changed.emit()
	return ""


func start_match() -> void:
	if role != Role.HOST:
		return
	match_on = true
	match_seed = randi()
	for id in players:
		var p: Dictionary = players[id]
		p.score = 0
		p.round = 1
		p.awra = 100
		p.out = false
		p.perfect = 0
	_h_start.rpc(match_seed)
	_h_players.rpc(players)
	Achievements.unlock("teacher")
	match_started.emit()
	players_changed.emit()


func end_match() -> void:
	if role != Role.HOST or not match_on:
		return
	match_on = false
	_h_end.rpc()
	match_ended.emit()


# --- Student -------------------------------------------------------------------

## Look for the lobby on the WiFi and join it. Listen for joined / join_failed.
func join(id: String, player_name: String) -> void:
	close()
	id = normalize_id(id)
	if id.length() != 6:
		join_failed.emit("A lobby ID has 6 letters and numbers, like K7P-2QX.")
		return
	my_name = player_name.strip_edges().substr(0, 18)
	if my_name == "":
		my_name = "Student"
	lobby_id = id
	_find_targets.clear()
	var guess := _ip_from_id(id)
	if guess != "":
		_find_targets.append(guess)
	_find_targets.append("255.255.255.255")
	_udp = PacketPeerUDP.new()
	_udp.set_broadcast_enabled(true)
	if _udp.bind(0) != OK:
		join_failed.emit("Couldn't use the network on this device.")
		return
	_finding = true
	_find_left = FIND_TIMEOUT
	_find_tick = 0.0
	role = Role.CLIENT


func normalize_id(id: String) -> String:
	var out := ""
	for ch in id.to_upper():
		if ALPHABET.contains(ch): # dashes and spaces drop out
			out += ch
	return out


## The game reports how this student is doing (only sends real changes).
func report(score: int, round_number: int, awra: int, out: bool, perfect: int) -> void:
	if role != Role.CLIENT or multiplayer.multiplayer_peer == null:
		return
	var r := {"score": score, "round": round_number, "awra": awra, "out": out, "perfect": perfect}
	if r == _last_report:
		return
	_last_report = r
	_c_report.rpc_id(1, score, round_number, awra, out, perfect)


## Leave / close the lobby.
func close() -> void:
	_finding = false
	if _udp:
		_udp.close()
		_udp = null
	if multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	role = Role.NONE
	match_on = false
	players.clear()
	_last_report = {}


# --- Discovery -----------------------------------------------------------------

func _process(delta: float) -> void:
	if _udp == null:
		return
	if role == Role.HOST:
		while _udp.get_available_packet_count() > 0:
			var msg := _udp.get_packet().get_string_from_utf8()
			if msg == "THFIND " + lobby_id:
				_udp.set_dest_address(_udp.get_packet_ip(), _udp.get_packet_port())
				_udp.put_packet(("THHERE %s %d" % [lobby_id, GAME_PORT]).to_utf8_buffer())
		if _board_dirty:
			_board_tick -= delta
			if _board_tick <= 0.0:
				_board_tick = BOARD_EVERY
				_board_dirty = false
				_h_players.rpc(players)
				players_changed.emit()
	elif role == Role.CLIENT and _finding:
		while _udp.get_available_packet_count() > 0:
			var msg := _udp.get_packet().get_string_from_utf8()
			var ip := _udp.get_packet_ip()
			var parts := msg.split(" ")
			if parts.size() >= 3 and parts[0] == "THHERE" and parts[1] == lobby_id:
				_finding = false
				_connect_to(ip, int(parts[2]))
				return
		_find_left -= delta
		if _find_left <= 0.0:
			var id := pretty_id()
			close()
			join_failed.emit("Couldn't find lobby %s. Check the ID, and that you're on the same WiFi as your teacher." % id)
			return
		_find_tick -= delta
		if _find_tick <= 0.0:
			_find_tick = FIND_EVERY
			for target in _find_targets:
				_udp.set_dest_address(target, FIND_PORT)
				_udp.put_packet(("THFIND " + lobby_id).to_utf8_buffer())


func _connect_to(ip: String, port: int) -> void:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(ip, port) != OK:
		close()
		join_failed.emit("Couldn't connect to the lobby.")
		return
	multiplayer.multiplayer_peer = peer


func _on_connected() -> void:
	if role == Role.CLIENT:
		_c_hello.rpc_id(1, my_name, PROTOCOL)


func _on_connection_failed() -> void:
	if role == Role.CLIENT:
		close()
		join_failed.emit("Couldn't connect to the lobby.")


func _on_server_disconnected() -> void:
	if role == Role.CLIENT:
		close()
		left.emit("The teacher closed the lobby.")


func _on_peer_connected(_id: int) -> void:
	pass # wait for their hello


func _on_peer_disconnected(id: int) -> void:
	if role == Role.HOST and players.has(id):
		players[id].left = true
		_mark_board()


func _mark_board() -> void:
	_board_dirty = true


# --- Messages --------------------------------------------------------------------

## Student -> teacher: my name.
@rpc("any_peer", "reliable")
func _c_hello(player_name: String, protocol: int) -> void:
	if role != Role.HOST:
		return
	var id := multiplayer.get_remote_sender_id()
	if protocol != PROTOCOL:
		_h_refuse.rpc_id(id, "This game version doesn't match your teacher's. Update the game.")
		return
	player_name = player_name.strip_edges().substr(0, 18)
	if player_name == "":
		player_name = "Student"
	# Same name twice in a class: add a number.
	var taken := {}
	for p in players.values():
		taken[p.name] = true
	var unique := player_name
	var n := 2
	while taken.has(unique):
		unique = "%s %d" % [player_name, n]
		n += 1
	players[id] = {"name": unique, "score": 0, "round": 1, "awra": 100, "out": false, "perfect": 0, "left": false}
	_h_welcome.rpc_id(id, lobby_id, quiz_title, quiz_theme, _questions, match_on, match_seed, unique)
	_h_players.rpc(players)
	players_changed.emit()


## Student -> teacher: how I'm doing.
@rpc("any_peer", "reliable")
func _c_report(score: int, round_number: int, awra: int, out: bool, perfect: int) -> void:
	if role != Role.HOST:
		return
	var id := multiplayer.get_remote_sender_id()
	if not players.has(id):
		return
	var p: Dictionary = players[id]
	p.score = score
	p.round = round_number
	p.awra = awra
	p.out = out
	p.perfect = perfect
	_mark_board()


@rpc("authority", "reliable")
func _h_refuse(message: String) -> void:
	close()
	join_failed.emit(message)


@rpc("authority", "reliable")
func _h_welcome(id: String, title: String, theme: String, questions: Array, running: bool, seed_value: int, final_name: String) -> void:
	lobby_id = id
	quiz_title = title
	quiz_theme = theme
	my_name = final_name
	QuizDatabase.set_custom_questions(theme, questions)
	Achievements.unlock("classmate")
	Sfx.play("join") # you're in the class
	match_on = running
	match_seed = seed_value
	joined.emit()
	if running:
		match_started.emit() # late join: straight into the game


@rpc("authority", "reliable")
func _h_players(p: Dictionary) -> void:
	players = p
	players_changed.emit()


@rpc("authority", "reliable")
func _h_start(seed_value: int) -> void:
	match_on = true
	match_seed = seed_value
	_last_report = {}
	match_started.emit()


@rpc("authority", "reliable")
func _h_end() -> void:
	match_on = false
	match_ended.emit()


# --- Lobby ID <-> address ------------------------------------------------------------

## This device's WiFi/LAN address (private IPv4), or "".
static func _lan_ip() -> String:
	var best := ""
	for a in IP.get_local_addresses():
		if a.contains(":"):
			continue
		if a.begins_with("192.168."):
			return a
		if a.begins_with("10.") or _is_172_private(a):
			best = a
	return best


static func _is_172_private(a: String) -> bool:
	if not a.begins_with("172."):
		return false
	var second := int(a.get_slice(".", 1))
	return second >= 16 and second <= 31


## 6 characters: 4 carry the address's last two numbers (plus 4 random bits),
## 2 are random so an old ID from yesterday doesn't find today's lobby.
static func _make_id(ip: String) -> String:
	var parts := ip.split(".")
	var low := (int(parts[2]) << 8) | int(parts[3])
	var value := ((randi() & 0xF) << 16) | low
	var id := ""
	for i in 4:
		id = ALPHABET[value & 31] + id
		value >>= 5
	for i in 2:
		id += ALPHABET[randi() % 32]
	return id


## The host's address guessed from the ID and this device's own network.
static func _ip_from_id(id: String) -> String:
	var value := 0
	for i in 4:
		value = (value << 5) | ALPHABET.find(id[i])
	var low := value & 0xFFFF
	var mine := _lan_ip()
	if mine == "":
		return ""
	var p := mine.split(".")
	return "%s.%s.%d.%d" % [p[0], p[1], low >> 8, low & 255]
