class_name EasterEggs
extends RefCounted
## The five hidden collectibles: a trumpo, a golden
## tsinelas, Lolo's tungkod, a kite and a big marble.
##
## Each one shows up during one round of a normal run (3, 6, 8, 9, 12) at its
## own spot, spread all over the barangay: most sit on a roof you have to
## parkour up to (wooden crates are stacked as steps), one is on the ground in
## an alley. Nothing points at them: they're just there. Picking one up adds
## it to the account's Collection for good, unlocks its achievement, and all
## five unlock the secret rounds after Mama (16 to 25).
##
## Spots are given relative to a house (its lot name and a point in the house
## model's own space), so they follow the house if the layout moves.

## Playtest helper: a tall light over each item that's out and an arrow on the
## HUD pointing at it. Off: the items are properly hidden.
const SHOW_MARKERS := false

## Directions on the map: "north" is the finish-line end of the court, "west"
## is the left side as you face it from the start.
const ITEMS := [
	{"id": "trumpo", "name": "Spinning Top", "round": 3, "achievement": "egg_trumpo",
		"desc": "An old wooden top that still spins like new. Who left it up on a roof?",
		"where": "Round 3: south-west, on the roof of the little tin shack behind the start, past the road.",
		"lot": "HP_40_V5_Shack", "local": Vector3(0.0, 0.0, -1.6), "approach": Vector3(0, 0, 1), "glow": Color(1.0, 0.55, 0.3)},
	{"id": "golden_tsinelas", "name": "Golden Slipper", "round": 6, "achievement": "egg_golden",
		"desc": "Pure gold, supposedly. Not for throwing, strictly for showing off.",
		"where": "Round 6: west, on the side roof of the tall house beside the middle of the court.",
		"lot": "HP_26_V4_Tall", "local": Vector3(2.75, 0.0, -2.75), "approach": Vector3(1, 0, 0), "glow": Color(1.0, 0.82, 0.3)},
	{"id": "tungkod", "name": "Grandpa's Cane", "round": 8, "achievement": "egg_tungkod",
		"desc": "The cane Grandpa never actually uses. Somebody left it in the alley.",
		"where": "Round 8: far north, on the ground behind the little shack past the finish end, near the fence.",
		"lot": "HP_54_V5_Shack", "local": Vector3(0.0, 0.0, -4.6), "glow": Color(0.75, 0.55, 0.35)},
	{"id": "saranggola", "name": "Kite", "round": 9, "achievement": "egg_kite",
		"desc": "Snagged on the kubo's roof after a strong gust of wind.",
		"where": "Round 9: east, on the nipa roof of the kubo across the road from the start.",
		"lot": "HP_30_V9_Kubo", "local": Vector3(0.0, 0.0, 0.3), "approach": Vector3(0, 0, 1), "glow": Color(0.95, 0.35, 0.4)},
	{"id": "holen", "name": "Giant Marble", "round": 12, "achievement": "egg_marble",
		"desc": "The biggest marbles in the neighborhood. Whoever holds them wins every game.",
		"where": "Round 12: far north-east corner, on the very top of the tall brick house.",
		"lot": "HPN_06_V10_Brick", "local": Vector3(1.7, 0.0, -1.2), "approach": Vector3(-1, 0, 0), "glow": Color(0.45, 0.8, 1.0)},
]

## Parkour steps: for each item up on a roof, wooden crates are stacked as a
## staircase from the ground. "approach" (in the house's own space) is the way
## you come from: starting at the item and walking that way, every time the
## surface drops more than you can jump (a roof edge, a lower roof, the
## ground), a row of crates is stacked just past the edge, each about 1 m
## lower than the one before. Built once per game; they stay all the time.
const MAX_HOP := 1.3 ## metres you can always jump up without a crate
const CRATE_STEP := 1.0 ## height difference between neighbouring crates
const CRATE := 1.1

static var _icons := {}


static func find(id: String) -> Dictionary:
	for it in ITEMS:
		if it.id == id:
			return it
	return {}


## The item that comes out in this round, or {} if none.
static func for_round(round_number: int) -> Dictionary:
	for it in ITEMS:
		if int(it.round) == round_number:
			return it
	return {}


# --- Where things go -------------------------------------------------------------

