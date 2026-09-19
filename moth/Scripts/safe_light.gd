extends Light
class_name SafeLight

## Fine to rest on for a few seconds. Linger past linger_time and a
## patrolling bird gets alerted to your position.

@export var linger_time := 3.0
@export var bird_alert_signal_name := "moth_lingering"

var _timer: Timer
var _moth_inside := false

func _ready() -> void:
	super._ready()
	_timer = Timer.new()
	_timer.wait_time = linger_time
	_timer.one_shot = true
	_timer.timeout.connect(_on_linger_timeout)
	add_child(_timer)
	body_exited.connect(_on_body_exited)

func on_moth_reached(_moth: Node) -> void:
	_moth_inside = true
	_timer.start()

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("moth"):
		_moth_inside = false
		_timer.stop()

func _on_linger_timeout() -> void:
	if _moth_inside:
		get_tree().call_group("birds", "alert_to_position", global_position)
