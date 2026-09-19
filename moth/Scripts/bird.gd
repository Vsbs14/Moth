@tool
extends Node2D
class_name Bird

## Patrols between its spawn point and spawn + patrol_offset, showing a vision cone.
## Moth in cone -> windup (cone reddens and tracks the moth) -> if still inside:
## one-key QTE -> dodge = bird whiffs, fail = moth dies.

enum State { PATROL, INVESTIGATE, WINDUP, QTE, STRIKE, COOLDOWN }

const MOTH_LAYER_MASK := 1
const ARRIVE_DISTANCE := 4.0
const LOSE_TARGET_PAUSE := 0.6
const LUNGE_IN_TIME := 0.18
const LUNGE_BACK_TIME := 0.4
const DODGE_WHIFF_FRACTION := 0.7

@export_group("Patrol")
@export var patrol_offset := Vector2(400, 0):
	set(v):
		patrol_offset = v
		queue_redraw()
@export var patrol_speed := 90.0
@export var turn_pause := 0.6
@export var art_faces_left := false

@export_group("Vision")
@export_range(10, 180) var cone_angle_deg := 50
@export var cone_length := 380.0
@export var ray_count := 24
## Where the cone starts relative to the bird when facing RIGHT (mirrored when facing left).
@export var cone_origin := Vector2(15, 8)
## Physics layers that block sight. Keep the moth's layer OUT of this. 0 = sees through everything.
@export_flags_2d_physics var vision_block_mask := 0
## Birds farther than this from the moth go to sleep (saves web performance).
@export var active_range := 1600.0

@export_group("Catch")
@export var windup_time := 0.9
## How fast the cone swings toward the moth during windup, in degrees per second.
@export var track_speed := 70.0
@export var qte_window := 0.7
@export var qte_key: Key = KEY_Q
@export var cooldown_time := 2.5

@export_group("Alert")
@export var alert_hear_radius := 1200.0
@export var investigate_speed := 180.0
@export var investigate_stop_distance := 60.0
@export var investigate_linger := 1.5

@export_group("Cone Look")
@export var color_calm := Color(1.0, 0.85, 0.25)
@export var color_alert := Color(1.0, 0.15, 0.1)
@export var color_cooldown := Color(0.6, 0.6, 0.65)
## Alpha at the apex (beak) and at the far end of the cone.
@export_range(0.0, 1.0) var alpha_near := 0.55
@export_range(0.0, 1.0) var alpha_far := 0.03
@export_range(0.0, 1.0) var outline_alpha := 0.55
@export var outline_width := 2.0
@export var shimmer_amount := 0.12

static var _qte_owner: Bird = null   # only one QTE at a time across all birds

var _state := State.PATROL
var _patrol_a: Vector2
var _patrol_b: Vector2
var _target: Vector2
var _investigate_pos: Vector2
var _timer := 0.0
var _pause_left := 0.0
var _awake := true
var _facing := Vector2.RIGHT
var _tint := Color.WHITE       # current cone color (rgb), alpha handled separately
var _intensity := 1.0          # overall cone strength (dimmed in cooldown)
var _pulse_speed := 3.0
var _moth: Node2D
var _prompt: Label

var _cone: VisionCone2D
var _cone_poly: Polygon2D
var _cone_outline: Line2D
var _cone_area: Area2D
@onready var _sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")


# ---------- setup ----------

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	add_to_group("birds")
	_patrol_a = global_position
	_patrol_b = global_position + patrol_offset
	_target = _patrol_b
	_tint = color_calm
	_build_cone()
	if _sprite:
		_sprite.play("flying")
	_face(_target - global_position)


func _draw() -> void:
	# Patrol preview in the editor
	if Engine.is_editor_hint():
		draw_line(Vector2.ZERO, patrol_offset, Color.YELLOW, 2.0)
		draw_circle(patrol_offset, 8.0, Color.YELLOW)


func _exit_tree() -> void:
	if not Engine.is_editor_hint():
		_release_qte()