## The item's spot in the world: its house's space -> world, then dropped onto
## whatever is under it (a roof, the ground). Vector3.INF if the house is missing.
static func world_spot(barangay: Node, item: Dictionary) -> Vector3:
	var xf: Transform3D = barangay.house_transform(item.lot)
	if xf == Transform3D():
		return Vector3.INF
	var p: Vector3 = xf * Vector3(item.local.x, 0.0, item.local.z)
	return _drop(barangay, p)


static func _drop(barangay: Node, p: Vector3) -> Vector3:
	var space := (barangay as Node3D).get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 20.0, p + Vector3.DOWN * 2.0, 1)
	var hit := space.intersect_ray(q)
	return hit.position if not hit.is_empty() else p


## The stacked crates, as one static body (wood boxes with collision).
## Returns the body; its "steps" meta lists every crate as [world centre on
## the ground/roof, height] (for the playtest notes).
static func build_steps(barangay: Node) -> Node3D:
	var body := StaticBody3D.new()
	body.name = "ParkourCrates"
	barangay.add_child(body)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.43, 0.24)
	mat.roughness = 0.9
	var band := StandardMaterial3D.new()
	band.albedo_color = Color(0.36, 0.23, 0.12)
	band.roughness = 0.9
	var placed: Array = []
	for it in ITEMS:
		if not it.has("approach"):
			continue
		var xf: Transform3D = barangay.house_transform(it.lot)
		if xf == Transform3D():
			continue
		# The given way in first; if crates can't go there (a wall, a fence,
		# props in the way) try the other sides of the house.
		var plan: Array = []
		var found := false
		for d in [it.approach, Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
			var dir: Vector3 = xf.basis * (d as Vector3)
			dir.y = 0.0
			var res := _plan_stairs(barangay, world_spot(barangay, it), dir.normalized())
			if res.ok:
				plan = res.crates
				found = true
				break
		if not found:
			push_warning("EasterEggs: no way up to %s" % it.id)
		for c in plan:
			_crate_stack(body, c[0], c[1], c[2], mat, band)
			placed.append([c[0], c[1]])
	body.set_meta("steps", placed)
	return body


## Crates from `spot` (an item on a roof) down to the ground, walking `dir`.
## Returns {ok, crates: [[base, height, yaw]]}; ok = it gets all the way down
## with no step higher than MAX_HOP.
static func _plan_stairs(barangay: Node, spot: Vector3, dir: Vector3) -> Dictionary:
	var crates: Array = []
	var yaw := atan2(-dir.x, -dir.z)
	var p := spot
	var top := spot.y
	var guard := 0
	while top > MAX_HOP * 0.5 and guard < 6:
		guard += 1
		# Walk outward until the surface drops away.
		var edge := Vector3.INF
		var low := 0.0
		var d := 0.0
		while d < 14.0:
			d += 0.2
			var q := p + dir * d
			var h := _height_below(barangay, Vector3(q.x, top + 0.4, q.z))
			if h > top + 0.6:
				return {"ok": false, "crates": crates} # a wall in the way
			if h < top - 0.6:
				edge = Vector3(q.x, h, q.z)
				low = h
				break
		if edge == Vector3.INF:
			return {"ok": false, "crates": crates}
		if top - low <= MAX_HOP:
			p = edge
			top = low
			continue
		# Crates just past the edge, stepping down by about a metre each.
		var crate_top := top - 1.05
		var k := 0
		var last := edge
		while crate_top - low > 0.45 and k < 6:
			var c := edge + dir * (0.75 + k * (CRATE + 0.05))
			var ground := _height_below(barangay, Vector3(c.x, top - 0.2, c.z))
			if absf(ground - low) > 0.5:
				return {"ok": false, "crates": crates} # something else is there
			# Room for the crate (and to stand on it).
			for side in [-0.5, 0.5]:
				var sp: Vector3 = c + dir.cross(Vector3.UP) * float(side)
				if absf(_height_below(barangay, Vector3(sp.x, top - 0.2, sp.z)) - low) > 0.5:
					return {"ok": false, "crates": crates}
			crates.append([Vector3(c.x, low, c.z), crate_top - low, yaw + (0.08 if k % 2 else -0.06)])
			last = c
			crate_top -= CRATE_STEP
			k += 1
		p = last + dir * 0.6
		top = low
	return {"ok": top <= MAX_HOP * 0.5 + 0.01, "crates": crates}


## Height of the first solid surface straight below `from`. Nothing there
## means the open ground (y = 0; outside the court its collider only grows
## when the walls come down).
static func _height_below(barangay: Node, from: Vector3) -> float:
	var space := (barangay as Node3D).get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 30.0, 1)
	var hit := space.intersect_ray(q)
	return maxf(hit.position.y, 0.0) if not hit.is_empty() else 0.0


