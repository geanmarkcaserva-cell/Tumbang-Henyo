extends Node
## Tansan (bottlecap) balance, the character and slipper catalog, what the
## player owns and has equipped, and the player's lifetime stats. Saved per
## account: Accounts.path("profile.cfg").
## Characters and slippers are cosmetic only (GDD: Characters and slippers).

signal caps_changed(value: int)

const SAVE_FILE := "profile.cfg"
## New profiles start with a few caps so buying can be tested. Set to 0 for launch.
const STARTER_CAPS := 200

const CHARACTERS := [
	## Hand-drawn character: "sprite" names its folder. Every character uses
	## three sheets there (see PixelArt.character_look): idle (front), run
	## (back view) and happy, each a horizontal strip of square frames, named
	## <id>_idle.png etc. unless "idle"/"run"/"happy" give the file names.
	## The palette is only a fallback. "requires": something to do before it
	## can be bought ("beat_tanods": get home before the 7 PM curfew).
	## Proktoy is the free starter.
	{"id": "proktoy", "name": "Proktoy", "price": 0,
		"desc": "Wild hair, a headband and eyes that never blink. Always ready for a chase, mostly because he's always the one being chased.",
		"palette": {"hair": Color(0.12, 0.09, 0.08), "skin": Color(0.98, 0.78, 0.72), "shirt": Color(0.2, 0.18, 0.16),
			"accent": Color(0.92, 0.92, 0.95), "pants": Color(0.2, 0.18, 0.16), "feet": Color(0.15, 0.15, 0.2)},
		"sprite": {"dir": "res://art/characters/Proktoy", "idle": "Proktoy idle.png", "run": "Proktoy back.png", "happy": "Proktoy happy.png"}},
	{"id": "gm", "name": "GM", "price": 1000,
		"desc": "The barangay's resident genius, never without an answer (or that one stubborn strand of hair). Wherever he goes, Ashiela, his other half, is never far behind.",
		"palette": {"hair": Color(0.05, 0.05, 0.06), "skin": Color(0.98, 0.84, 0.72), "shirt": Color(0.08, 0.1, 0.2),
			"accent": Color(0.85, 0.15, 0.15), "pants": Color(0.08, 0.1, 0.2), "feet": Color(0.05, 0.05, 0.08)},
		"sprite": {"dir": "res://art/characters/gm", "pixel_size": 0.095}},
	## The barkada (art/characters/<Name>): sheets keep the artist's file names.
	## Sheets saved at 10x (240 px frames) are scaled down automatically.
	{"id": "kei", "name": "Kei", "price": 200,
		"desc": "Long hair, even longer patience. Never in a hurry, yet somehow always the first one home.",
		"palette": {"hair": Color(0.95, 0.6, 0.65), "skin": Color(0.98, 0.84, 0.72), "shirt": Color(0.7, 0.85, 0.45),
			"accent": Color(0.95, 0.9, 0.5), "pants": Color(0.95, 0.9, 0.5), "feet": Color(0.9, 0.85, 0.5)},
		"sprite": {"dir": "res://art/characters/Kei", "idle": "kei-idlesheet.png", "run": "kei-backsheet.png", "happy": "kei-happisheet.png"}},
	{"id": "lisa", "name": "Lisa", "price": 250,
		"desc": "Curly pink hair and a star clip that never sits crooked. She's always the first to yell \"Tumba!\"",
		"palette": {"hair": Color(0.85, 0.25, 0.5), "skin": Color(0.98, 0.84, 0.72), "shirt": Color(0.35, 0.65, 0.25),
			"accent": Color(1.0, 0.8, 0.2), "pants": Color(0.35, 0.65, 0.25), "feet": Color(0.9, 0.85, 0.8)},
		"sprite": {"dir": "res://art/characters/Lisa", "idle": "Lisa-Idle Sheet.png", "run": "Lisa - Back-Sheet.png", "happy": "Lisa - Happy-Sheet.png"}},
	{"id": "badette", "name": "Badette", "price": 250,
		"desc": "Pink hair, full glam, and the loudest \"Ay, ganda!\" on the court. He runs like it's a runway and throws like it's a mic drop.",
		"palette": {"hair": Color(0.9, 0.2, 0.5), "skin": Color(0.5, 0.32, 0.22), "shirt": Color(0.15, 0.45, 0.3),
			"accent": Color(0.8, 0.2, 0.2), "pants": Color(0.15, 0.15, 0.3), "feet": Color(0.4, 0.25, 0.15)},
		"sprite": {"dir": "res://art/characters/Badette", "idle": "Badette - Idle-Sheet.png", "run": "Badette - Back-Sheet.png", "happy": "Badette-Happy Sheet.png"}},
	{"id": "migo", "name": "Migo", "price": 300,
		"desc": "Bandana on, all in black, barely says a word. Quiet hands, but his throws never miss.",
		"palette": {"hair": Color(0.1, 0.1, 0.15), "skin": Color(0.95, 0.78, 0.68), "shirt": Color(0.12, 0.12, 0.14),
			"accent": Color(0.9, 0.9, 0.9), "pants": Color(0.12, 0.12, 0.14), "feet": Color(0.1, 0.1, 0.1)},
		"sprite": {"dir": "res://art/characters/Migo", "idle": "EMAN idle-Sheet.png", "run": "EMAN back-Sheet.png", "happy": "EMAN - happy-Sheet.png"}},
	{"id": "saisai", "name": "Sai Sai", "price": 400,
		"desc": "Knee-length blue hair and a red ribbon you can spot from across the court. Don't let the cute face fool you.",
		"palette": {"hair": Color(0.3, 0.75, 0.9), "skin": Color(0.98, 0.8, 0.65), "shirt": Color(0.9, 0.35, 0.4),
			"accent": Color(0.85, 0.15, 0.2), "pants": Color(0.7, 0.7, 0.72), "feet": Color(0.95, 0.85, 0.75)},
		"sprite": {"dir": "res://art/characters/Sai Sai", "idle": "sai sai front idle-Sheet.png", "run": "sai sai back idle-Sheet.png", "happy": "sai sai happy-Sheet.png"}},
	{"id": "ashiela", "name": "Ashiela", "price": 1000, "requires": "beat_tanods",
		"desc": "Quiet, sharp-eyed, always in black and red, and you won't notice her until you're the taya. She never strays far from GM, her other half.",
		"palette": {"hair": Color(0.18, 0.12, 0.1), "skin": Color(0.95, 0.8, 0.68), "shirt": Color(0.1, 0.1, 0.16),
			"accent": Color(0.8, 0.12, 0.15), "pants": Color(0.12, 0.12, 0.2), "feet": Color(0.6, 0.7, 0.9)},
		"sprite": {"dir": "res://art/characters/Ashiela", "idle": "Ashiela Idle.png", "run": "Ashiela back.png", "happy": "Ashiela happy.png"}},
]

