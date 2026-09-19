extends Light
class_name FlickeringLight

## Cycles on/off on its own timing. Ignores Interact — the player has
## to learn the pattern and time their pass instead of toggling it.

@export var on_duration := 1.5
@export var off_duration := 1.0
@export var randomize_start := true

var _timer: Timer

func _ready() -> void:
	can_toggle = false
	super._ready()
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_on_cycle_timeout)
	add_child(_timer)

	if randomize_start:
		is_active = randf() < 0.5
		_apply_glow_state()   # sync glow to the randomized start state
	_start_next_phase()

func _start_next_phase() -> void:
	_timer.wait_time = on_duration if is_active else off_duration
	_timer.start()

func _on_cycle_timeout() -> void:
	is_active = !is_active
	_on_toggled()
	_apply_glow_state()
	# Own toggle() is a no-op for this subtype, so the signal has to be
	# emitted directly here -- birds still need to hear about flicker
	# transitions exactly like any other light's toggle.
	light_toggled.emit(self, is_active)
	if is_active:
		get_tree().call_group("birds", "alert_to_position", global_position)
	_start_next_phase()

func toggle() -> void:
	pass  # flickering lights can't be manually toggled