static func _crate_stack(body: StaticBody3D, base: Vector3, height: float, yaw: float, mat: Material, band: Material) -> void:
	var levels := ceili(height - 0.01)
	for k in levels:
		var h := minf(1.0, height - k)
		var rot := Basis(Vector3.UP, yaw + (0.1 if k % 2 else 0.0))
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(CRATE, h, CRATE)
		mi.mesh = bm
		mi.material_override = mat
		mi.transform = Transform3D(rot, base + Vector3(0, k + h * 0.5, 0))
		body.add_child(mi)
		# A dark band round the top so stacked crates read as separate boxes.
		var slat := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(CRATE + 0.02, 0.1, CRATE + 0.02)
		slat.mesh = sm
		slat.material_override = band
		slat.transform = Transform3D(rot, base + Vector3(0, k + h - 0.06, 0))
		body.add_child(slat)
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(CRATE, h, CRATE)
		cs.shape = shape
		cs.transform = mi.transform
		body.add_child(cs)


# --- Looks (placeholders) --------------------------------------------------------

## Pixel icons, 16 x 16, for the Collection page, avatars and pop-ups.
const ICON_ROWS := {
	"trumpo": [
		"................",
		".......KK.......",
		"......wWWw......",
		"....wWWWWWWw....",
		"...wRRRRRRRRw...",
		"..wWWWWWWWWWWw..",
		"..wBBBBBBBBBBw..",
		"..wWWWWWWWWWWw..",
		"...wRRRRRRRRw...",
		"....wWWWWWWw....",
		".....wWWWWw.....",
		"......wWWw......",
		".......ww.......",
		".......KK.......",
		".......KK.......",
		"................",
	],
	"golden_tsinelas": [
		"................",
		"......gggg......",
		".....gGGGGg.....",
		"....gGYGGGGg....",
		"....gGTGGTGg....",
		"....gGGTTGGg....",
		"....gGGTTGGg....",
		"....gGTGGTGg....",
		"....gTGGGGTg....",
		"....gGGGGGGg....",
		"....gGGGGGGg....",
		"....gGYGGGGg....",
		"....gGGGGGGg....",
		".....gGGGGg.....",
		"......gggg......",
		"................",
	],
	"tungkod": [
		"................",
		"......wwww......",
		".....wWWWWw.....",
		"....wW....Ww....",
		"....wW.....Ww...",
		".....w.....Ww...",
		"...........Ww...",
		"...........Ww...",
		"...........Ww...",
		"...........Ww...",
		"...........Ww...",
		"...........Ww...",
		"...........Ww...",
		"...........KK...",
		"...........KK...",
		"................",
	],
	"saranggola": [
		".......RR.......",
		"......RRRR......",
		".....RRRYRR.....",
		"....RRRRYRRR....",
		"...RRRRRYRRRR...",
		"..YYYYYYYYYYYY..",
		"...BBBBBYBBBB...",
		"....BBBBYBBB....",
		".....BBBYBB.....",
		"......BBBB......",
		".......BB.......",
		"........S.......",
		".......S.r......",
		"......r.S.......",
		"........S.r.....",
		".........S......",
	],
	"holen": [
		"................",
		".....oooooo.....",
		"...ooCCCCCCoo...",
		"..oCCWWCCCCCCo..",
		"..oCWWCCCCCCCo..",
		".oCCWCCCRRCCCCo.",
		".oCCCCCRRRRCCCo.",
		".oCCCCRRCCRRCCo.",
		".oCCCCRCCCCRCCo.",
		".oCCCCCRRRRCCCo.",
		".oCCCCCCRRCCCCo.",
		"..oCCCCCCCCCCo..",
		"..ooCCCCCCCCoo..",
		"....oooooooo....",
		"................",
		"................",
	],
}
const ICON_COLORS := {
	"W": Color(0.86, 0.62, 0.36), "w": Color(0.52, 0.32, 0.16), "R": Color(0.9, 0.2, 0.2),
	"B": Color(0.2, 0.42, 0.9), "K": Color(0.62, 0.64, 0.68), "G": Color(1.0, 0.8, 0.22),
	"g": Color(0.7, 0.48, 0.08), "Y": Color(1.0, 0.97, 0.7), "T": Color(0.86, 0.55, 0.1),
	"S": Color(0.95, 0.95, 0.95), "r": Color(1.0, 0.85, 0.2), "o": Color(0.2, 0.42, 0.6),
	"C": Color(0.62, 0.86, 1.0),
}


