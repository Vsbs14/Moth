extends Area2D
class_name Light

## Base class for every light in the level. Handles the shared stuff
## (active state, toggling, group membership, pull strength) and exposes
## hooks that subtypes override for their own quirks.

@export var can_toggle := true
@export var pull_strength := 1.0   # multiplier on the moth's attraction pull
@export var start_active := true

var is_active: bool

func _ready() -> void:
	is_active = start_active
	add_to_group("lights")
	# Let the moth detect overlap-based "reached" events itself,
	# but subtypes can also just call _on_moth_entered manually
	# if they connect body_entered.
	body_entered.connect(_on_body_entered)

func toggle() -> void:
	if not can_toggle:
		return
	is_active = !is_active
	_on_toggled()
	if is_active:
		get_tree().call_group("birds", "alert_to_position", global_position)

func _on_toggled() -> void:
	pass  # override: swap sprite frame, play sound, etc.

func _on_body_entered(body: Node) -> void:
	if not is_active:
		return
	if body.is_in_group("moth"):
		on_moth_reached(body)

func on_moth_reached(_moth: Node) -> void:
	pass  # override: kill, start safe-timer, save checkpoint, etc.

## Called by the moth's pull scan. Lights that shouldn't pull
## right now (e.g. toggled off, or a checkpoint already hit) can
## override this instead of just checking is_active everywhere.
func is_attracting() -> bool:
	return is_active
