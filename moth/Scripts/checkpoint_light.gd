extends Light
class_name CheckpointLight

## Red until reached, then turns green, saves progress, and becomes
## the moth's respawn point. Doesn't pull once it's already been hit,
## so the player isn't yanked back to an old checkpoint.

@onready var sprite: Sprite2D = $Sprite2D  # swap for AnimatedSprite2D if needed
@export var red_texture: Texture2D
@export var green_texture: Texture2D

## Emitted when this checkpoint is hit for the first time. Connect this
## to a GameState/respawn system once you build one — kept as a signal
## instead of a hard autoload reference so this script has no dependency
## on systems that don't exist yet.
signal checkpoint_reached(position: Vector2)

var reached := false

func _ready() -> void:
	can_toggle = false
	super._ready()
	if sprite and red_texture:
		sprite.texture = red_texture

func on_moth_reached(moth: Node) -> void:
	if reached:
		return
	reached = true
	if sprite and green_texture:
		sprite.texture = green_texture
	checkpoint_reached.emit(global_position)

func is_attracting() -> bool:
	# Once you've hit this checkpoint, it stops competing for the pull —
	# no reason to keep getting dragged toward lights behind you.
	return is_active and not reached