## Every slipper is a hand-drawn sprite in art/Slippers ("icon"), shown as-is
## in weapon select. "palette" colours the 3D tsinelas in-game, picked from
## the sprite's mid tones (the 3D view is lit and tone-mapped, so the art's
## darkest colours would come out near black). "enchanted" adds the
## Minecraft-style purple glint (see Enchant). Items without an icon fall back
## to a generated placeholder. "wind_resist" (0..1): how much less the wind
## pushes it (Bakya the most; the Enchanted one isn't pushed at all).
const SLIPPERS := [
	{"id": "goma", "name": "Blue na Tsinelas", "price": 0, "wind_resist": 0.0,
		"desc": "The classic blue rubber slipper, light and dependable. The wind pushes it around the most.",
		"icon": "res://art/Slippers/Blue.png",
		"palette": {"sole": Color("374ac0"), "strap": Color("942d73")}},
	{"id": "bakya", "name": "Bakya", "price": 250, "wind_resist": 0.7,
		"desc": "A solid wooden clog that clacks when it lands. Heavy enough to shrug off almost any wind.",
		"icon": "res://art/Slippers/Bakya.png",
		"palette": {"sole": Color("734724"), "strap": Color("5a2f0c")}},
	{"id": "purto", "name": "Purto", "price": 250, "wind_resist": 0.15,
		"desc": "Cream with a purple strap, made for the house but ready for a fight. A little steadier than plain rubber.",
		"icon": "res://art/Slippers/Purto.png",
		"palette": {"sole": Color("ddcda5"), "strap": Color("886dec")}},
	{"id": "aylander", "name": "Aylander", "price": 300, "wind_resist": 0.35,
		"desc": "The barangay's favorite black rubber slipper: thick, tough and never snaps. Its weight keeps it steady in a breeze.",
		"icon": "res://art/Slippers/Aylander.png",
		"palette": {"sole": Color("4b445b"), "strap": Color("615663")}},
	{"id": "rabit", "name": "Rabit", "price": 350, "wind_resist": 0.05,
		"desc": "Soft, pink and fluffy, the favorite of every ate on the corner. Light as a feather, so the wind loves it too.",
		"icon": "res://art/Slippers/Rabit.png",
		"palette": {"sole": Color("e5c9dc"), "strap": Color("a56991")}},
	{"id": "kroks", "name": "Kroks", "price": 600, "wind_resist": 0.25,
		"desc": "Green, full of holes and fancy for the neighborhood. The holes let a little wind slip through.",
		"icon": "res://art/Slippers/kroks.png",
		"palette": {"sole": Color("99e550"), "strap": Color("3c911c")}},
	{"id": "enchanted", "name": "Tsinelas na Enchanted", "price": 2000, "wind_resist": 1.0,
		"desc": "Shimmering with magic: it hits just as hard, but with more style. No wind can touch it.",
		"icon": "res://art/Slippers/Tsinelas na Enchanted.png", "enchanted": true,
		"palette": {"sole": Color("2d2878"), "strap": Color("5fcde4")}},
]

