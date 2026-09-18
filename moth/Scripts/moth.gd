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
@export var climb_pitch_deg := -25.0       # Slight upward pitch when flapping
@export var glide_pitch_deg := 15.0        # Gentle downward tilt while drifting
@export var dive_pitch_deg := 80.0         # Sharp, dramatic nose-down dive
@export var bank_deg := 18.0               # Extra tilt when leaning into a turn
@export var rot_smooth := 14.0

@export_group("Stamina")
@export var max_stamina := 100.0
@export var stamina_drain := 35.0
@export var stamina_regen := 25.0

var stamina := max_stamina
var is_exhausted := false

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

func _physics_process(delta: float) -> void:
	var steer_input := Input.get_axis("move_left", "move_right")
	var climb_pressed := Input.is_action_pressed("fly_up")
	var dive_pressed := Input.is_action_pressed("ui_down")

	# 1. Stamina (Gated Recovery)
	if stamina <= 0.0:
		is_exhausted = true
	elif stamina >= max_stamina * 0.3:
		is_exhausted = false

	var is_climbing := climb_pressed and not is_exhausted
	var is_diving := dive_pressed and not is_climbing

	if is_climbing:
		stamina = max(0.0, stamina - stamina_drain * delta)
	else:
		stamina = min(max_stamina, stamina + stamina_regen * delta)

	# 2. Vertical Velocity
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

	velocity.y = move_toward(velocity.y, target_vy, y_accel * 100.0 * delta)

	# 3. Horizontal Speed (Faster during dives, tighter while climbing)
	var speed_mod := 1.4 if is_diving else (0.8 if is_climbing else 1.0)
	var target_vx := steer_input * steer_speed * speed_mod
	velocity.x = move_toward(velocity.x, target_vx, steer_accel * 100.0 * delta)

	# 4. Direction & Pitch
	if steer_input != 0:
		# Flip only when actively steering and maintain last facing direction
		sprite.flip_h = steer_input < 0

	# Base pitch decided purely by intent state
	var base_pitch := glide_pitch_deg
	if is_climbing:
		base_pitch = climb_pitch_deg
	elif is_diving:
		base_pitch = dive_pitch_deg

	# Add bank roll: leaning forward/downward in the direction of flight
	var bank := steer_input * bank_deg if not sprite.flip_h else -steer_input * bank_deg
	var target_angle := deg_to_rad(base_pitch + bank)

	# Symmetrical pitch adjustment when facing left
	if sprite.flip_h:
		target_angle = -target_angle

	sprite.rotation = lerp_angle(sprite.rotation, target_angle, rot_smooth * delta)

	# 5. Procedural Squash & Stretch
	var target_scale_y := 1.0
	var target_scale_x := 1.0
	if is_climbing:
		target_scale_y = 1.15  # Stretch vertically during flap
		target_scale_x = 0.88
	elif is_diving:
		target_scale_y = 1.25  # Streamline stretch during steep dive
		target_scale_x = 0.80

	sprite.scale.x = move_toward(sprite.scale.x, target_scale_x, 3.0 * delta)
	sprite.scale.y = move_toward(sprite.scale.y, target_scale_y, 3.0 * delta)

	# 6. Animations
	if is_climbing:
		sprite.play("climb")
	else:
		sprite.play("flutter")

	move_and_slide()
