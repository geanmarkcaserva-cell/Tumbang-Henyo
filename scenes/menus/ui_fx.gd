class_name UiFx
extends RefCounted
## Bouncy UI motion and the overall UI size, shared by the menus and the HUD.
##
## - shrink(): makes a screen's UI a bit smaller. Each piece shrinks toward
##   the screen edge or corner it sits near, so margins stay put.
## - pop_in(): pieces of a panel spring in one after another (overshoot and
##   settle) when the panel opens.
## - hookup_button(): buttons grow a little on hover, squash when pressed and
##   spring back on release.
## - bounce() / shake() / idle_float(): one-off punches, "wrong" wiggles and a
##   gentle breathing loop for logos.
##
## Pieces keep their resting scale in the "fx_base" meta so the effects scale
## around it. Set the "fx_skip" meta on a node to leave it alone.

const UI_SCALE := 0.82 ## overall size of menus and HUD (1 = original size)
const DESIGN := Vector2(1920, 1080) ## the layouts are drawn for this screen size


static func base_of(c: CanvasItem) -> Vector2:
	return c.get_meta("fx_base", Vector2.ONE)


# --- Size ---------------------------------------------------------------------

## Shrink every piece under `parent` (a full-screen Control or a CanvasLayer).
## Full-screen plain Controls are looked into; everything else is scaled
## toward its nearest screen edge or corner.
static func shrink(parent: Node, factor: float = UI_SCALE) -> void:
	for child in parent.get_children():
		var c := child as Control
		if c == null or c.has_meta("fx_skip"):
			continue
		if _is_full_rect(c) and not (c is Container):
			shrink(c, factor)
		else:
			_pin(c, factor)


static func _is_full_rect(c: Control) -> bool:
	return is_equal_approx(c.anchor_left, 0.0) and is_equal_approx(c.anchor_top, 0.0) \
			and is_equal_approx(c.anchor_right, 1.0) and is_equal_approx(c.anchor_bottom, 1.0)


static func _pin(c: Control, factor: float) -> void:
	c.set_meta("fx_base", Vector2.ONE * factor)
	c.set_meta("fx_pivot_locked", true)
	c.scale = Vector2.ONE * factor
	_update_pin_pivot(c)
	if not c.has_meta("fx_pin_hooked"):
		c.set_meta("fx_pin_hooked", true)
		c.resized.connect(_update_pin_pivot.bind(c))


## Pivot on the side of the piece that is close to a screen edge: a piece
## starting in the left quarter shrinks toward the left, one ending in the
## right quarter toward the right; pieces spanning both (or neither) shrink
## toward their middle. Same for top and bottom.
static func _update_pin_pivot(c: Control) -> void:
	var r := c.get_rect()
	c.pivot_offset = c.size * Vector2(_edge(r.position.x, r.end.x, DESIGN.x), _edge(r.position.y, r.end.y, DESIGN.y))


static func _edge(start: float, end: float, span: float) -> float:
	var near_start := start < span * 0.25
	var near_end := end > span * 0.75
	if near_start and not near_end:
		return 0.0
	if near_end and not near_start:
		return 1.0
	return 0.5


static func _centre_pivot(c: Control) -> void:
	if c.has_meta("fx_pivot_locked"):
		return
	c.pivot_offset = c.size * 0.5
	if not c.has_meta("fx_pivot_hooked"):
		c.set_meta("fx_pivot_hooked", true)
		c.resized.connect(_recentre.bind(c))


static func _recentre(c: Control) -> void:
	if not c.has_meta("fx_pivot_locked"):
		c.pivot_offset = c.size * 0.5


# --- Motion -------------------------------------------------------------------

static func _kill_meta_tween(c: Object, key: String) -> void:
	if c.has_meta(key):
		var old: Tween = c.get_meta(key)
		if old and old.is_valid():
			old.kill()


static func _new_tween(c: CanvasItem) -> Tween:
	_kill_meta_tween(c, "fx_tween")
	var t := c.create_tween()
	c.set_meta("fx_tween", t)
	return t


## Spring one piece in: fades up from `from` of its size, overshoots, settles.
static func pop(c: Control, delay: float = 0.0, from: float = 0.55, duration: float = 0.5) -> void:
	if c.has_meta("fx_skip"):
		return
	_centre_pivot(c)
	var base := base_of(c)
	c.scale = base * from
	c.modulate.a = 0.0
	var t := _new_tween(c).set_parallel(true)
	t.tween_property(c, "modulate:a", 1.0, duration * 0.4).set_delay(delay)
	t.tween_property(c, "scale", base, duration).set_delay(delay) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Open a panel: its pieces pop in one after another, and the items inside a
