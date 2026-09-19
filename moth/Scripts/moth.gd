extends CharacterBody2D

@export_group("Flight Dynamics")
@export var climb_speed := 340.0
@export var climb_accel := 14.0
@export var glide_speed := 160.0
@export var dive_speed := 460.0
@export var fall_accel := 9.0
@export var steer_speed := 260.0
@export var steer_accel := 12.0

@export_group("Tilt")
@export var climb_pitch_deg := 0.0
@export var glide_pitch_deg := 180.0
@export var dive_pitch_deg := 80.0
@export var bank_deg := 24.0
@export var rotation_smoothness := 4.5

@export_group("Stamina")
@export var max_stamina := 100.0
@export var stamina_drain := 35.0
@export var stamina_regen := 25.0

@export_group("Light Pull")
@export var pull_detect_radius := 400.0   # how far the moth "senses" lights
@export var pull_accel := 2600.0          # extra acceleration toward an attracting light (px/sec^2). Compare to climb/steer accel (~1200-1400 effective) -- needs to be clearly stronger to feel like a real fight
@export var pull_altitude_scale := 0.002  # pull gets stronger the higher you climb

@export_group("Resist")
@export var resist_mash_decay := 0.6      # how fast resist charge drains per second while NOT mashing
@export var resist_mash_gain := 0.22      # charge added per mash press
@export var resist_charge_to_escape := 1.0 # charge at which pull is fully cancelled (0..1)

var stamina := max_stamina
var is_exhausted := false

var is_resisting := false
var resist_charge := 0.0
var is_being_pulled := false

var current_altitude := 0.0   # set externally or derived from -global_position.y
var is_dead := false

signal pull_started
signal pull_ended

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var detect_area: Area2D = $LightDetectArea  # Area2D w/ CollisionShape2D radius = pull_detect_radius
@onready var single_flap: AudioStreamPlayer2D = get_node_or_null("singleFlap")

func _ready() -> void:
	add_to_group("moth")

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	var steer_input := Input.get_axis("move_left", "move_right")
	var climb_pressed := Input.is_action_pressed("fly_up")
	var dive_pressed := Input.is_action_pressed("ui_down")

	var nearest_light: Light = _get_nearest_attracting_light()
	var was_being_pulled := is_being_pulled
	is_being_pulled = nearest_light != null

	if is_being_pulled and not was_being_pulled:
		resist_charge = 0.0
		pull_started.emit()
		print("[PULL] light detected, pull started -> ", nearest_light.name)
	elif was_being_pulled and not is_being_pulled:
		pull_ended.emit()
		print("[PULL] out of range, pull ended")

	_handle_resist(delta, is_being_pulled)

	# 1. Stamina (Gated Recovery)
	if stamina <= 0.0:
		is_exhausted = true
	elif stamina >= max_stamina * 0.3:
		is_exhausted = false

	var is_climbing := climb_pressed and not is_exhausted
	var is_diving := dive_pressed and not is_climbing
	var is_fluttering := not is_climbing and not is_diving

	if is_climbing:
		stamina = max(0.0, stamina - stamina_drain * delta)
	else:
		stamina = min(max_stamina, stamina + stamina_regen * delta)

	# TEMP: only plays if the singleFlap AudioStreamPlayer2D node exists in this scene
	if single_flap and !Input.is_action_pressed("fly_up"):
		single_flap.play()

	# 2. Vertical Velocity -- normal flight control, always active
	var target_vy: float
	var y_accel: float

	if is_climbing:
		target_vy = -climb_speed
		y_accel = climb_accel
	elif is_diving:
		target_vy = dive_speed
		y_accel = fall_accel * 1.5
	else:
		target_vy = glide_speed
		y_accel = fall_accel

	velocity.y = move_toward(
		velocity.y,
		target_vy,
		y_accel * 100.0 * delta
	)

	# 3. Horizontal Speed -- player always keeps steering control; pull never
	# locks this out. Pull is added afterward as an extra force, so it reads
	# as "fighting a strong current," not losing control of the moth entirely.
	var speed_mod := 1.4 if is_diving else (0.8 if is_climbing else 1.0)
	var target_vx := steer_input * steer_speed * speed_mod

	velocity.x = move_toward(
		velocity.x,
		target_vx,
		steer_accel * 100.0 * delta
	)

	# 3b. Light pull -- continuous extra force toward the light, added on top
	# of whatever velocity normal flight controls just produced. Mashing
	# Resist scales down how much of this force gets through; it never
	# hijacks velocity outright, so the player can always still steer/climb/
	# dive even mid-pull -- no softlock, just a harder fight.
	if is_being_pulled:
		_apply_light_pull(nearest_light, delta)

	# 4. Direction
	if is_being_pulled and resist_charge < resist_charge_to_escape:
		var to_light_x: float = nearest_light.global_position.x - global_position.x
		# Facing toward the light while being dragged in; flips to face away
		# while actively mashing, as if straining against the pull. Reverts
		# back to facing the light the instant mashing stops (if not escaped).
		# Once fully escaped (charge maxed), this block is skipped entirely
		# so the sprite straightens out and normal steering takes over facing.
		if is_resisting:
			sprite.flip_h = to_light_x > 0.0   # facing away from the light
		else:
			sprite.flip_h = to_light_x < 0.0   # facing toward the light
	elif steer_input != 0.0:
		sprite.flip_h = steer_input < 0.0

	# 5. Rotation
	var base_pitch := glide_pitch_deg

	if is_climbing:
		base_pitch = climb_pitch_deg
	elif is_diving:
		base_pitch = dive_pitch_deg

	var bank := steer_input * bank_deg

	if is_fluttering:
		bank = -bank

	var target_angle := deg_to_rad(base_pitch + bank)
	var rotation_weight := 1.0 - exp(-rotation_smoothness * delta)

	sprite.rotation = lerp_angle(
		sprite.rotation,
		target_angle,
		rotation_weight
	)

	# 6. Procedural Squash & Stretch
	var target_scale_y := 1.0
	var target_scale_x := 1.0

	if is_climbing:
		target_scale_y = 1.15
		target_scale_x = 0.88
	elif is_diving:
		target_scale_y = 1.25
		target_scale_x = 0.80

	sprite.scale.x = move_toward(sprite.scale.x, target_scale_x, 3.0 * delta)
	sprite.scale.y = move_toward(sprite.scale.y, target_scale_y, 3.0 * delta)

	# 7. Animations
	if climb_pressed and not is_exhausted:
		sprite.play("climb")
	else:
		sprite.play("flutter")

	move_and_slide()


