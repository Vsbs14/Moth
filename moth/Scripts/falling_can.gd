extends Node2D
class_name FallingCan
## Environmental hazard: sits at a fixed spawn point (placed by your level
## designer as a Marker2D-equivalent -- just position this node where you
## want the can to start). Drops when the moth passes below it and is
## roughly under it on the x-axis. Instant death on contact, like a zapper.
##
## SETUP: instance this scene, position it at the ledge/shelf where the can
## sits, assign `can_texture` (or leave the child Sprite2D's texture set in
## the editor), and optionally tweak `trigger_width` for how forgiving the
## x-overlap trigger is.

@export var can_texture: Texture2D
@export var trigger_width := 40.0     # how far left/right of the can the moth can be and still trigger it
@export var fall_speed := 700.0
@export var fall_acceleration := 1400.0
@export var warning_time := 0.35      # brief telegraph before it actually drops -- gives the player a chance to react
@export var respawn_delay := 3.0      # seconds after falling before it resets to try again; set 0 to never reset
@export var death_particles: PackedScene

enum State { IDLE, WARNING, FALLING, DONE }

var _state := State.IDLE
var _spawn_position: Vector2
var _velocity := 0.0
var _moth: Node2D

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _hitbox: Area2D = $Hitbox
@onready var _rattle_sound: AudioStreamPlayer2D = get_node_or_null("rattleSound")
@onready var _drop_sound: AudioStreamPlayer2D = get_node_or_null("dropSound")

func _ready() -> void:
	_spawn_position = global_position
	if can_texture and _sprite:
		_sprite.texture = can_texture
	_hitbox.body_entered.connect(_on_hitbox_body_entered)
	add_to_group("falling_cans")

func _physics_process(delta: float) -> void:
	if not _moth or not is_instance_valid(_moth):
		_moth = get_tree().get_first_node_in_group("moth")
		if not _moth:
			return

	match _state:
		State.IDLE:
			_check_trigger()
		State.WARNING:
			pass  # handled by the timer in _start_warning()
		State.FALLING:
			_velocity += fall_acceleration * delta
			_velocity = minf(_velocity, fall_speed)
			global_position.y += _velocity * delta
		State.DONE:
			pass

func _check_trigger() -> void:
	# Moth must be below the can's spawn height AND roughly underneath it
	# on x -- this is the "passes below it" condition. Using spawn Y (not
	# current Y, which hasn't moved yet in IDLE) so this is stable.
	if _moth.global_position.y <= _spawn_position.y:
		return
	if absf(_moth.global_position.x - _spawn_position.x) > trigger_width:
		return
	_start_warning()

func _start_warning() -> void:
	_state = State.WARNING
	if _rattle_sound:
		_rattle_sound.play()
	# Small shake so the drop reads as reactable, not a cheap-shot instant hazard.
	var tw := create_tween()
	tw.tween_property(_sprite, "position:x", 3.0, 0.05).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_sprite, "position:x", -3.0, 0.1).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_sprite, "position:x", 0.0, 0.05).set_trans(Tween.TRANS_SINE)
	await get_tree().create_timer(warning_time).timeout
	if _state == State.WARNING:   # could have been reset/freed mid-wait
		_start_fall()

func _start_fall() -> void:
	_state = State.FALLING
	_velocity = 0.0
	if _drop_sound:
		_drop_sound.play()

func _on_hitbox_body_entered(body: Node) -> void:
	if _state != State.FALLING:
		return
	if body.is_in_group("moth"):
		_kill_moth(body)
	else:
		# Hit the ground/geometry instead of the moth -- land and despawn/reset.
		_land()

func _kill_moth(moth: Node) -> void:
	if death_particles:
		var fx = death_particles.instantiate()
		get_tree().current_scene.add_child(fx)
		fx.global_position = moth.global_position
	if moth.has_method("die"):
		moth.die()
	_land()

func _land() -> void:
	_state = State.DONE
	visible = false
	set_physics_process(respawn_delay > 0.0)
	if respawn_delay > 0.0:
		await get_tree().create_timer(respawn_delay).timeout
		_reset()

func _reset() -> void:
	global_position = _spawn_position
	_sprite.position = Vector2.ZERO
	_velocity = 0.0
	visible = true
	_state = State.IDLE