var caps := STARTER_CAPS
var owned := {"proktoy": true, "goma": true}
var equipped_character := "proktoy"
var equipped_slipper := "goma"
## First-run tutorial finished (or skipped). Cleared by "Replay tutorial" in Settings.
var tutorial_done := false
## Got home before the tanods at curfew (round 25) at least once: Ashiela can be bought.
var beat_tanods := false
## One-time gameplay tips already shown ("wind", "squad", "elite").
var tips_seen: Array = []
## Lifetime stats for the account card: games, wins (made it home before Mama),
## highest_round, bullseyes, play_seconds, best = {theme: score}.
var stats := {}
## Easter-egg items found (ids from EasterEggs.ITEMS), kept for good.
var collection: Array = []

signal collected(item_id: String)


func _ready() -> void:
	load_profile()


## PLAYTEST: owned without buying, on every account. Empty this before release.
const PLAYTEST_OWNED := ["ashiela"]


func owns(item_id: String) -> bool:
	if owned.has(item_id) or PLAYTEST_OWNED.has(item_id):
		return true
	# Free items are always yours (also on saves made before they existed).
	for kind in ["character", "slipper"]:
		for item in catalog(kind):
			if item.id == item_id and item.price == 0:
				return true
	return false


func can_afford(price: int) -> bool:
	return caps >= price


## Whether an item's "requires" is done (always true when it has none).
func requirement_met(item_id: String) -> bool:
	for kind in ["character", "slipper"]:
		for it in catalog(kind):
			if it.id == item_id:
				match String(it.get("requires", "")):
					"beat_tanods":
						return beat_tanods
	return true


## What to do first, in words ("" when nothing).
func requirement_text(item_id: String) -> String:
	for it in CHARACTERS:
		if it.id == item_id and String(it.get("requires", "")) == "beat_tanods":
			return "Beat the tanods first"
	return ""


## Spend caps on an item. Returns false if it can't be bought.
func buy(item_id: String, price: int) -> bool:
	if owns(item_id) or not can_afford(price) or not requirement_met(item_id):
		return false
	caps -= price
	owned[item_id] = true
	save_profile()
	caps_changed.emit(caps)
	Achievements.unlock("shopper")
	_shop_achievements(item_id)
	return true


## Collecting characters and tsinelas, and the couple (GM and Ashiela).
## Only what was really bought or is free counts (not playtest unlocks).
func _shop_achievements(bought_id: String) -> void:
	var is_char := false
	for c in CHARACTERS:
		if c.id == bought_id:
			is_char = true
	if is_char:
		Achievements.unlock("new_friend")
	else:
		Achievements.unlock("fresh_pair")
	var chars := _really_owned(CHARACTERS)
	if chars >= 4:
		Achievements.unlock("barkada")
	if chars >= CHARACTERS.size():
		Achievements.unlock("whole_barkada")
	var slips := _really_owned(SLIPPERS)
	if slips >= 4:
		Achievements.unlock("shoe_rack")
	if slips >= SLIPPERS.size():
		Achievements.unlock("tsinelas_collector")
	if owned.has("gm") or owned.has("ashiela"):
		Achievements.unlock("half_heart")
	if owned.has("gm") and owned.has("ashiela"):
		Achievements.unlock("full_heart")


