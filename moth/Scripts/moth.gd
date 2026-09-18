extends CharacterBody2D

@export var climb_speed := 300.0
@export var glide_fall_speed := 150.0
@export var steer_speed := 200.0
@export var steer_penalty := 0.7  # slower while steering
@export var max_stamina := 100.0
@export var stamina_drain := 30.0
@export var stamina_regen := 20.0

var stamina := max_stamina

func _physics_process(delta: float) -> void:
	var steering := Input.get_axis("move_left", "move_right")
	var climbing := Input.is_action_pressed("fly_up") and stamina > 0.0

	if climbing:
		velocity.y = -climb_speed
		stamina -= stamina_drain * delta
	else:
		velocity.y = glide_fall_speed
		stamina = min(stamina + stamina_regen * delta, max_stamina)

	var horizontal_speed := steer_speed
	if steering != 0:
		horizontal_speed *= steer_penalty
	velocity.x = steering * horizontal_speed
	
	if climbing:
		$AnimatedSprite2D.play("climb")
	else:
		$AnimatedSprite2D.play("glide")

	move_and_slide()
