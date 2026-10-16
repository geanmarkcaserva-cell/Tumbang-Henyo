extends Node
## Tansan (bottlecap) balance, the character and slipper catalog, what the
## player owns and has equipped. Saved to user://profile.cfg.
## Characters and slippers are cosmetic only (GDD: Characters and slippers).

signal caps_changed(value: int)

const SAVE_PATH := "user://profile.cfg"
## New profiles start with a few caps so buying can be tested. Set to 0 for launch.
const STARTER_CAPS := 200

const CHARACTERS := [
	{"id": "totoy", "name": "Totoy", "price": 0,
		"desc": "Batang kalye ng barangay. Sando, shorts, at walang takot sa taya.",
		"palette": {"hair": Color(0.32, 0.2, 0.15), "skin": Color(0.86, 0.66, 0.52), "shirt": Color(0.36, 0.12, 0.15),
			"accent": Color(0.98, 0.6, 0.62), "pants": Color(0.25, 0.05, 0.12), "feet": Color(0.25, 0.4, 0.92)}},
	## Hand-drawn character: "sprite" names its folder. Every character uses the
	## same three sheets there (see PixelArt.character_look): <id>_idle.png,
	## <id>_run.png (back view) and <id>_happy.png, each a horizontal strip of
	## square frames. The palette is only a fallback.
	{"id": "gm", "name": "GM", "price": 0,
		"desc": "Ang henyo ng barangay. Laging may sagot, laging may ahoge.",
		"palette": {"hair": Color(0.05, 0.05, 0.06), "skin": Color(0.98, 0.84, 0.72), "shirt": Color(0.08, 0.1, 0.2),
			"accent": Color(0.85, 0.15, 0.15), "pants": Color(0.08, 0.1, 0.2), "feet": Color(0.05, 0.05, 0.08)},
		"sprite": {"dir": "res://art/characters/gm", "pixel_size": 0.095}},
	{"id": "neneng", "name": "Neneng", "price": 150,
		"desc": "Laging naka-uniform galing eskwela. Mabilis tumakbo, mas mabilis sumagot.",
		"palette": {"hair": Color(0.1, 0.08, 0.08), "skin": Color(0.88, 0.7, 0.56), "shirt": Color(0.95, 0.95, 0.95),
			"accent": Color(0.15, 0.2, 0.45), "pants": Color(0.15, 0.2, 0.45), "feet": Color(0.1, 0.1, 0.1)}},
	{"id": "jepoy", "name": "Kuya Jepoy", "price": 300,
		"desc": "Regular sa SK Court. Jersey, headband, at walang mintis daw.",
		"palette": {"hair": Color(0.12, 0.09, 0.08), "skin": Color(0.72, 0.52, 0.38), "shirt": Color(0.98, 0.8, 0.2),
			"accent": Color(0.4, 0.2, 0.6), "pants": Color(0.4, 0.2, 0.6), "feet": Color(0.95, 0.95, 0.95)}},
	{"id": "lorna", "name": "Ate Lorna", "price": 300,
		"desc": "May-ari ng sari-sari store. Naka-duster at alam ang lahat ng balita sa barangay.",
		"palette": {"hair": Color(0.2, 0.12, 0.1), "skin": Color(0.86, 0.66, 0.52), "shirt": Color(0.95, 0.55, 0.7),
			"accent": Color(1.0, 0.9, 0.4), "pants": Color(0.95, 0.55, 0.7), "feet": Color(0.9, 0.3, 0.3)}},
	{"id": "ising", "name": "Lolo Ising", "price": 500,
		"desc": "Naka-barong at may tungkod na hindi naman niya ginagamit.",
		"palette": {"hair": Color(0.78, 0.78, 0.78), "skin": Color(0.8, 0.6, 0.46), "shirt": Color(0.96, 0.93, 0.82),
			"accent": Color(0.85, 0.8, 0.65), "pants": Color(0.12, 0.12, 0.14), "feet": Color(0.4, 0.25, 0.15)}},
	{"id": "baby", "name": "Tita Baby", "price": 800,
		"desc": "Sunglasses, pamaypay, at sobrang daming energy.",
		"palette": {"hair": Color(0.45, 0.18, 0.12), "skin": Color(0.9, 0.72, 0.6), "shirt": Color(0.2, 0.75, 0.7),
			"accent": Color(1.0, 0.4, 0.6), "pants": Color(0.95, 0.95, 0.95), "feet": Color(1.0, 0.8, 0.25)}},
]

