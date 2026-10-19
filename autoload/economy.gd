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

## Every slipper is a hand-drawn sprite in art/Slippers ("icon"), shown as-is
## in weapon select. "palette" colours the 3D tsinelas in-game, picked from
## the sprite's mid tones (the 3D view is lit and tone-mapped, so the art's
## darkest colours would come out near black). "enchanted" adds the
## Minecraft-style purple glint (see Enchant). Items without an icon fall back
## to a generated placeholder.
const SLIPPERS := [
	{"id": "goma", "name": "Blue na Tsinelas", "price": 0,
		"desc": "Ang klasikong goma. Asul, laging maaasahan.",
		"icon": "res://art/Slippers/Blue.png",
		"palette": {"sole": Color("374ac0"), "strap": Color("942d73")}},
	{"id": "bakya", "name": "Bakya", "price": 250,
		"desc": "Kahoy na bakya. Maingay kapag tumama.",
		"icon": "res://art/Slippers/Bakya.png",
		"palette": {"sole": Color("734724"), "strap": Color("5a2f0c")}},
	{"id": "purto", "name": "Purto", "price": 250,
		"desc": "Kulay-krema na may ube na tali. Pambahay pero pang-laban.",
		"icon": "res://art/Slippers/Purto.png",
		"palette": {"sole": Color("ddcda5"), "strap": Color("886dec")}},
	{"id": "aylander", "name": "Aylander", "price": 300,
		"desc": "Ang paboritong goma ng buong barangay. Itim, matibay, hindi napipigtas.",
		"icon": "res://art/Slippers/Aylander.png",
		"palette": {"sole": Color("4b445b"), "strap": Color("615663")}},
	{"id": "rabit", "name": "Rabit", "price": 350,
		"desc": "Pink at malambot. Paborito ng mga ate sa kanto.",
		"icon": "res://art/Slippers/Rabit.png",
		"palette": {"sole": Color("e5c9dc"), "strap": Color("a56991")}},
	{"id": "kroks", "name": "Kroks", "price": 600,
		"desc": "Berde, butas-butas, at pang-sosyal sa kanto.",
		"icon": "res://art/Slippers/kroks.png",
		"palette": {"sole": Color("99e550"), "strap": Color("3c911c")}},
	{"id": "enchanted", "name": "Tsinelas na Enchanted", "price": 2000,
		"desc": "Kumikinang sa mahika. Pareho pa rin ang tama, pero iba ang dating.",
		"icon": "res://art/Slippers/Tsinelas na Enchanted.png", "enchanted": true,
		"palette": {"sole": Color("2d2878"), "strap": Color("5fcde4")}},
]

var caps := STARTER_CAPS
var owned := {"totoy": true, "goma": true}
var equipped_character := "totoy"
var equipped_slipper := "goma"
## First-run tutorial finished (or skipped). Cleared by "Replay tutorial" in Settings.
var tutorial_done := false
## One-time gameplay tips already shown ("wind", "squad", "elite").
var tips_seen: Array = []


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


func equipped_slipper_item() -> Dictionary:
	return find_item("slipper", equipped_slipper)


func save_profile() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "caps", caps)
	cfg.set_value("profile", "owned", owned.keys())
	cfg.set_value("profile", "character", equipped_character)
	cfg.set_value("profile", "slipper", equipped_slipper)
	cfg.set_value("progress", "tutorial_done", tutorial_done)
	cfg.set_value("progress", "tips_seen", tips_seen)
	cfg.save(SAVE_PATH)


## A one-time tip: true the first time it's asked for (and remembers it).
func first_time(tip_id: String) -> bool:
	if tips_seen.has(tip_id):
		return false
	tips_seen.append(tip_id)
	save_profile()
	return true


func load_profile() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return # first launch: keep the defaults
	caps = cfg.get_value("profile", "caps", STARTER_CAPS)
	for item_id in cfg.get_value("profile", "owned", []):
		owned[item_id] = true
	equipped_character = cfg.get_value("profile", "character", "totoy")
	equipped_slipper = cfg.get_value("profile", "slipper", "goma")
	tutorial_done = cfg.get_value("progress", "tutorial_done", false)
	tips_seen = cfg.get_value("progress", "tips_seen", [])
