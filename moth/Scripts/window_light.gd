extends Light
class_name WindowLight

@export var lit_texture: Texture2D
@export var unlit_texture: Texture2D

@onready var sprite: Sprite2D = get_node_or_null("Sprite2D")

func _ready() -> void:
	pull_strength = 0.0
	can_toggle = true
	super._ready()
	_apply_texture()

func _on_toggled() -> void:
	_apply_texture()

func _apply_texture() -> void:
	if not sprite:
		return
	var tex := lit_texture if is_active else unlit_texture
	if tex:
		sprite.texture = tex