const SLIPPERS := [
	{"id": "goma", "name": "Blue na Tsinelas", "price": 0,
		"desc": "Ang klasikong goma. Asul at puti, laging maaasahan.",
		"palette": {"sole": Color(0.25, 0.4, 0.92), "strap": Color(0.95, 0.95, 0.95)}},
	{"id": "bakya", "name": "Bakya", "price": 250,
		"desc": "Kahoy na bakya na may pinturang disenyo. Maingay kapag tumama.",
		"palette": {"sole": Color(0.6, 0.4, 0.22), "strap": Color(0.85, 0.2, 0.2)}},
	{"id": "pambahay", "name": "Pambahay", "price": 250,
		"desc": "Malambot na pink na tsinelas pambahay.",
		"palette": {"sole": Color(1.0, 0.65, 0.78), "strap": Color(1.0, 1.0, 1.0)}},
	{"id": "simbahan", "name": "Pang-Simbahan", "price": 400,
		"desc": "Makintab na sandalyas pang-Linggo.",
		"palette": {"sole": Color(0.14, 0.13, 0.14), "strap": Color(0.5, 0.3, 0.16)}},
	{"id": "ginto", "name": "Gintong Tsinelas", "price": 1500,
		"desc": "Ginto. Pang-flex lang, pareho pa rin ang tama.",
		"palette": {"sole": Color(1.0, 0.8, 0.25), "strap": Color(1.0, 0.97, 0.85)}},
]

var caps := STARTER_CAPS
var owned := {"totoy": true, "goma": true}
var equipped_character := "totoy"
var equipped_slipper := "goma"


func _ready() -> void:
	load_profile()


func owns(item_id: String) -> bool:
	if owned.has(item_id):
		return true
	# Free items are always yours (also on saves made before they existed).
	for kind in ["character", "slipper"]:
		for item in catalog(kind):
			if item.id == item_id and item.price == 0:
				return true
	return false


func can_afford(price: int) -> bool:
	return caps >= price


## Spend caps on an item. Returns false if it can't be bought.
func buy(item_id: String, price: int) -> bool:
	if owns(item_id) or not can_afford(price):
		return false
	caps -= price
	owned[item_id] = true
	save_profile()
	caps_changed.emit(caps)
	return true


func add_caps(amount: int) -> void:
	caps += amount
	caps_changed.emit(caps)


func equip(kind: String, item_id: String) -> void:
	if not owns(item_id):
		return
	if kind == "character":
		equipped_character = item_id
	else:
		equipped_slipper = item_id
	save_profile()


func equipped(kind: String) -> String:
	return equipped_character if kind == "character" else equipped_slipper


func catalog(kind: String) -> Array:
	return CHARACTERS if kind == "character" else SLIPPERS


func find_item(kind: String, item_id: String) -> Dictionary:
	for item in catalog(kind):
		if item.id == item_id:
			return item
	return catalog(kind)[0]


func slipper_palette() -> Dictionary:
	return find_item("slipper", equipped_slipper).palette


func save_profile() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "caps", caps)
	cfg.set_value("profile", "owned", owned.keys())
	cfg.set_value("profile", "character", equipped_character)
	cfg.set_value("profile", "slipper", equipped_slipper)
	cfg.save(SAVE_PATH)


func load_profile() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return # first launch: keep the defaults
	caps = cfg.get_value("profile", "caps", STARTER_CAPS)
	for item_id in cfg.get_value("profile", "owned", []):
		owned[item_id] = true
	equipped_character = cfg.get_value("profile", "character", "totoy")
	equipped_slipper = cfg.get_value("profile", "slipper", "goma")