## piece's list (buttons in a column, rows in a box) follow in a cascade.
static func pop_in(root: Node, start_delay: float = 0.0) -> void:
	var i := 0
	for child in root.get_children():
		var c := child as Control
		if c == null or not c.visible or c.has_meta("fx_skip") or c.has_meta("fx_custom"):
			continue
		if _is_full_rect(c) and not (c is Container):
			if c is ColorRect: # a dim backdrop fades in under its panel
				var a := (c as ColorRect).modulate.a
				c.modulate.a = 0.0
				c.create_tween().tween_property(c, "modulate:a", maxf(a, 1.0), 0.2)
			pop_in(c, start_delay + i * 0.05) # look inside
			i += 1
			continue
		var d := start_delay + i * 0.06
		pop(c, d)
		var items := _list_items(c)
		for j in items.size():
			pop(items[j], d + 0.08 + j * 0.05, 0.7, 0.45)
		i += 1


## The items of a list inside `c`: digs through single-child wrappers
## (panel -> margin -> column) to the first box container.
static func _list_items(c: Control) -> Array[Control]:
	var out: Array[Control] = []
	var node: Node = c
	for depth in 4:
		if node is BoxContainer or node is GridContainer:
			for k in node.get_children():
				if k is Control and k.visible:
					out.append(k)
			return out
		if node is Container and node.get_child_count() >= 1:
			node = node.get_child(0)
		else:
			break
	return out


## A quick punch: grows to `amount` and springs back (score ticks, "Tama!").
static func bounce(c: Control, amount: float = 1.18, duration: float = 0.5) -> void:
	_centre_pivot(c)
	var base := base_of(c)
	var t := _new_tween(c)
	t.tween_property(c, "scale", base * amount, duration * 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(c, "scale", base, duration * 0.82).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## A "no" wiggle (wrong answer).
static func shake(c: Control, strength_deg: float = 4.0) -> void:
	_centre_pivot(c)
	var t := c.create_tween()
	for k in [1.0, -1.0, 0.7, -0.5, 0.25, 0.0]:
		t.tween_property(c, "rotation", deg_to_rad(strength_deg * k), 0.05)


## Gentle breathing and sway, forever (logos, mascots).
static func idle_float(c: Control, amount: float = 0.025, period: float = 2.6) -> void:
	var base := base_of(c)
	var t := c.create_tween().set_loops()
	t.tween_property(c, "scale", base * (1.0 + amount), period * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(c, "scale", base * (1.0 - amount * 0.4), period * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var r := c.create_tween().set_loops()
	r.tween_property(c, "rotation", deg_to_rad(1.2), period * 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	r.tween_property(c, "rotation", deg_to_rad(-1.2), period * 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Logo entrance: drops in big and wobbles into place (elastic), then breathes.
static func logo_intro(c: Control, delay: float = 0.0) -> void:
	_centre_pivot(c)
	var base := base_of(c)
	for key in ["fx_tween", "fx_idle_a", "fx_idle_b"]:
		_kill_meta_tween(c, key)
	c.scale = base * 0.3
	c.rotation = deg_to_rad(-8.0)
	c.modulate.a = 0.0
	var t := c.create_tween().set_parallel(true)
	c.set_meta("fx_tween", t)
	t.tween_property(c, "modulate:a", 1.0, 0.25).set_delay(delay)
	t.tween_property(c, "scale", base, 1.1).set_delay(delay).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	t.tween_property(c, "rotation", 0.0, 0.9).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.chain().tween_callback(func():
		var a := c.create_tween().set_loops()
		a.tween_property(c, "scale", base * 1.025, 1.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		a.tween_property(c, "scale", base * 0.99, 1.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		var b := c.create_tween().set_loops()
		b.tween_property(c, "rotation", deg_to_rad(1.0), 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		b.tween_property(c, "rotation", deg_to_rad(-1.0), 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		c.set_meta("fx_idle_a", a)
		c.set_meta("fx_idle_b", b))


# --- Buttons ------------------------------------------------------------------

## Hover grows a little, press squashes, release springs back.
static func hookup_button(b: BaseButton) -> void:
	if b.has_meta("fx_button"):
		return
	b.set_meta("fx_button", true)
	_centre_pivot(b)
	b.mouse_entered.connect(func():
		if not b.disabled:
			_spring(b, 1.07, 0.18, Tween.TRANS_BACK))
	b.mouse_exited.connect(func(): _spring(b, 1.0, 0.2, Tween.TRANS_QUAD))
	b.button_down.connect(func(): _spring(b, 0.9, 0.07, Tween.TRANS_QUAD))
	b.button_up.connect(func():
		_spring(b, 1.07 if b.is_hovered() else 1.0, 0.45, Tween.TRANS_ELASTIC))


static func _spring(c: Control, mult: float, duration: float, trans: Tween.TransitionType) -> void:
	var t := _new_tween(c)
	t.tween_property(c, "scale", base_of(c) * mult, duration).set_trans(trans).set_ease(Tween.EASE_OUT)
