extends CanvasLayer
## Minimal code-only dialogue system for the Moth God intro/tutorial lines.
## Add this as an Autoload (Project Settings > Autoload) named "DialogueBox".
## No addon, no scene file needed -- everything is built in _ready().

signal line_finished
signal queue_finished

@export var letters_per_second := 45.0
@export var box_height := 140.0

var _panel: PanelContainer
var _label: RichTextLabel
var _speaker_label: Label
var _prompt: Label

var _queue: Array[Dictionary] = []
var _current_text := ""
var _visible_chars := 0.0
var _is_typing := false
var _active := false

func _ready() -> void:
	layer = 100  # draw above gameplay/HUD
	_build_ui()
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_bottom", 30)
	margin.offset_top = -box_height - 30
	add_child(margin)

	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.88)
	style.border_color = Color(0.8, 0.7, 0.3, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	_panel.add_theme_stylebox_override("panel", style)
	_panel.custom_minimum_size = Vector2(0, box_height)
	margin.add_child(_panel)

	var vbox := VBoxContainer.new()
	_panel.add_child(vbox)

	_speaker_label = Label.new()
	_speaker_label.add_theme_font_size_override("font_size", 18)
	_speaker_label.add_theme_color_override("font_color", Color(0.85, 0.75, 0.35))
	vbox.add_child(_speaker_label)

	_label = RichTextLabel.new()
	_label.bbcode_enabled = false
	_label.fit_content = true
	_label.scroll_active = false
	_label.add_theme_font_size_override("normal_font_size", 20)
	_label.custom_minimum_size = Vector2(0, 70)
	vbox.add_child(_label)

	_prompt = Label.new()
	_prompt.text = "▼ press E"
	_prompt.add_theme_font_size_override("font_size", 14)
	_prompt.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_prompt.visible = false
	vbox.add_child(_prompt)

func _process(delta: float) -> void:
	if not _active:
		return

	if _is_typing:
		_visible_chars += letters_per_second * delta
		var count := int(_visible_chars)
		_label.visible_characters = count
		if count >= _current_text.length():
			_is_typing = false
			_prompt.visible = true

	# Advance: press interact (E) to either fast-forward the current line
	# or move to the next one once it's fully typed.
	if Input.is_action_just_pressed("interact"):
		if _is_typing:
			_visible_chars = _current_text.length()
			_label.visible_characters = -1
			_is_typing = false
			_prompt.visible = true
		else:
			_advance()

## Queue up one or more lines. Each entry: {"speaker": String, "text": String}.
## Call show_lines([...]) to start; connect to queue_finished to know when
## the whole sequence (e.g. the intro cutscene) is done.
func show_lines(lines: Array[Dictionary]) -> void:
	_queue = lines.duplicate()
	_active = true
	visible = true
	get_tree().paused = false  # keep false; caller decides if gameplay should pause
	_advance()

func _advance() -> void:
	if _queue.is_empty():
		_active = false
		visible = false
		queue_finished.emit()
		return

	var entry: Dictionary = _queue.pop_front()
	_speaker_label.text = entry.get("speaker", "")
	_current_text = entry.get("text", "")
	_label.text = _current_text
	_label.visible_characters = 0
	_visible_chars = 0.0
	_is_typing = true
	_prompt.visible = false
	line_finished.emit()

## True while a dialogue sequence is playing -- gameplay scripts should
## check this to suppress movement/pull/etc. during forced story beats.
func is_active() -> bool:
	return _active
