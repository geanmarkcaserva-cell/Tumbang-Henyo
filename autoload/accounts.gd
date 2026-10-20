extends Node
## Local accounts (profiles) on this device: up to MAX_ACCOUNTS players, each
## with their own tansan, items, tutorial progress, stats and achievements.
##
## The list lives in user://accounts.cfg. Each account's saves sit in its own
## folder, user://accounts/<id>/ (profile.cfg, achievements.cfg). Settings,
## custom quizzes and the device leaderboard stay shared by everyone.
##
## Other scripts ask path("profile.cfg") for where to save. With no account yet
## (first launch) that's the old single-player location, so the very first
## account created takes over any progress made before accounts existed.

signal changed ## an account was created, switched, renamed or deleted

const LIST_PATH := "user://accounts.cfg"
const ROOT := "user://accounts/"
const MAX_ACCOUNTS := 5
const NAME_MAX := 16
## Badge colours, picked in turn for new accounts (changeable: set_color).
const COLORS := [Color(0.98, 0.72, 0.25), Color(0.4, 0.75, 1.0), Color(0.55, 0.9, 0.5),
		Color(1.0, 0.5, 0.6), Color(0.75, 0.6, 1.0)]

var _accounts: Array = [] ## [{id, name, created, color, avatar}] (avatar: see Avatars)
var _current := ""
var _loaded := false


func _ready() -> void:
	_ensure()


# --- Queries ------------------------------------------------------------------------

func list() -> Array:
	_ensure()
	return _accounts.duplicate(true)


func has_any() -> bool:
	_ensure()
	return not _accounts.is_empty()


func can_create() -> bool:
	_ensure()
	return _accounts.size() < MAX_ACCOUNTS


func current_id() -> String:
	_ensure()
	return _current


func current() -> Dictionary:
	return find(current_id())


func current_name() -> String:
	var a := current()
	return a.get("name", "Ikaw")


func find(id: String) -> Dictionary:
	_ensure()
	for a in _accounts:
		if a.id == id:
			return a
	return {}


## Where the current account keeps `file` (profile.cfg, achievements.cfg...).
func path(file: String) -> String:
	_ensure()
	if _current == "":
		return "user://" + file # no account yet: the pre-accounts location
	return ROOT + _current + "/" + file


## The same, for any account (for its stats card).
func path_of(id: String, file: String) -> String:
	return ROOT + id + "/" + file


# --- Changes ------------------------------------------------------------------------

## A clean, unique name, or "" if it's empty. Returns the error to show, or "".
func check_name(name: String, ignore_id: String = "") -> String:
	var n := clean_name(name)
	if n == "":
		return "Type a name first."
	for a in _accounts:
		if a.id != ignore_id and String(a.name).to_lower() == n.to_lower():
			return "That name is already taken on this device."
	return ""


static func clean_name(name: String) -> String:
	return name.strip_edges().substr(0, NAME_MAX)


## Make a new account and switch to it. Returns its id ("" if not allowed).
func create(name: String) -> String:
	_ensure()
	if not can_create() or check_name(name) != "":
		return ""
	var first := _accounts.is_empty()
	var id := "acc%d_%d" % [Time.get_unix_time_from_system(), randi() % 10000]
	DirAccess.make_dir_recursive_absolute(ROOT + id)
	if first:
		_adopt_old_saves(id) # progress from before accounts goes to the first one
	_accounts.append({"id": id, "name": clean_name(name),
			"created": int(Time.get_unix_time_from_system()),
			"color": COLORS[_accounts.size() % COLORS.size()]})
	_save_list()
	switch_to(id)
	return id


func rename(id: String, name: String) -> bool:
	if check_name(name, id) != "":
		return false
	for a in _accounts:
		if a.id == id:
			a.name = clean_name(name)
	_save_list()
	changed.emit()
	return true


## Profile picture (see Avatars): {"kind": "letter" / "character" / "slipper" / "item", "id": ...}.
func set_avatar(id: String, avatar: Dictionary) -> void:
	for a in _accounts:
		if a.id == id:
			a.avatar = avatar.duplicate()
	_save_list()
	changed.emit()


