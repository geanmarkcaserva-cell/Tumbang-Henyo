class_name Enchant
extends RefCounted
## Minecraft-style enchantment glint for items flagged "enchanted" in the
## catalog (e.g. Tsinelas na Enchanted). One look for both places a slipper
## shows up: the 2D slipper art in weapon select and the 3D thrown tsinelas.

const MESH_SHADER := preload("res://scenes/game/enchant_mesh.gdshader")
const CANVAS_SHADER := preload("res://scenes/game/enchant_canvas.gdshader")


static func is_enchanted(item: Dictionary) -> bool:
	return item.get("enchanted", false)


## Put the glint on a 2D item (TextureRect, Sprite2D), or take it off.
static func apply_to_canvas(item: CanvasItem, enchanted: bool) -> void:
	if not enchanted:
		item.material = null
		return
	var mat := ShaderMaterial.new()
	mat.shader = CANVAS_SHADER
	mat.set_shader_parameter("glint_strength", 0.8)
	item.material = mat


## Add the glint as an extra pass on a mesh's material.
static func apply_to_mesh(mesh: MeshInstance3D) -> void:
	var base := mesh.material_override
	if base == null:
		base = StandardMaterial3D.new()
		mesh.material_override = base
	var glint := ShaderMaterial.new()
	glint.shader = MESH_SHADER
	base.next_pass = glint
