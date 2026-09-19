extends Node2D
class_name StaminaRing
## Zelda-style circular stamina indicator that follows the moth.
## Attach as a child of the Moth node (or instance this scene and set
## `moth` to the Moth in the Inspector). Uses Stamina Empty.png as the
## base ring and Stamina Full.png as the fill, clipped radially to show
## only the filled portion -- same trick BotW's stamina wheel uses.
##
## SETUP:
## 1. Add this as a child scene of Moth (or a sibling that tracks it).
## 2. Set `empty_texture` / `full_texture` in the Inspector to your
##    Stamina Empty.png / Stamina Full.png (drag from FileSystem).
## 3. If your PNGs aren't square/centered, adjust `texture_offset`.

@export var empty_texture: Texture2D
@export var full_texture: Texture2D
@export var moth: CharacterBody2D           # auto-found if left empty
@export var follow_offset := Vector2(0, -46) # above the moth sprite
@export var texture_offset := Vector2.ZERO
@export var ring_scale := 1.0
@export var hide_when_full := true
@export var hide_delay := 1.2                # seconds after reaching full before it fades

var _empty_sprite: Sprite2D
var _full_sprite: Sprite2D
var _hide_timer := 0.0
var _current_alpha := 1.0

func _ready() -> void:
	if not moth:
		moth = get_parent() as CharacterBody2D
		if not moth:
			moth = get_tree().get_first_node_in_group("moth") as CharacterBody2D

	z_index = 50
	scale = Vector2(ring_scale, ring_scale)

	_empty_sprite = Sprite2D.new()
	_empty_sprite.texture = empty_texture
	_empty_sprite.position = texture_offset
	add_child(_empty_sprite)

	_full_sprite = Sprite2D.new()
	_full_sprite.texture = full_texture
	_full_sprite.position = texture_offset
	# Material with a radial clip so it reveals proportionally to stamina,
	# like a pie-chart wipe -- this is what gives the "Zelda circle" look
	# instead of a plain horizontal bar.
	var shader := Shader.new()
	shader.code = _RADIAL_FILL_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("fill_amount", 1.0)
	_full_sprite.material = mat
	add_child(_full_sprite)

	if not moth:
		push_warning("StaminaRing: no Moth found -- assign `moth` in the Inspector.")

func _process(delta: float) -> void:
	if not moth:
		return

	global_position = moth.global_position + follow_offset

	var pct: float = clampf(moth.stamina / moth.max_stamina, 0.0, 1.0)
	var mat := _full_sprite.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("fill_amount", pct)

	if hide_when_full:
		if pct >= 0.999:
			_hide_timer += delta
		else:
			_hide_timer = 0.0
		var target_alpha := 0.0 if _hide_timer > hide_delay else 1.0
		_current_alpha = move_toward(_current_alpha, target_alpha, delta * 3.0)
		modulate.a = _current_alpha
	else:
		modulate.a = 1.0

const _RADIAL_FILL_SHADER := """
shader_type canvas_item;

uniform float fill_amount : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 centered = UV - vec2(0.5);
	// atan gives -PI..PI starting at +X axis; rotate so the wipe starts
	// at the top (12 o'clock) and sweeps clockwise, like a stamina wheel.
	float angle = atan(centered.x, -centered.y);
	float normalized_angle = (angle + PI) / (2.0 * PI);

	vec4 tex_color = texture(TEXTURE, UV);
	if (normalized_angle > fill_amount) {
		tex_color.a = 0.0;
	}
	COLOR = tex_color;
}
"""
