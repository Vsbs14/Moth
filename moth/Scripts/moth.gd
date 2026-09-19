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
@export var pull_ramp_time := 5.0         # seconds of continuous exposure to reach full pull strength (longer = more reaction time before it gets hard)
@export var pull_accel_max := 2000.0      # extra acceleration toward an attracting light at FULL ramp (px/sec^2), added on top of the idle drift-toward-light behavior
@export var pull_altitude_scale := 0.002  # pull gets stronger the higher you climb
@export var pull_orbit_radius := 40.0     # inside this distance, pull force fades toward zero so the moth hovers/orbits instead of slamming into the light's exact center

@export_group("Resist")
@export var resist_mash_decay := 0.35     # how fast resist charge drains per second while NOT mashing (lower = more forgiving, easier to hold ground between presses)
@export var resist_mash_gain := 0.3       # charge added per mash press
@export var resist_charge_to_escape := 1.0 # charge at which pull is fully cancelled (0..1)

var stamina := max_stamina
var is_exhausted := false

var is_resisting := false
var resist_charge := 0.0
var is_being_pulled := false
var pull_exposure_time := 0.0   # seconds spent continuously inside a light's pull range; resets to 0 the moment you leave range

var current_altitude := 0.0   # px above the spawn point, updated every frame while alive
var start_y := 0.0            # spawn height; altitude is measured from here
var is_dead := false

var respawn_position: Vector2   # last checkpoint reached; where the moth respawns on death. Defaults to spawn position until a checkpoint is hit.

signal pull_started
signal pull_ended

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var detect_area: Area2D = $LightDetectArea  # Area2D w/ CollisionShape2D radius = pull_detect_radius
@onready var single_flap: AudioStreamPlayer2D = get_node_or_null("single_flap")
@onready var death_sound: AudioStreamPlayer2D = $deathSound

# Built entirely in code -- no scene node, no addon dependency. A plain
# Label showing "E" that toggles visible based on interact range.
var interact_prompt: Label

func _ready() -> void:
	add_to_group("moth")
	respawn_position = global_position
	start_y = global_position.y
	_sync_pull_detect_radius()
	_build_interact_prompt()
	# Deferred so it runs after every other node in the scene has finished
	# its own _ready() -- otherwise, if Moth appears earlier in the scene
	# tree than the CheckpointLights, they won't have added themselves to
	# the "lights" group yet and this would silently connect to nothing.
	call_deferred("_connect_existing_checkpoints")

func _sync_pull_detect_radius() -> void:
	# pull_detect_radius is the single source of truth: whatever you set it
	# to in the Inspector (per scene instance) is pushed into the actual
	# CircleShape2D on LightDetectArea here, so the real detection collider
	# always matches without needing to edit the shape resource by hand.
	var shape_node := detect_area.get_node_or_null("CircleShape2D")
	if shape_node and shape_node.shape is CircleShape2D:
		# Godot shares CircleShape2D resources by reference across instances
		# unless "Local to Scene" is enabled on the resource -- duplicate it
		# here so setting the radius on one Moth instance never bleeds into
		# other instances/scenes using what looks like "the same" shape.
		var shape: CircleShape2D = shape_node.shape.duplicate()
		shape.radius = pull_detect_radius
		shape_node.shape = shape
	else:
		push_warning("Moth: couldn't find a CircleShape2D under LightDetectArea to sync pull_detect_radius to -- detection radius may not match the exported value (%s)." % pull_detect_radius)

func _build_interact_prompt() -> void:
	# Plain code-built Label, no addon/scene node required. Sits above the
	# moth sprite and is shown/hidden each physics tick based on range.
	interact_prompt = Label.new()
	interact_prompt.text = "E"
	interact_prompt.add_theme_font_size_override("font_size", 28)
	interact_prompt.add_theme_color_override("font_color", Color.WHITE)
	interact_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	interact_prompt.add_theme_constant_override("outline_size", 6)
	interact_prompt.z_index = 100
	interact_prompt.position = Vector2(-8, -70)   # roughly centered above the moth
	interact_prompt.visible = false
	add_child(interact_prompt)

