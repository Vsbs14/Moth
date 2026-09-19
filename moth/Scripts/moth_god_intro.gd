extends Node
## Drives the opening Moth God cutscene + the first-few-feet tutorial beats.
## Attach to a plain Node placed in level.tscn (e.g. "IntroSequence"), and
## wire `moth` to your Moth node in the Inspector.
##
## Requires DialogueBox autoload (see dialogue_box.gd).

@export var moth: CharacterBody2D
@export var tutorial_altitude_resist := 60.0   # px climbed before the Resist tip fires
@export var tutorial_altitude_qte := 220.0     # px climbed before the QTE tip fires

var _freeze_input := false
var _shown_resist_tip := false
var _shown_qte_tip := false

func _ready() -> void:
	DialogueBox.queue_finished.connect(_on_intro_finished)
	_play_intro()

func _play_intro() -> void:
	_freeze_input = true
	if moth:
		moth.set_physics_process(false)  # hold the moth still during the opening lines

	var lines: Array[Dictionary] = [
		{"speaker": "Moth God", "text": "Brother. You must crave the billion lamps."},
		{"speaker": "Moth God", "text": "Climb, and do not yield to every light you see."},
	]
	DialogueBox.show_lines(lines)

func _on_intro_finished() -> void:
	if not _freeze_input:
		return  # a later tutorial line finished, not the intro -- ignore
	_freeze_input = false
	if moth:
		moth.set_physics_process(true)

func _physics_process(_delta: float) -> void:
	if _freeze_input or not moth:
		return

	# current_altitude is already tracked on Moth (px climbed above spawn).
	if not _shown_resist_tip and moth.current_altitude >= tutorial_altitude_resist:
		_shown_resist_tip = true
		DialogueBox.show_lines([
			{"speaker": "Moth God", "text": "You feel it pulling. Mash [Space] to resist the call."}
		])

	if not _shown_qte_tip and moth.current_altitude >= tutorial_altitude_qte:
		_shown_qte_tip = true
		DialogueBox.show_lines([
			{"speaker": "Moth God", "text": "A hunter circles. If it corners you, strike back with [Q]."}
		])
