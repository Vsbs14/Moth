extends Light
class_name PermanentLight

## Always on, can't be switched off. A fixed hazard the player has to
## route around. No death on contact by default — pair with a
## death_zone Area2D child if you want it to also be lethal, or just
## make this a ZapperLight with can_toggle forced off (see ZapperLight).

func _ready() -> void:
	can_toggle = false
	start_active = true
	super._ready()
