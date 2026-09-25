class_name RoomRuntime
extends RefCounted

signal room_cleared
signal progress_changed(snapshot: Dictionary)

enum State { CREATED, RUNNING, SPAWNS_DONE, CLEARED, FAILED }

var _state: State = State.CREATED
var state: State:
	get:
		return _state

var _active_enemies: Dictionary = {}
var _spawns_finished: bool = false
var _clear_emitted: bool = false
var _expected_spawn_count: int = 0
var _spawned_count: int = 0
var _resolved_count: int = 0
var reward_offer: RewardOffer

func start() -> void:
	if _state != State.CREATED:
		return
	_state = State.RUNNING
	_emit_progress()

func configure_expected_spawn_count(count: int) -> void:
	_expected_spawn_count = maxi(0, count)
	_emit_progress()

func register_spawn(enemy: Node) -> void:
	if _state != State.RUNNING or enemy == null:
		return
	var instance_id := enemy.get_instance_id()
	if _active_enemies.has(instance_id):
		return
	_active_enemies[instance_id] = true
	_spawned_count += 1
	_emit_progress()

func resolve_enemy(enemy: Node, _reason: int) -> void:
	if enemy == null:
		return
	resolve_enemy_id(enemy.get_instance_id())

func resolve_enemy_id(instance_id: int) -> void:
	if not _active_enemies.has(instance_id):
		return
	_active_enemies.erase(instance_id)
	_resolved_count = mini(_expected_spawn_count, _resolved_count + 1)
	_emit_progress()
	_check_clear()

func mark_spawns_finished() -> void:
	if _spawns_finished or _state != State.RUNNING:
		return
	_spawns_finished = true
	_state = State.SPAWNS_DONE
	_emit_progress()
	_check_clear()

func fail_start() -> void:
	if _state != State.RUNNING:
		return
	_state = State.FAILED

func active_enemy_count() -> int:
	return _active_enemies.size()

func is_cleared() -> bool:
	return _state == State.CLEARED

func progress_snapshot() -> Dictionary:
	return {
		"expected_spawn_count": _expected_spawn_count,
		"spawned_count": _spawned_count,
		"resolved_count": _resolved_count,
		"active_enemy_count": _active_enemies.size(),
		"spawns_finished": _spawns_finished,
		"combat_cleared": _state == State.CLEARED,
	}

func _emit_progress() -> void:
	progress_changed.emit(progress_snapshot())

func _check_clear() -> void:
	# A director may finish before all of its agenda has materialized.  A room is
	# clear only after every expected unique spawn has been resolved (including 0).
	if _clear_emitted or not _spawns_finished or not _active_enemies.is_empty() or _resolved_count < _expected_spawn_count:
		return
	_state = State.CLEARED
	_clear_emitted = true
	# Publish the terminal snapshot before the clear observer advances the room.
	_emit_progress()
	room_cleared.emit()