func _really_owned(list: Array) -> int:
	var n := 0
	for it in list:
		if owned.has(it.id) or int(it.price) == 0:
			n += 1
	return n


func add_caps(amount: int) -> void:
	caps += amount
	caps_changed.emit(caps)
	if caps >= 1000:
		Achievements.unlock("collector")


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


## The hand-drawn playable characters (the ones with a "sprite"): the tayas
## wear these, so it looks like the whole barkada is out playing.
func sprite_characters() -> Array:
	var out := []
	for c in CHARACTERS:
		if c.has("sprite"):
			out.append(c)
	return out


func find_item(kind: String, item_id: String) -> Dictionary:
	for item in catalog(kind):
		if item.id == item_id:
			return item
	return catalog(kind)[0]


## Found an easter-egg item. Returns true if it's new for this account.
func collect(item_id: String) -> bool:
	if collection.has(item_id):
		return false
	collection.append(item_id)
	save_profile()
	collected.emit(item_id)
	return true


func has_collected(item_id: String) -> bool:
	return collection.has(item_id)


## All five easter eggs found: the secret rounds after Mama are open.
func has_all_eggs() -> bool:
	for it in EasterEggs.ITEMS:
		if not collection.has(it.id):
			return false
	return true


## How much less the wind pushes the equipped slipper (0 = fully, 1 = not at all).
func wind_resist() -> float:
	return float(equipped_slipper_item().get("wind_resist", 0.0))


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
	cfg.set_value("progress", "beat_tanods", beat_tanods)
	cfg.set_value("stats", "all", stats)
	cfg.set_value("collection", "items", collection)
	cfg.save(Accounts.path(SAVE_FILE))


## A finished run, for the account's stats card.
func record_run(theme_id: String, score: int, rounds: int, won: bool, bullseyes: int, seconds: float) -> void:
	stats["games"] = int(stats.get("games", 0)) + 1
	if won:
		stats["wins"] = int(stats.get("wins", 0)) + 1
	stats["highest_round"] = maxi(int(stats.get("highest_round", 0)), rounds)
	stats["bullseyes"] = int(stats.get("bullseyes", 0)) + bullseyes
	stats["play_seconds"] = int(stats.get("play_seconds", 0)) + int(seconds)
	var best: Dictionary = stats.get("best", {})
	best[theme_id] = maxi(int(best.get(theme_id, 0)), score)
	stats["best"] = best
	save_profile()


## A one-time tip: true the first time it's asked for (and remembers it).
func first_time(tip_id: String) -> bool:
	if tips_seen.has(tip_id):
		return false
	tips_seen.append(tip_id)
	save_profile()
	return true


## Load the current account's profile (also used when switching accounts).
func load_profile() -> void:
	# Start from a fresh profile, then fill in what's saved.
	caps = STARTER_CAPS
	owned = {"proktoy": true, "goma": true}
	equipped_character = "proktoy"
	equipped_slipper = "goma"
	tutorial_done = false
	tips_seen = []
	beat_tanods = false
	stats = {}
	collection = []
	var cfg := ConfigFile.new()
	if cfg.load(Accounts.path(SAVE_FILE)) != OK:
		caps_changed.emit(caps)
		return # new account: keep the defaults
	caps = cfg.get_value("profile", "caps", STARTER_CAPS)
	for item_id in cfg.get_value("profile", "owned", []):
		owned[item_id] = true
	equipped_character = cfg.get_value("profile", "character", "proktoy")
	if find_item("character", equipped_character).id != equipped_character or not owns(equipped_character):
		equipped_character = "proktoy" # gone from the game, or not free any more
	equipped_slipper = cfg.get_value("profile", "slipper", "goma")
	tutorial_done = cfg.get_value("progress", "tutorial_done", false)
	beat_tanods = cfg.get_value("progress", "beat_tanods", false)
	tips_seen = cfg.get_value("progress", "tips_seen", [])
	stats = cfg.get_value("stats", "all", {})
	collection = cfg.get_value("collection", "items", [])
	caps_changed.emit(caps)