func _connect_existing_checkpoints() -> void:
	# Hook up every CheckpointLight already placed in the scene tree at
	# startup. If checkpoints are spawned dynamically later, call
	# connect_checkpoint() on them individually instead.
	var found := 0
	for node in get_tree().get_nodes_in_group("lights"):
		if node is CheckpointLight:
			connect_checkpoint(node)
			found += 1
	print("[CHECKPOINT] connected to ", found, " checkpoint(s) in scene")

func connect_checkpoint(checkpoint: CheckpointLight) -> void:
	if not checkpoint.checkpoint_reached.is_connected(_on_checkpoint_reached):
		checkpoint.checkpoint_reached.connect(_on_checkpoint_reached)

func _on_checkpoint_reached(pos: Vector2) -> void:
	# Only move the anchor upward (smaller y = higher)
	if pos.y < respawn_position.y:
		respawn_position = pos
		print("[CHECKPOINT] respawn point set -> ", pos)

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# Altitude above spawn, drives pull strength scaling
	current_altitude = maxf(0.0, start_y - global_position.y)

	var steer_input := Input.get_axis("move_left", "move_right")
	if Input.is_action_just_pressed("interact"):
		interact()
	if interact_prompt:
		# Re-scans every physics tick -- same cost as the pull-detection scan
		# already running each frame, so this doesn't add a meaningful hit.
		interact_prompt.visible = _find_nearest_interactable() != null
	var climb_pressed := Input.is_action_pressed("fly_up")
	var dive_pressed := Input.is_action_pressed("ui_down")

	var nearest_light: Light = _get_nearest_attracting_light()
	var was_being_pulled := is_being_pulled
	is_being_pulled = nearest_light != null

	if is_being_pulled and not was_being_pulled:
		resist_charge = 0.0
		pull_exposure_time = 0.0
		pull_started.emit()
		print("[PULL] light detected, pull started -> ", nearest_light.name)
	elif was_being_pulled and not is_being_pulled:
		pull_exposure_time = 0.0
		pull_ended.emit()
		print("[PULL] out of range, pull ended, ramp reset")

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

	# Flap SFX loops while climbing, stops otherwise.
	# (Loop must be ticked in the mp3's Import tab for a continuous sound.)
	if single_flap:
		if is_climbing and not single_flap.playing:
			single_flap.play()
		elif not is_climbing and single_flap.playing:
			single_flap.stop()

	# 2. Vertical Velocity -- normal flight control, always active. While being
	# pulled and the player isn't actively climbing/diving, the moth drifts
	# toward the light vertically too -- doing nothing is never a free escape.
	var target_vy: float
	var y_accel: float

	if is_climbing:
		target_vy = -climb_speed
		y_accel = climb_accel
	elif is_diving:
		target_vy = dive_speed
		y_accel = fall_accel * 1.5
	elif is_being_pulled:
		var to_light_y_idle: float = nearest_light.global_position.y - global_position.y
		var idle_ramp: float = clamp(pull_exposure_time / max(pull_ramp_time, 0.001), 0.0, 1.0)
		# Same orbit falloff as _apply_light_pull -- without it the idle
		# drift also just slams toward the light's exact y and overshoots/
		# corrects in a tight jitter once close, instead of settling into a
		# hover. Falls back to 1.0 (full drift) if not currently pulling on
		# this axis at all, matched to the same 40px dead zone.
		var y_falloff: float = clamp((absf(to_light_y_idle) - pull_orbit_radius) / pull_orbit_radius, 0.0, 1.0)
		target_vy = lerp(glide_speed, signf(to_light_y_idle) * glide_speed * y_falloff, idle_ramp)
		y_accel = fall_accel
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

	# While being pulled, doing NOTHING is not a safe option: the moth's own
	# instinct steers it toward the light unless the player actively steers
	# against it. This is what "resisting" is protecting you from -- letting
	# go of the stick and gliding/diving away should NOT be a free escape.
	if is_being_pulled and steer_input == 0.0:
		var to_light_x_idle: float = nearest_light.global_position.x - global_position.x
		var idle_ramp: float = clamp(pull_exposure_time / max(pull_ramp_time, 0.001), 0.0, 1.0)
		var x_falloff: float = clamp((absf(to_light_x_idle) - pull_orbit_radius) / pull_orbit_radius, 0.0, 1.0)
		target_vx = lerp(0.0, signf(to_light_x_idle) * steer_speed * speed_mod * x_falloff, idle_ramp)

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
	pull_exposure_time += delta

	var to_light: Vector2 = nearest.global_position - global_position
	var dist: float = to_light.length()
	if dist < 1.0:
		dist = 1.0

	# Ramp: pull starts weak the instant you enter range and grows toward
	# full strength over pull_ramp_time seconds of CONTINUOUS exposure.
	# Flying back out of range resets this to zero -- re-entering starts the
	# ramp fresh, so ducking in and out of a light's range is a valid way to
	# approach it cautiously rather than committing to a full fight.
	var ramp_t: float = clamp(pull_exposure_time / max(pull_ramp_time, 0.001), 0.0, 1.0)

	var altitude_bonus: float = 1.0 + current_altitude * pull_altitude_scale
	var accel: float = pull_accel_max * ramp_t * nearest.pull_strength * altitude_bonus

	# Distance falloff + dead zone -- without this, accel stays at full
	# strength no matter how close the moth gets, so it just slams straight
	# into the light's center (and visually reads as "stuck" oscillating
	# behind the sprite) instead of hovering/orbiting near it like a real
	# moth in a trance. orbit_radius is roughly "how close is close enough";
	# inside it, pull falls off toward zero instead of staying maxed out.
	var falloff: float = clamp((dist - pull_orbit_radius) / pull_orbit_radius, 0.0, 1.0)
	accel *= falloff

	# resist_charge scales how much of the (already-ramped) pull force gets
	# through. At charge 0: full ramped pull. At resist_charge_to_escape:
	# pull is fully cancelled for this frame -- the player just flies
	# normally, free to steer straight out of the detection radius, which is
	# the actual way out (crossing pull_detect_radius, not the charge itself).
	var t: float = clamp(resist_charge / max(resist_charge_to_escape, 0.001), 0.0, 1.0)
	accel *= (1.0 - t)

	velocity += to_light.normalized() * accel * delta

	if Engine.get_physics_frames() % 30 == 0:  # throttled so it doesn't spam every physics tick
		print("[PULL] ", nearest.name, " | dist=", snapped(dist, 1.0), " ramp=", snapped(ramp_t, 0.01), " accel=", snapped(accel, 1.0), " charge=", snapped(resist_charge, 0.01))