func _build_cone() -> void:
	_cone_area = Area2D.new()
	_cone_area.collision_layer = 0
	_cone_area.collision_mask = MOTH_LAYER_MASK
	_cone_area.monitorable = false
	var col := CollisionPolygon2D.new()
	_cone_area.add_child(col)

	_cone_poly = Polygon2D.new()
	_cone_outline = Line2D.new()
	_cone_outline.width = outline_width
	_cone_outline.joint_mode = Line2D.LINE_JOINT_ROUND

	# Set everything BEFORE add_child: the plugin reads these in its own _ready
	_cone = VisionCone2D.new()
	_cone.angle_deg = cone_angle_deg
	_cone.ray_count = ray_count
	_cone.max_distance = cone_length
	_cone.collision_layer_mask = vision_block_mask
	_cone.minimum_recalculate_time_msec = 50
	_cone.min_distance_sqr = 64.0
	_cone.write_collision_polygon = col
	_cone.write_polygon2d = _cone_poly
	_cone.add_child(_cone_poly)
	_cone.add_child(_cone_outline)
	_cone.add_child(_cone_area)
	add_child(_cone)


# ---------- main loop ----------

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not _find_moth():
		return

	# Moth died mid-catch (zapper etc.): abandon the catch
	if _moth.get("is_dead") and (_state == State.WINDUP or _state == State.QTE):
		_release_qte()
		_enter_cooldown()

	if not _update_sleep():
		return

	match _state:
		State.PATROL:
			_patrol_step(delta)
			_check_for_moth()
		State.INVESTIGATE:
			_investigate_step(delta)
		State.WINDUP:
			_windup_step(delta)
		State.QTE:
			_qte_step(delta)
		State.COOLDOWN:
			_cooldown_step(delta)
		State.STRIKE:
			pass   # the tween drives movement

	_update_cone_visuals()


func _find_moth() -> bool:
	if _moth == null or not is_instance_valid(_moth):
		_moth = get_tree().get_first_node_in_group("moth") as Node2D
	return _moth != null


## Sleeps the bird when far from the moth. Returns false while asleep.
func _update_sleep() -> bool:
	var awake := global_position.distance_to(_moth.global_position) <= active_range
	if awake != _awake:
		_awake = awake
		_cone.process_mode = Node.PROCESS_MODE_INHERIT if awake else Node.PROCESS_MODE_DISABLED
		_cone.visible = awake
	return _awake


# ---------- state handlers ----------

func _investigate_step(delta: float) -> void:
	_move_toward(_investigate_pos, investigate_speed, delta)
	if global_position.distance_to(_investigate_pos) <= investigate_stop_distance:
		_state = State.PATROL
		_pause_left = investigate_linger
	_check_for_moth()


func _windup_step(delta: float) -> void:
	if not _moth_in_cone():
		# Player escaped in time
		_state = State.PATROL
		_pause_left = LOSE_TARGET_PAUSE
		_set_calm()
		return

	_timer -= delta
	_track_moth(delta)

	var t := clampf(1.0 - _timer / windup_time, 0.0, 1.0)
	_tint = color_calm.lerp(color_alert, t)
	_pulse_speed = lerpf(3.0, 14.0, t)   # heartbeat gets faster as the catch nears

	if _timer <= 0.0 and _qte_owner == null:
		_start_qte()


