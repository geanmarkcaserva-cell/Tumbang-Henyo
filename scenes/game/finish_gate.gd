class_name FinishGate
extends Node3D
## The FINISH pad at the far end of the court (art/finish/finish_gate.glb,
## built in Blender by art/finish/build_finish_gate.py): a white-rimmed cyan
## pad with FINISH on it and a soft light curtain rising round its back and
## sides. The curtain and the glow on the ground are see-through and gently
## pulse, never bright enough to hide what's behind them.

const SCENE_PATH := "res://art/finish/finish_gate.glb"
const CURTAIN_ALPHA := 0.8 ## on top of the texture's own fade (max ~0.6 at the bottom)

var _soft: Array[StandardMaterial3D] = []
var _t := 0.0


func _ready() -> void:
	if not ResourceLoader.exists(SCENE_PATH):
		return
	var gate: Node3D = (load(SCENE_PATH) as PackedScene).instantiate()
	add_child(gate)
	for mi in gate.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var n := String(m.name).to_lower()
		if not ("curtain" in n or "halo" in n):
			continue
		var src := m.get_active_material(0) as BaseMaterial3D
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.albedo_texture = src.albedo_texture if src else null
		mat.albedo_color = Color(1, 1, 1, CURTAIN_ALPHA)
		mat.render_priority = 1 if "curtain" in n else 0
		m.material_override = mat
		_soft.append(mat)


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	var a := CURTAIN_ALPHA * (0.85 + 0.15 * sin(_t * 1.7))
	for mat in _soft:
		mat.albedo_color.a = a
		if mat.render_priority == 1:
			mat.uv1_offset.x = fmod(_t * 0.03, 1.0) # the curtain's streaks drift slowly sideways
