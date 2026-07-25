class_name RoomRuntime
extends RefCounted

signal room_cleared

enum State { CREATED, RUNNING, SPAWNS_DONE, CLEARED, FAILED }

var _state: State = State.CREATED
var state: State:
	get:
		return _state

var _active_enemies: Dictionary = {}
var _spawns_finished: bool = false
var _clear_emitted: bool = false
var reward_offer: RewardOffer

func start() -> void:
	if _state != State.CREATED:
		return
	_state = State.RUNNING

func register_spawn(enemy: Node) -> void:
	if _state != State.RUNNING or enemy == null:
		return
	var instance_id := enemy.get_instance_id()
	if _active_enemies.has(instance_id):
		return
	_active_enemies[instance_id] = true

func resolve_enemy(enemy: Node, _reason: int) -> void:
	if enemy == null:
		return
	resolve_enemy_id(enemy.get_instance_id())

func resolve_enemy_id(instance_id: int) -> void:
	if not _active_enemies.has(instance_id):
		return
	_active_enemies.erase(instance_id)
	_check_clear()

func mark_spawns_finished() -> void:
	if _spawns_finished or _state != State.RUNNING:
		return
	_spawns_finished = true
	_state = State.SPAWNS_DONE
	_check_clear()

func fail_start() -> void:
	if _state != State.RUNNING:
		return
	_state = State.FAILED

func active_enemy_count() -> int:
	return _active_enemies.size()

func is_cleared() -> bool:
	return _state == State.CLEARED

func _check_clear() -> void:
	if _clear_emitted or not _spawns_finished or not _active_enemies.is_empty():
		return
	_state = State.CLEARED
	_clear_emitted = true
	room_cleared.emit()