func _qte_step(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_resolve_qte(false)


func _cooldown_step(delta: float) -> void:
	_patrol_step(delta)
	_timer -= delta
	if _timer <= 0.0:
		_state = State.PATROL
		_set_calm()


# ---------- movement ----------

func _patrol_step(delta: float) -> void:
	if _pause_left > 0.0:
		_pause_left -= delta
		return
	_move_toward(_target, patrol_speed, delta)
	if global_position.distance_to(_target) < ARRIVE_DISTANCE:
		_target = _patrol_a if _target == _patrol_b else _patrol_b
		_pause_left = turn_pause
		_face(_target - global_position)


func _move_toward(dest: Vector2, speed: float, delta: float) -> void:
	if (dest - global_position).length() > 0.5:
		_face(dest - global_position)
	global_position = global_position.move_toward(dest, speed * delta)


## Points the bird, sprite and cone along dir.
func _face(dir: Vector2) -> void:
	if dir.length() < 0.01:
		return
	_facing = dir.normalized()
	_apply_cone_transform()
	if _sprite and absf(_facing.x) > 0.1:
		_sprite.flip_h = (_facing.x < 0.0) != art_faces_left


## Swings the cone toward the moth at track_speed. The sprite keeps its facing.
func _track_moth(delta: float) -> void:
	var want := (_moth.global_position - global_position).angle()
	var step := deg_to_rad(track_speed) * delta
	var diff := angle_difference(_facing.angle(), want)
	_facing = _facing.rotated(clampf(diff, -step, step))
	_apply_cone_transform()


func _apply_cone_transform() -> void:
	# The plugin's cone points DOWN at rotation 0, hence the -90 degrees
	_cone.rotation = _facing.angle() - PI / 2.0
	var side := -1.0 if _facing.x < 0.0 else 1.0
	_cone.position = Vector2(cone_origin.x * side, cone_origin.y)


# ---------- detection / catching ----------

func _moth_in_cone() -> bool:
	if _moth == null or _moth.get("is_dead"):
		return false
	return _cone_area.get_overlapping_bodies().has(_moth)


func _check_for_moth() -> void:
	if _moth_in_cone():
		_state = State.WINDUP
		_timer = windup_time


func _start_qte() -> void:
	_qte_owner = self
	_state = State.QTE
	_timer = qte_window
	_prompt = Label.new()
	_prompt.text = "[%s]" % OS.get_keycode_string(qte_key)
	_prompt.add_theme_font_size_override("font_size", 28)
	_prompt.add_theme_color_override("font_color", Color.WHITE)
	_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	_prompt.add_theme_constant_override("outline_size", 6)
	_prompt.position = Vector2(-24, -90)
	_prompt.z_index = 100
	_moth.add_child(_prompt)


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or _state != State.QTE:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == qte_key:
		_resolve_qte(true)


func _resolve_qte(dodged: bool) -> void:
	_release_qte()
	_lunge(not dodged)


func _release_qte() -> void:
	if _qte_owner == self:
		_qte_owner = null
	if _prompt and is_instance_valid(_prompt):
		_prompt.queue_free()
	_prompt = null


func _lunge(hit: bool) -> void:
	if _moth == null or not is_instance_valid(_moth):
		_enter_cooldown()
		return
	_state = State.STRIKE
	var start := global_position
	var to_moth := _moth.global_position - start
	_face(to_moth)
	var reach := to_moth if hit else to_moth * DODGE_WHIFF_FRACTION

	var tw := create_tween()
	tw.tween_property(self, "global_position", start + reach, LUNGE_IN_TIME).set_ease(Tween.EASE_IN)
	if hit:
		tw.tween_callback(_kill_moth)
	tw.tween_property(self, "global_position", start, LUNGE_BACK_TIME)
	tw.tween_callback(_enter_cooldown)


func _kill_moth() -> void:
	if _moth and is_instance_valid(_moth) and _moth.has_method("die"):
		_moth.die()


func _enter_cooldown() -> void:
	_state = State.COOLDOWN
	_timer = cooldown_time
	_tint = color_cooldown
	_intensity = 0.35
	_pulse_speed = 3.0


func _set_calm() -> void:
	_tint = color_calm
	_intensity = 1.0
	_pulse_speed = 3.0


# ---------- cone visuals ----------

## Gradient fill (bright at the beak, fading out), soft outline, and a shimmer.
## Called after the plugin has rewritten the polygon so vertex colors always match.
func _update_cone_visuals() -> void:
	var pts := _cone_poly.polygon
	var n := pts.size()
	if n < 3:
		return

	var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.001 * _pulse_speed) * shimmer_amount
	var colors := PackedColorArray()
	colors.resize(n)
	for i in n:
		var d := clampf(pts[i].length() / cone_length, 0.0, 1.0)
		var a := lerpf(alpha_near, alpha_far, d) * pulse * _intensity
		colors[i] = Color(_tint.r, _tint.g, _tint.b, clampf(a, 0.0, 1.0))
	_cone_poly.vertex_colors = colors
	_cone_poly.color = Color.WHITE   # vertex colors carry the tint

	_cone_outline.points = pts
	_cone_outline.closed = true
	_cone_outline.default_color = Color(_tint.r, _tint.g, _tint.b, outline_alpha * pulse * _intensity)


# ---------- called by other scripts ----------

## SafeLight already calls this via the "birds" group. Also used for the lure.
func alert_to_position(pos: Vector2) -> void:
	if _state != State.PATROL and _state != State.INVESTIGATE:
		return
	if global_position.distance_to(pos) > alert_hear_radius:
		return
	_investigate_pos = pos
	_state = State.INVESTIGATE
