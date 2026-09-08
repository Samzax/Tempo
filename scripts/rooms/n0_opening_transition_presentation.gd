class_name N0OpeningTransitionPresentation
extends Node

signal sequence_completed
const PLAYER := preload("res://scripts/backgrounds/n0_n1_v27_player.gd")
const PROGRESS := preload("res://scripts/backgrounds/n0_n1_v27_progress.gd")
var runtime: RoomRuntime
var model := PROGRESS.new()
var player: N0N1V27Player
var _combat_done := false
var _tail_frame := -1
var _accumulator := 0.0

func configure(value: RoomRuntime) -> void:
	runtime = value

func _ready() -> void:
	player = PLAYER.ensure_for_viewport(get_viewport())
	if runtime != null:
		runtime.progress_changed.connect(_on_progress_changed)
		_on_progress_changed(runtime.progress_snapshot())

func _process(delta: float) -> void:
	# This presentation is also instantiated by pause-focused tests before a
	# RoomRuntime is configured. Until configure() supplies one, it has no
	# authoritative combat snapshot to apply and must remain inert.
	if get_tree().paused or player == null or runtime == null:
		return
	player.tick_parallax(delta)
	if not _combat_done:
		player.show_progress(model.update_from_snapshot(runtime.progress_snapshot(), delta))
		return
	if player.current_frame < 718:
		player.advance_toward(718, delta, 2.0)
		return
	_accumulator += delta
	while _accumulator >= 1.0 / 30.0 and _tail_frame <= 808:
		_accumulator -= 1.0 / 30.0
		if player.show_frame(_tail_frame):
			_tail_frame += 1
		else:
			_accumulator += 1.0 / 30.0
			break
	if _tail_frame > 808:
		if not player.show_frame(809):
			return
		sequence_completed.emit()
		set_process(false)

func _on_progress_changed(_snapshot: Dictionary) -> void:
	pass

func combat_cleared() -> void:
	_combat_done = true
	_tail_frame = 719
	player.begin_handoff_approach()
