## Server-authoritative registry for Regente drones.
## Snapshots hydrate both servers and clients; only lifecycle mutations require authority.
class_name DroneManager
extends RefCounted

const MAX_DRONES := 12

var is_server := true
var _next_id := 1
var _revision := 0
var _emitted_cursor := 0 # Monotonic snapshot cursor; never regresses during hydration.
var _drones: Dictionary = {}
var _destroyed_ids: Dictionary = {}

func _init(server_authority := true) -> void:
	is_server = server_authority

func spawn_drone(position := Vector2.ZERO, formation_open := false) -> Dictionary:
	if not is_server or _drones.size() >= MAX_DRONES:
		return {}
	var drone := {"id": _next_id, "position": position, "formation_open": formation_open}
	_drones[_next_id] = drone
	_next_id += 1
	_revision += 1
	_emitted_cursor += 1
	return drone.duplicate(true)

func destroy_drone(drone_id: int) -> bool:
	if not is_server or not _drones.has(drone_id):
		return false
	_drones.erase(drone_id)
	_destroyed_ids[drone_id] = true
	_revision += 1
	_emitted_cursor += 1
	return true

func update_drone(drone_id: int, position: Vector2, formation_open := false) -> bool:
	if not is_server or not _drones.has(drone_id):
		return false
	_drones[drone_id] = {"id": drone_id, "position": position, "formation_open": formation_open}
	_revision += 1
	_emitted_cursor += 1
	return true

func active_drones() -> Array:
	var result: Array = []
	for drone_id in _drones.keys():
		result.append(_drones[drone_id].duplicate(true))
	result.sort_custom(func(a, b): return a.id < b.id)
	return result

func snapshot() -> Dictionary:
	var destroyed_ids: Array = _destroyed_ids.keys()
	destroyed_ids.sort()
	return {"revision": _revision, "emitted_cursor": _emitted_cursor, "next_id": _next_id, "drones": active_drones(), "destroyed_ids": destroyed_ids}

func apply_snapshot(state: Dictionary) -> bool:
	# A host is the sole lifecycle writer; only client replicas hydrate remote state.
	if is_server:
		return false
	if not _valid_raw_snapshot(state):
		return false
	var canonical := _normalize_snapshot(state)
	if canonical.is_empty() or state != canonical or not _valid_snapshot(canonical):
		return false
	var incoming_revision := int(canonical.get("revision", 0))
	var incoming_cursor := int(canonical.emitted_cursor)
	if incoming_cursor < _emitted_cursor: return false
	if incoming_revision < _revision: return false
	if incoming_cursor == _emitted_cursor: return snapshot() == canonical
	if int(canonical.next_id) < _next_id: return false # Issued-ID cursor may not regress.
	for destroyed_id in _destroyed_ids.keys():
		if not canonical.destroyed_ids.has(destroyed_id): return false
	var restored: Dictionary = {}
	var highest_id := 0
	for drone in canonical.drones:
		var drone_id := int(drone.id)
		restored[drone_id] = drone.duplicate(true)
		highest_id = max(highest_id, drone_id)
	for destroyed_id in canonical.get("destroyed_ids", []):
		_destroyed_ids[int(destroyed_id)] = true
		restored.erase(int(destroyed_id))
	_drones = restored
	# IDs are monotonic even if a delayed snapshot advertises an older cursor.
	_next_id = max(_next_id, int(canonical.next_id), highest_id + 1)
	_revision = max(_revision, incoming_revision)
	_emitted_cursor = incoming_cursor
	return true

func _normalize_snapshot(state: Dictionary) -> Dictionary:
	if not state.has_all(["revision", "emitted_cursor", "next_id", "drones", "destroyed_ids"]) or not state.drones is Array or not state.destroyed_ids is Array:
		return {}
	var normalized := state.duplicate(true)
	normalized.drones.sort_custom(func(a, b): return int(a.id) < int(b.id))
	normalized.destroyed_ids.sort()
	return normalized

func _valid_raw_snapshot(state: Dictionary) -> bool:
	if not state.has_all(["revision", "emitted_cursor", "next_id", "drones", "destroyed_ids"]): return false
	if not state.revision is int or not state.emitted_cursor is int or not state.next_id is int or not state.drones is Array or not state.destroyed_ids is Array: return false
	for drone in state.drones:
		if not drone is Dictionary or not drone.has_all(["id", "position", "formation_open"]): return false
		if not drone.id is int or not drone.position is Vector2 or not drone.formation_open is bool: return false
	for destroyed_id in state.destroyed_ids:
		if not destroyed_id is int: return false
	return true

func _valid_snapshot(state: Dictionary) -> bool:
	var incoming_drones = state.get("drones", [])
	if not state.has_all(["revision", "emitted_cursor", "next_id", "drones", "destroyed_ids"]) or int(state.next_id) < 1 or int(state.emitted_cursor) < 0 or not incoming_drones is Array:
		return false
	if incoming_drones.size() > MAX_DRONES: return false
	var ids := {}
	for drone in incoming_drones:
		if not drone is Dictionary or not drone.has("id"):
			return false
		var drone_id := int(drone.id)
		if drone_id < 1 or ids.has(drone_id):
			return false
		ids[drone_id] = true
	if not state.destroyed_ids is Array:
		return false
	var highest_known := 0
	for drone_id in ids.keys(): highest_known = max(highest_known, int(drone_id))
	var tombstones := {}
	for destroyed_id in state.destroyed_ids:
		var tombstone_id := int(destroyed_id)
		if tombstone_id < 1 or tombstones.has(tombstone_id) or ids.has(tombstone_id): return false
		tombstones[tombstone_id] = true
		highest_known = max(highest_known, tombstone_id)
	if int(state.next_id) <= highest_known: return false
	# Every issued ID must be represented, so an incomplete state cannot resurrect it later.
	for issued_id in range(1, int(state.next_id)):
		if not ids.has(issued_id) and not tombstones.has(issued_id): return false
	return true