func _handle_resist(delta: float, being_pulled: bool) -> void:
	if not being_pulled:
		resist_charge = 0.0
		is_resisting = false
		return

	if Input.is_action_just_pressed("resist"):
		resist_charge = min(1.0, resist_charge + resist_mash_gain)
		print("[RESIST] mash! charge = ", snapped(resist_charge, 0.01))

	resist_charge = max(0.0, resist_charge - resist_mash_decay * delta)
	is_resisting = resist_charge > 0.0

	if is_resisting and resist_charge >= resist_charge_to_escape:
		print("[RESIST] full charge reached, pull cancelled")


func _apply_light_pull(nearest: Light, delta: float) -> void:
	var to_light: Vector2 = nearest.global_position - global_position
	var dist: float = to_light.length()
	if dist < 1.0:
		dist = 1.0

	var altitude_bonus: float = 1.0 + current_altitude * pull_altitude_scale
	var accel: float = pull_accel * nearest.pull_strength * altitude_bonus

	# resist_charge scales how much of the pull force actually gets through.
	# At charge 0: full pull. At resist_charge_to_escape: pull is fully
	# cancelled (0 extra force) -- the player just flies normally again,
	# rather than being yanked backward or frozen. This is additive to
	# whatever velocity normal flight controls already set this frame, so
	# steering/climbing/diving always still work, even mid-pull.
	var t: float = clamp(resist_charge / max(resist_charge_to_escape, 0.001), 0.0, 1.0)
	accel *= (1.0 - t)

	velocity += to_light.normalized() * accel * delta

	if Engine.get_physics_frames() % 30 == 0:  # throttled so it doesn't spam every physics tick
		print("[PULL] ", nearest.name, " | dist=", snapped(dist, 1.0), " accel=", snapped(accel, 1.0), " charge=", snapped(resist_charge, 0.01))


func _get_nearest_attracting_light() -> Light:
	var best: Light = null
	var best_dist := INF

	for body in detect_area.get_overlapping_areas():
		if body is Light and body.is_attracting():
			var d := global_position.distance_to(body.global_position)
			if d < best_dist:
				best_dist = d
				best = body

	return best


func interact() -> void:
	for area in detect_area.get_overlapping_areas():
		if area is Light:
			var d := global_position.distance_to(area.global_position)
			if d <= pull_detect_radius * 0.25:  # tighter range than sensing/pull
				area.toggle()
				return  # only tossggle the closest one


func die() -> void:
	if is_dead:
		return
	is_dead = true
	velocity = Vector2.ZERO
	sprite.play("death") if sprite.sprite_frames.has_animation("death") else sprite.stop()
	get_tree().quit()  # TEMP: quit immediately on death for testing; swap for a proper respawn/game-over screen later
	# GameState.respawn_at_checkpoint() or similar goes here