## The hand-drawn icons (art/ui/Easter egg icons) and 3D models
## (art/Easter Egg assets). Models are scaled so their longest side is
## MODEL_SIZE metres and stood on the ground (y = 0), centred.
const ICON_FILES := {
	"trumpo": "res://art/ui/Easter egg icons/Trumpo.png",
	"golden_tsinelas": "res://art/ui/Easter egg icons/Golden Slipper.png",
	"tungkod": "res://art/ui/Easter egg icons/Cane.png",
	"saranggola": "res://art/ui/Easter egg icons/Kite.png",
	"holen": "res://art/ui/Easter egg icons/Jolen.png",
}
const MODEL_FILES := {
	"trumpo": "res://art/Easter Egg assets/trumpo.glb",
	"golden_tsinelas": "res://art/Easter Egg assets/Golden Tsinelas.glb",
	"tungkod": "res://art/Easter Egg assets/Sungkod.glb",
	"saranggola": "res://art/Easter Egg assets/kite.glb",
	"holen": "res://art/Easter Egg assets/jolens.glb",
}
const MODEL_SIZE := {"trumpo": 0.45, "golden_tsinelas": 0.5, "tungkod": 1.0, "saranggola": 0.8, "holen": 0.6}


## The item's icon, (16 x scale) pixels square; 256 px for scale 1 (big
## enough to shrink cleanly into a profile badge). Falls back to the old
## pixel-art placeholder if the picture is missing.
static func icon(id: String, scale: int = 1) -> Texture2D:
	var key := "%s@%d" % [id, scale]
	if _icons.has(key):
		return _icons[key]
	var path: String = ICON_FILES.get(id, "")
	if path != "" and ResourceLoader.exists(path):
		var src := (load(path) as Texture2D).get_image()
		if src.is_compressed():
			src.decompress()
		src.convert(Image.FORMAT_RGBA8)
		# Crop to the drawing, square, with a little room round it.
		var used := src.get_used_rect()
		var side := int(maxi(used.size.x, used.size.y) * 1.08)
		var sq := Image.create(side, side, false, Image.FORMAT_RGBA8)
		sq.fill(Color(0, 0, 0, 0))
		sq.blit_rect(src, used, Vector2i((side - used.size.x) / 2, (side - used.size.y) / 2))
		var px := 16 * scale if scale > 1 else 256
		sq.resize(px, px, Image.INTERPOLATE_LANCZOS)
		var t := ImageTexture.create_from_image(sq)
		_icons[key] = t
		return t
	var rows: Array = ICON_ROWS.get(id, ICON_ROWS.trumpo)
	var img := PixelArt._image(rows, ICON_COLORS)
	if scale > 1:
		img.resize(img.get_width() * scale, img.get_height() * scale, Image.INTERPOLATE_NEAREST)
	var tex := ImageTexture.create_from_image(img)
	_icons[key] = tex
	return tex


## The item's 3D model (see MODEL_FILES), or the old low-poly stand-in.
static func model(id: String) -> Node3D:
	var path: String = MODEL_FILES.get(id, "")
	if path != "" and ResourceLoader.exists(path):
		var holder := Node3D.new()
		var inst: Node3D = (load(path) as PackedScene).instantiate()
		holder.add_child(inst)
		var box := bounds(inst)
		var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
		if longest > 0.0001:
			var k: float = MODEL_SIZE.get(id, 0.5) / longest
			inst.scale = Vector3.ONE * k
			var c := box.get_center()
			inst.position = Vector3(-c.x * k, -box.position.y * k, -c.z * k)
		return holder
	return _stand_in(id)


