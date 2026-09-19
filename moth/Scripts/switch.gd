extends Area2D
class_name Switch

## A breaker box / switch the player can Interact [E] with. Doesn't attract
## or kill on its own -- it just forwards toggle() to whatever Lights are
## wired into it via the Inspector. Drop any number of Light-derived scene
## instances (plain lights, flickering lights, checkpoints, etc.) into
## controlled_lights and this will flip all of them together on each press.
##
## Zappers are intentionally still toggleable via this array if you ever
## want to wire one in later (ZapperLight just no-ops since can_toggle is
## forced false in its own script) -- nothing here assumes otherwise.

@export var controlled_lights: Array[Light] = []

## Optional: swap sprite frame / play a sound when flipped. Purely cosmetic --
## doesn't affect which lights end up on/off (each Light tracks its own state).
signal switched(is_on: bool)

var _is_on := false

func _ready() -> void:
	add_to_group("switches")

## Called by moth.gd's interact() when the moth is in range of this switch.
## Named differently from Light.toggle() so a single interact() call site in
## moth.gd can just check "is this a Light or a Switch" and call the right
## one -- see the interact_with() hook on Light for the shared entry point.
func interact_with(_moth: Node) -> void:
	_is_on = !_is_on
	for light in controlled_lights:
		if light == null:
			continue  # empty inspector slot, skip it
		if light.is_active != _is_on:
			light.toggle()
	switched.emit(_is_on)
	_on_switched()

func _on_switched() -> void:
	pass  # override or connect to `switched` signal: sprite swap, sfx, etc.
