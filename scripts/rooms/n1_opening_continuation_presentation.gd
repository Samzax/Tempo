class_name N1OpeningContinuationPresentation
extends Node

const PLAYER := preload("res://scripts/backgrounds/n0_n1_v27_player.gd")
var player: N0N1V27Player
var _frame := 809
var _accumulator := 0.0

func _ready() -> void:
	player = PLAYER.ensure_for_viewport(get_viewport())
	player.show()
	player.show_frame(809)
	player.begin_continuation_drift()

func _process(delta: float) -> void:
	if get_tree().paused or player == null:
		return
	player.tick_parallax(delta)
	_accumulator += delta
	while _accumulator >= 1.0 / 30.0 and _frame <= 988:
		_accumulator -= 1.0 / 30.0
		if player.show_frame(_frame):
			_frame += 1
		else:
			_accumulator += 1.0 / 30.0
			break
	if _frame > 988:
		player.enter_stable_continuation()
