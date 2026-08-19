## Presentation-only state observer for CasuloExplosivo.
class_name CasuloExplosivoVisual
extends Sprite2D

const FRAME_IDLE := preload("res://assets/sprites/enemies/regente-dos-ecos/drones/regente-casulo-p2-f0.png")
const FRAME_TRACKING := preload("res://assets/sprites/enemies/regente-dos-ecos/drones/regente-casulo-p2-f1.png")
const FRAME_DETONATE := preload("res://assets/sprites/enemies/regente-dos-ecos/drones/regente-casulo-p2-f2.png")
const FRAME_RESET := preload("res://assets/sprites/enemies/regente-dos-ecos/drones/regente-casulo-p2-f3.png")

const IDLE := 0
const IN_SLOT := 1
const TRACKING := 2
const LOCKED := 3
const DETONATING := 4
const EMPTY := 5
const DESTROYED := 6
const DETONATE_HOLD_SECONDS := 0.16
const RESET_HOLD_SECONDS := 0.12

var _last_state := -1
var _hold_seconds := 0.0
var _presentation := "hidden"
var _reconstitution_pending := false

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_process_state(0.0)

func _process(delta: float) -> void:
	_process_state(delta)

func _process_state(delta: float) -> void:
	var parent := _logical_parent()
	if parent == null:
		_reset_lifecycle_to_hidden()
		return
	var state: int = int(parent.get("state"))
	if state == DESTROYED:
		_hold_seconds = 0.0
		_reconstitution_pending = false
		_show_hidden()
		_last_state = state
		return
	if _hold_seconds > 0.0:
		if _presentation == "detonate" and state == IN_SLOT:
			_reconstitution_pending = true
		_hold_seconds = maxf(0.0, _hold_seconds - maxf(delta, 0.0))
		if _hold_seconds > 0.0:
			_last_state = state
			return
		if _presentation == "detonate" and _reconstitution_pending:
			_reconstitution_pending = false
			_show_frame(FRAME_RESET, "reset")
			_hold_seconds = RESET_HOLD_SECONDS
			_last_state = state
			return
		if state == EMPTY:
			_show_hidden()
			_last_state = state
			return
	if state == DETONATING or (state == EMPTY and _last_state >= TRACKING and _last_state <= DETONATING):
		_show_frame(FRAME_DETONATE, "detonate")
		_hold_seconds = DETONATE_HOLD_SECONDS
		_last_state = state
		return
	if state == IN_SLOT and _last_state == EMPTY:
		_show_frame(FRAME_RESET, "reset")
		_hold_seconds = RESET_HOLD_SECONDS
		_last_state = state
		return
	match state:
		IDLE, IN_SLOT:
			_show_frame(FRAME_IDLE, "idle")
		TRACKING, LOCKED:
			_show_frame(FRAME_TRACKING, "tracking")
		EMPTY:
			_show_hidden()
		_:
			_show_hidden()
	_last_state = state

func _show_frame(next_texture: Texture2D, label: String) -> void:
	texture = next_texture
	visible = true
	_presentation = label

func _show_hidden() -> void:
	visible = false
	_presentation = "hidden"

func _reset_lifecycle_to_hidden() -> void:
	_show_hidden()
	_last_state = -1
	_hold_seconds = 0.0
	_reconstitution_pending = false

func _logical_parent() -> Node:
	var parent := get_parent()
	if parent == null or not is_instance_valid(parent) or parent.is_queued_for_deletion():
		return null
	if typeof(parent.get("state")) != TYPE_INT:
		return null
	return parent

func runtime_snapshot() -> Dictionary:
	return {
		"parent_bound": _logical_parent() != null,
		"state": _last_state,
		"presentation": _presentation,
		"visible": visible,
		"hold_seconds": _hold_seconds,
		"reconstitution_pending": _reconstitution_pending,
		"idle_texture_loaded": FRAME_IDLE != null,
		"tracking_texture_loaded": FRAME_TRACKING != null,
		"detonate_texture_loaded": FRAME_DETONATE != null,
		"reset_texture_loaded": FRAME_RESET != null,
	}
