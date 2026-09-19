extends Area2D
class_name Light

## Base class for every light in the level. Handles the shared stuff
## (active state, toggling, group membership, pull strength) and exposes
## hooks that subtypes override for their own quirks.
##
## GLOW: every Light now owns a PointLight2D child (built in code, so no
## per-scene setup needed) that turns on/off in lockstep with is_active.
## Subtypes just set glow_color / glow_energy / glow_texture_scale to taste
## in the Inspector -- no extra wiring required. If a light scene already
## has its own PointLight2D child named "Glow", that one is used instead
## of building a new one (lets a designer hand-place/tune one in-editor).

@export var can_toggle := true
@export var pull_strength := 1.0   # multiplier on the moth's attraction pull
@export var start_active := true

@export_group("Glow")
@export var glow_enabled := true
@export var glow_color := Color(1.0, 0.85, 0.5)
@export var glow_energy := 0.4
@export var glow_texture_scale := 0.5  # scales Godot's default soft-circle gradient texture
@export var glow_off_energy := 0.0       # energy while inactive (0 = fully dark)

var is_active: bool

## Emitted whenever toggle() flips this light, whether from player
## interact, a Switch, or a subtype's own timer (FlickeringLight).
## Birds use this to know when to head toward / leave a light.
signal light_toggled(light: Light, active: bool)

var _glow: PointLight2D

func _ready() -> void:
	is_active = start_active
	add_to_group("lights")
	body_entered.connect(_on_body_entered)
	if glow_enabled:
		_setup_glow()
		_apply_glow_state()

func _setup_glow() -> void:
	_glow = get_node_or_null("Glow") as PointLight2D
	if _glow:
		return  # designer already placed/tuned one in this scene
	_glow = PointLight2D.new()
	_glow.name = "Glow"
	_glow.texture = _default_glow_texture()
	_glow.color = glow_color
	_glow.texture_scale = glow_texture_scale
	_glow.energy = glow_energy
	add_child(_glow)

## Godot ships no built-in radial gradient texture, so this generates one
## once and caches it -- avoids requiring every light scene to have its own
## glow texture asset just to get a soft circular falloff.
static var _cached_glow_texture: GradientTexture2D

static func _default_glow_texture() -> GradientTexture2D:
	if _cached_glow_texture:
		return _cached_glow_texture
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 256
	tex.height = 256
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	_cached_glow_texture = tex
	return tex

func _apply_glow_state() -> void:
	if not _glow:
		return
	_glow.color = glow_color
	_glow.texture_scale = glow_texture_scale
	_glow.energy = glow_energy if is_active else glow_off_energy
	_glow.visible = is_active or glow_off_energy > 0.0

func toggle() -> void:
	if not can_toggle:
		return
	is_active = !is_active
	_on_toggled()
	_apply_glow_state()
	light_toggled.emit(self, is_active)
	if is_active:
		get_tree().call_group("birds", "alert_to_position", global_position)

## Shared entry point moth.gd's interact() calls on whatever it finds in
## range, whether it's a Light or a Switch -- lets the moth script stay
## agnostic about which type it hit. Lights still toggle themselves directly
## here; a level designer who wants a light ONLY switch-controlled should
## just set can_toggle to false on it and wire it into a Switch instead.
func interact_with(_moth: Node) -> void:
	toggle()

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
