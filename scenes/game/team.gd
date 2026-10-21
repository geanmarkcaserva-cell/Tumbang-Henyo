class_name Team
extends RefCounted
## The people who made Tumbang Henyo. Each has a sprite in art/characters/Team
## (their photo head on a pixel body). They stand in a row on the street west of the court
## in the menu (Credits zooms in on each one) and stroll around the barangay
## like the NPCs during a game, with their nickname over their head.

const SHEET_DIR := "res://art/characters/Team/"

const MEMBERS := [
	{"id": "gm", "name": "Gean Mark Caserva", "nick": "GM", "title": "Team Leader",
		"roles": ["Game idea + GDD", "Code control", "3D models", "Assets and illustrations",
			"Trailer animation", "Sound design (SFX + BGM)"],
		"spot": Vector3(-16.4, 0.0, -36.3)},
	{"id": "renkoy", "name": "Renk Europeo", "nick": "Renkoy", "title": "Coach",
		"roles": ["Prototype draft", "Database prototype and concepts", "Quality control", "Code control"],
		"spot": Vector3(-18.7, 0.0, -37.0)},
	{"id": "johannna", "name": "Johu Luste", "nick": "Johannna", "title": "Artist",
		"roles": ["Additional concepts", "3D models", "Assets and illustrations"],
		"spot": Vector3(-14.1, 0.0, -36.9)},
	{"id": "ekkido", "name": "Eichied Europeo", "nick": "ekkido", "title": "Artist",
		"roles": ["3D models", "Assets and illustrations"],
		"spot": Vector3(-11.8, 0.0, -36.6)},
	{"id": "wanix", "name": "Dwan Mitch Caspe", "nick": "Wanix", "title": "Artist",
		"roles": ["3D models", "Assets and illustrations"],
		"spot": Vector3(-21.0, 0.0, -36.6)},
]


static func sheet(member: Dictionary) -> String:
	return SHEET_DIR + String(member.id) + ".png"


## Members whose sprite is in the project.
static func present() -> Array:
	return MEMBERS.filter(func(m): return ResourceLoader.exists(sheet(m)))