## Bounding box of every mesh under `root`, in root's own space.
static func bounds(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var xf := Transform3D()
		var n: Node = m
		while n != root and n is Node3D:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var b := xf * m.mesh.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


## A small low-poly stand-in model, about 0.4 - 0.9 m across.
static func _stand_in(id: String) -> Node3D:
	var root := Node3D.new()
	match id:
		"trumpo":
			_part(root, _cyl(0.2, 0.03, 0.34), _mat(Color(0.86, 0.62, 0.36)), Vector3(0, 0.17, 0))
			_part(root, _cyl(0.205, 0.17, 0.06), _mat(Color(0.9, 0.2, 0.2)), Vector3(0, 0.27, 0))
			_part(root, _cyl(0.17, 0.12, 0.05), _mat(Color(0.2, 0.42, 0.9)), Vector3(0, 0.36, 0))
			_part(root, _cyl(0.05, 0.05, 0.08), _mat(Color(0.52, 0.32, 0.16)), Vector3(0, 0.42, 0))
			_part(root, _cyl(0.015, 0.002, 0.08), _mat(Color(0.7, 0.72, 0.75), 0.8), Vector3(0, -0.03, 0))
		"golden_tsinelas":
			var gold := _mat(Color(1.0, 0.78, 0.2), 0.9, 0.25)
			for side in [-1.0, 1.0]:
				var sole := Node3D.new()
				sole.position = Vector3(0.09 * side, 0.03, 0.0)
				sole.rotation.y = 0.12 * side
				root.add_child(sole)
				_part(sole, _box(Vector3(0.13, 0.035, 0.32)), gold, Vector3.ZERO)
				_part(sole, _box(Vector3(0.02, 0.03, 0.12)), _mat(Color(0.85, 0.5, 0.1), 0.7), Vector3(-0.04, 0.03, -0.03), Vector3(0, 0.6, 0))
				_part(sole, _box(Vector3(0.02, 0.03, 0.12)), _mat(Color(0.85, 0.5, 0.1), 0.7), Vector3(0.04, 0.03, -0.03), Vector3(0, -0.6, 0))
		"tungkod":
			var wood := _mat(Color(0.5, 0.3, 0.14))
			_part(root, _cyl(0.025, 0.025, 0.9), wood, Vector3(0, 0.45, 0))
			var hook := TorusMesh.new()
			hook.inner_radius = 0.07
			hook.outer_radius = 0.12
			hook.rings = 12
			hook.ring_segments = 6
			_part(root, hook, wood, Vector3(-0.095, 0.9, 0), Vector3(PI * 0.5, 0, 0))
			_part(root, _cyl(0.03, 0.03, 0.05), _mat(Color(0.2, 0.2, 0.22)), Vector3(0, 0.02, 0))
		"saranggola":
			var kite := MeshInstance3D.new()
			kite.mesh = _diamond()
			var km := _mat(Color.WHITE)
			km.vertex_color_use_as_albedo = true
			km.cull_mode = BaseMaterial3D.CULL_DISABLED
			kite.material_override = km
			kite.position = Vector3(0, 0.45, 0)
			root.add_child(kite)
			_part(root, _box(Vector3(0.6, 0.015, 0.015)), _mat(Color(0.5, 0.32, 0.16)), Vector3(0, 0.5, 0.01))
			for i in 5:
				_part(root, _box(Vector3(0.06, 0.04, 0.01)), _mat(Color(1.0, 0.85, 0.2) if i % 2 else Color(0.95, 0.95, 0.95)),
						Vector3(0.03 * sin(i * 1.3), 0.1 - i * 0.09, 0.0), Vector3(0, 0, 0.4 * sin(i * 1.7)))
		"holen":
			var glass := _mat(Color(0.62, 0.86, 1.0, 0.55), 0.1, 0.05)
			glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			glass.emission_enabled = true
			glass.emission = Color(0.2, 0.4, 0.6)
			var ball := SphereMesh.new()
			ball.radius = 0.3
			ball.height = 0.6
			ball.radial_segments = 16
			ball.rings = 8
			_part(root, ball, glass, Vector3(0, 0.3, 0))
			var swirl := SphereMesh.new()
			swirl.radius = 0.16
			swirl.height = 0.12
			swirl.radial_segments = 12
			swirl.rings = 4
			_part(root, swirl, _mat(Color(0.95, 0.2, 0.25)), Vector3(0, 0.3, 0), Vector3(0.5, 0, 0.3))
	return root


static func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func _mat(c: Color, metallic: float = 0.0, roughness: float = 0.7) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metallic
	m.roughness = roughness
	return m


static func _cyl(top: float, bottom: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = 12
	c.rings = 1
	return c


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


## Red top half, blue bottom half, standing upright.
static func _diamond() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := Vector3(0, 0.38, 0)
	var bottom := Vector3(0, -0.34, 0)
	var left := Vector3(-0.3, 0.05, 0)
	var right := Vector3(0.3, 0.05, 0)
	var red := Color(0.92, 0.2, 0.22)
	var blue := Color(0.22, 0.42, 0.92)
	for tri in [[top, right, left, red], [left, right, bottom, blue]]:
		st.set_normal(Vector3.BACK)
		for k in 3:
			st.set_color(tri[3])
			st.add_vertex(tri[k])
	return st.commit()


# --- The pickup in the world -------------------------------------------------------

## An item sitting where it was left, turning slowly with a soft pulsing glow
## in its own colour. Emits `collected`
## when the player touches it (once).
class Pickup extends Area3D:
	signal collected(item_id: String)

	var item: Dictionary = {}
	var _model: Node3D
	var _t := 0.0
	var _taken := false
	var _light: OmniLight3D
	var _glow_mats: Array[BaseMaterial3D] = []

	func _ready() -> void:
		monitoring = true
		monitorable = false
		collision_layer = 0
		collision_mask = 0xFFFFFFFF
		var cs := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 1.0
		cs.shape = sphere
		cs.position.y = 0.8
		add_child(cs)
		body_entered.connect(_on_body)
		_model = EasterEggs.model(item.get("id", "trumpo"))
		_model.position.y = 0.05
		add_child(_model)
		# A soft glow in the item's colour: the model shines a little and a small
		# light pulses on the roof around it (no beam: you still have to find it).
		var glow: Color = item.get("glow", Color(1, 0.85, 0.4))
		for node in _model.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if mi.material_override is BaseMaterial3D:
				mi.material_override = _glowing(mi.material_override, glow)
				continue
			if mi.mesh == null:
				continue
			for s in mi.mesh.get_surface_count():
				var src := mi.get_active_material(s)
				if src is BaseMaterial3D:
					mi.set_surface_override_material(s, _glowing(src, glow))
		_light = OmniLight3D.new()
		_light.light_color = glow
		_light.light_energy = 1.2
		_light.omni_range = 2.8
		_light.omni_attenuation = 1.6
		_light.shadow_enabled = false
		_light.position.y = 0.6
		add_child(_light)

	func _glowing(src: Material, glow: Color) -> BaseMaterial3D:
		var m := src.duplicate() as BaseMaterial3D
		m.emission_enabled = true
		m.emission = glow
		m.emission_energy_multiplier = 0.35
		_glow_mats.append(m)
		return m

	func _process(delta: float) -> void:
		_t += delta
		if _model:
			_model.rotation.y += delta * 0.6 # a slow turn, so it catches the eye up close
		var pulse := 0.5 + 0.5 * sin(_t * 2.4)
		if _light:
			_light.light_energy = 0.9 + 0.6 * pulse
		for m in _glow_mats:
			m.emission_energy_multiplier = 0.25 + 0.35 * pulse

	func _on_body(body: Node) -> void:
		if _taken or not body.is_in_group("player"):
			return
		_taken = true
		collected.emit(item.id)
		# Zip up and shrink away.
		var tw := create_tween().set_parallel()
		tw.tween_property(_model, "position:y", 2.2, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_property(_model, "scale", Vector3.ONE * 0.05, 0.45)
		tw.tween_property(_light, "light_energy", 0.0, 0.45)
		tw.chain().tween_callback(queue_free)