func _get_nearest_attracting_light() -> Light:
	var best: Light = null
	var best_dist := INF

	for body in detect_area.get_overlapping_areas():
		# pull_strength > 0 skips silent lights (checkpoints) so they can't
		# steal the "nearest light" slot from a real hazard.
		if body is Light and body.is_attracting() and body.pull_strength > 0.0:
			var d := global_position.distance_to(body.global_position)
			if d < best_dist:
				best_dist = d
				best = body

	return best


## Shared by interact() and the prompt-visibility check in _physics_process
## so "can I press E right now" and "what does E actually do" can never
## disagree with each other. Switches only -- lights are toggled via their
## switch, not directly, so the prompt/action never appears for a light,
## zapper, checkpoint, etc. even when they're technically can_toggle=true.
func _find_nearest_interactable() -> Switch:
	var best: Switch = null
	var best_dist := INF
	for area in detect_area.get_overlapping_areas():
		if area is Switch:
			var d := global_position.distance_to(area.global_position)
			if d <= pull_detect_radius * 0.6 and d < best_dist:
				best_dist = d
				best = area
	return best

func interact() -> void:
	var best := _find_nearest_interactable()
	if best:
		best.interact_with(self)


func die() -> void:
	if is_dead:
		return
	is_dead = true
	velocity = Vector2.ZERO
	if single_flap:
		single_flap.stop()
	death_sound.play()
	sprite.play("death") if sprite.sprite_frames.has_animation("death") else sprite.stop()
	print("[DEATH] respawning at ", respawn_position)
	await get_tree().create_timer(0.6).timeout   # brief pause so the death pose/anim actually reads before snapping back
	_respawn()

func _respawn() -> void:
	global_position = respawn_position
	velocity = Vector2.ZERO
	resist_charge = 0.0
	is_being_pulled = false
	pull_exposure_time = 0.0
	is_dead = false
	sprite.play("flutter")
