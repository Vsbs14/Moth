extends Light
class_name PlainLight

@export var lit_texture: Texture2D
@export var unlit_texture: Texture2D

@onready var sprite: Sprite2D = get_node_or_null("Sprite2D")

func _ready() -> void:
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
