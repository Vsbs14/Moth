extends Light
class_name ZapperLight

## Instant death if the moth reaches it. Cannot be toggled off —
## it's a fixed hazard you have to Resist your way past.

@export var death_particles: PackedScene

func _ready() -> void:
	can_toggle = false
	super._ready()

func on_moth_reached(moth: Node) -> void:
	if death_particles:
		var fx = death_particles.instantiate()
		get_tree().current_scene.add_child(fx)
		fx.global_position = moth.global_position
	if moth.has_method("die"):
		moth.die()
