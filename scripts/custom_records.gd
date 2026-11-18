class_name CustomRecords
extends RefCounted
## Score records of custom quiz games, kept on this device for review (Custom
## quiz -> Records). Every custom game that ends - made it home, caught, or
## left early from the pause menu after answering something - adds one:
##   {set, title, desc, player, time, score, rounds, correct, asked, result, class}
## result is "home", "caught" or "left". Newest first; only the last MAX are kept.

const PATH := "user://custom_records.json"
const MAX := 300


static func add(entry: Dictionary) -> void:
	var all := _load()
	all.push_front(entry)
	if all.size() > MAX:
		all.resize(MAX)
	_save(all)


## Records newest first; set_id "" = every set.
static func list(set_id: String = "") -> Array:
	var all := _load()
	if set_id == "":
		return all
	return all.filter(func(r): return String(r.get("set", "")) == set_id)


## Forget the records of one set ("" = all of them).
static func clear(set_id: String = "") -> void:
	if set_id == "":
		_save([])
	else:
		_save(_load().filter(func(r): return String(r.get("set", "")) != set_id))


static func _load() -> Array:
	if not FileAccess.file_exists(PATH):
		return []
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return data if typeof(data) == TYPE_ARRAY else []


static func _save(all: Array) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(all))
		f.close()