## The badge colour behind the picture.
func set_color(id: String, color: Color) -> void:
	for a in _accounts:
		if a.id == id:
			a.color = color
	_save_list()
	changed.emit()


## What an account has unlocked for its picture: owned characters and slippers
## and found Collection items. The current account answers live.
func unlocks_of(id: String) -> Dictionary:
	if id == current_id():
		return {"owned": Economy.owned.keys(), "collection": Economy.collection.duplicate()}
	var out := {"owned": ["proktoy", "goma"], "collection": []}
	var p := ConfigFile.new()
	if p.load(path_of(id, "profile.cfg")) == OK:
		out.owned = p.get_value("profile", "owned", out.owned)
		out.collection = p.get_value("collection", "items", [])
	return out


## Delete an account and its saves. If it was the current one, switch to the
## next one left (or to "no account", which shows the create screen).
func delete(id: String) -> void:
	_ensure()
	var keep: Array = []
	for a in _accounts:
		if a.id != id:
			keep.append(a)
	_accounts = keep
	_remove_dir(ROOT + id)
	if _current == id:
		_current = ""
		_save_list()
		if not _accounts.is_empty():
			switch_to(_accounts[0].id)
		else:
			_reload_everything()
			changed.emit()
	else:
		_save_list()
		changed.emit()


## Make `id` the active account and load its progress everywhere.
func switch_to(id: String) -> void:
	if find(id).is_empty():
		return
	if _current != "":
		Economy.save_profile() # keep what the old account had
	_current = id
	_save_list()
	_reload_everything()
	changed.emit()


# --- Stats ----------------------------------------------------------------------------

## A summary for an account's card: tansan, runs, wins, best score, trophies...
func stats_of(id: String) -> Dictionary:
	var out := {"caps": 0, "games": 0, "wins": 0, "best": 0, "best_theme": "", "highest_round": 0,
			"correct": 0, "bullseyes": 0, "owned": 0, "achievements": 0, "play_seconds": 0, "eggs": 0}
	var p := ConfigFile.new()
	if p.load(path_of(id, "profile.cfg")) == OK:
		out.caps = p.get_value("profile", "caps", 0)
		out.owned = (p.get_value("profile", "owned", []) as Array).size()
		out.eggs = (p.get_value("collection", "items", []) as Array).size()
		var st: Dictionary = p.get_value("stats", "all", {})
		for k in ["games", "wins", "highest_round", "bullseyes", "play_seconds"]:
			out[k] = int(st.get(k, 0))
		var best: Dictionary = st.get("best", {})
		for theme in best:
			if int(best[theme]) > out.best:
				out.best = int(best[theme])
				out.best_theme = theme
	var ach := ConfigFile.new()
	if ach.load(path_of(id, "achievements.cfg")) == OK:
		out.achievements = (ach.get_value("achievements", "unlocked", {}) as Dictionary).size()
		out.correct = int((ach.get_value("achievements", "stats", {}) as Dictionary).get("correct_total", 0))
	return out


# --- Internals ------------------------------------------------------------------------

func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(LIST_PATH) == OK:
		_accounts = cfg.get_value("accounts", "list", [])
		_current = cfg.get_value("accounts", "current", "")
	if find(_current).is_empty():
		_current = _accounts[0].id if not _accounts.is_empty() else ""


func _save_list() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("accounts", "list", _accounts)
	cfg.set_value("accounts", "current", _current)
	cfg.save(LIST_PATH)


func _reload_everything() -> void:
	Economy.load_profile()
	Achievements.reload()


## Move the pre-accounts saves (user://profile.cfg, achievements.cfg) into `id`.
func _adopt_old_saves(id: String) -> void:
	for f in ["profile.cfg", "achievements.cfg"]:
		var old: String = "user://" + f
		if FileAccess.file_exists(old):
			DirAccess.rename_absolute(old, ROOT + id + "/" + f)


func _remove_dir(dir_path: String) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(dir_path)
