extends GutTest

const DroneManagerScript = preload("res://scripts/combat/drone_manager.gd")

func test_authority_ids_cap_destroy_and_replacement() -> void:
	var client = DroneManagerScript.new(false)
	assert_eq(client.spawn_drone(), {})
	assert_false(client.destroy_drone(1))
	assert_false(client.update_drone(1, Vector2.ONE))
	assert_true(client.apply_snapshot({"revision": 0, "emitted_cursor": 1, "next_id": 9, "drones": [], "destroyed_ids": [1,2,3,4,5,6,7,8]}))
	var manager = DroneManagerScript.new()
	for i in 12: assert_eq(manager.spawn_drone().id, i + 1)
	assert_eq(manager.spawn_drone(), {})
	assert_true(manager.destroy_drone(4))
	assert_eq(manager.spawn_drone().id, 13)
	assert_true(manager.destroy_drone(1))
	assert_eq(manager.spawn_drone().id, 14)
	assert_eq(manager.active_drones().size(), 12)

func test_snapshot_is_stable_and_idempotent() -> void:
	var manager = DroneManagerScript.new()
	manager.spawn_drone(Vector2(2, 3)); manager.spawn_drone(Vector2(4, 5))
	var state = manager.snapshot()
	assert_false(manager.apply_snapshot(state))
	var client = DroneManagerScript.new(false)
	assert_true(client.apply_snapshot(state))
	assert_true(client.apply_snapshot(state))
	assert_eq(client.snapshot(), state)
	var non_canonical = state.duplicate(true)
	non_canonical.drones.reverse()
	assert_false(DroneManagerScript.new(false).apply_snapshot(non_canonical))

func test_client_late_join_hydrates_full_state_without_lifecycle_mutation() -> void:
	var server = DroneManagerScript.new()
	server.spawn_drone(Vector2(2, 3), true)
	server.spawn_drone(Vector2(4, 5))
	server.destroy_drone(1)
	var state = server.snapshot()
	var client = DroneManagerScript.new(false)
	assert_true(client.apply_snapshot(state))
	assert_eq(client.snapshot(), state)
	assert_true(client.apply_snapshot(state))
	assert_eq(client.snapshot(), state)
	assert_eq(client.spawn_drone(), {})
	assert_false(client.destroy_drone(2))
	assert_false(client.update_drone(2, Vector2.ONE))

func test_accepted_snapshot_does_not_regress_next_id_or_tombstones() -> void:
	var client = DroneManagerScript.new(false)
	var newer := {"revision": 4, "emitted_cursor": 4, "next_id": 8, "drones": [{"id": 7, "position": Vector2.ONE, "formation_open": false}], "destroyed_ids": [1,2,3,4,5,6]}
	assert_true(client.apply_snapshot(newer))
	var stale_cursor := {"revision": 4, "emitted_cursor": 3, "next_id": 7, "drones": [{"id": 7, "position": Vector2.ONE, "formation_open": false}], "destroyed_ids": [1,2,3,4,5,6]}
	assert_false(client.apply_snapshot(stale_cursor))
	assert_eq(client.snapshot().next_id, 8)
	assert_eq(client.snapshot().destroyed_ids, [1,2,3,4,5,6])

func test_snapshot_never_regresses_ids_or_resurrects_destroyed_drone() -> void:
	var manager = DroneManagerScript.new()
	manager.spawn_drone(); manager.spawn_drone(); manager.destroy_drone(1)
	var current = manager.snapshot()
	var client = DroneManagerScript.new(false); assert_true(client.apply_snapshot(current))
	var stale := {"revision": 0, "emitted_cursor": 0, "next_id": 2, "drones": [{"id": 1, "position": Vector2.ZERO, "formation_open": false}], "destroyed_ids": []}
	assert_false(client.apply_snapshot(stale))
	assert_eq(client.snapshot(), current)
	assert_eq(manager.spawn_drone().id, 3)

func test_same_emitted_cursor_only_accepts_idempotent_snapshot() -> void:
	var manager = DroneManagerScript.new()
	manager.spawn_drone()
	var state = manager.snapshot()
	var client = DroneManagerScript.new(false)
	assert_true(client.apply_snapshot(state))
	var conflicting = state.duplicate(true)
	conflicting.drones[0].position = Vector2.ONE
	assert_false(client.apply_snapshot(conflicting))
	assert_true(client.apply_snapshot(state))

func test_snapshot_rejects_cap_tombstone_conflict_and_missing_issued_id() -> void:
	var client = DroneManagerScript.new(false)
	var over_cap: Array = []
	for id in range(1, 14): over_cap.append({"id":id, "position":Vector2.ZERO, "formation_open":false})
	assert_false(client.apply_snapshot({"revision":1, "emitted_cursor":1, "next_id":14, "drones":over_cap, "destroyed_ids":[]}))
	assert_false(client.apply_snapshot({"revision":1, "emitted_cursor":1, "next_id":2, "drones":[{"id":1, "position":Vector2.ZERO, "formation_open":false}], "destroyed_ids":[1]}))
	assert_false(client.apply_snapshot({"revision":1, "emitted_cursor":1, "next_id":3, "drones":[{"id":2, "position":Vector2.ZERO, "formation_open":false}], "destroyed_ids":[]}))

func test_malformed_snapshot_is_rejected_before_normalization() -> void:
	var client = DroneManagerScript.new(false)
	assert_false(client.apply_snapshot({"revision":1, "emitted_cursor":1, "next_id":2, "drones":["not-a-drone"], "destroyed_ids":[1]}))
	assert_false(client.apply_snapshot({"revision":1, "emitted_cursor":1, "next_id":2, "drones":[{}], "destroyed_ids":[1]}))
	assert_false(client.apply_snapshot({"revision":1, "emitted_cursor":1, "next_id":2, "drones":[{"id":1, "formation_open":false}], "destroyed_ids":[]}))
	assert_false(client.apply_snapshot({"revision":1, "emitted_cursor":1, "next_id":2, "drones":[{"id":1, "position":Vector2.ZERO}], "destroyed_ids":[]}))
	assert_false(client.apply_snapshot({"revision":1, "emitted_cursor":1, "next_id":2, "drones":[{"id":"1", "position":Vector2.ZERO, "formation_open":false}], "destroyed_ids":[]}))
	assert_false(client.apply_snapshot({"revision":1, "emitted_cursor":1, "next_id":2, "drones":[{"id":1, "position":{}, "formation_open":false}], "destroyed_ids":[]}))
	assert_false(client.apply_snapshot({"revision":1, "emitted_cursor":1, "next_id":2, "drones":[{"id":1, "position":Vector2.ZERO, "formation_open":[]}], "destroyed_ids":[]}))
	assert_false(client.apply_snapshot({"revision":1, "emitted_cursor":1, "next_id":2, "drones":[], "destroyed_ids":{}}))
	assert_false(client.apply_snapshot({"revision":"1", "emitted_cursor":1, "next_id":2, "drones":[], "destroyed_ids":[1]}))
	assert_false(client.apply_snapshot({"revision":1, "emitted_cursor":"1", "next_id":2, "drones":[], "destroyed_ids":[1]}))
	assert_false(client.apply_snapshot({"revision":1, "emitted_cursor":1, "next_id":"2", "drones":[], "destroyed_ids":[1]}))
	assert_false(client.apply_snapshot({"revision":1, "emitted_cursor":1, "next_id":2, "drones":{}, "destroyed_ids":[1]}))
	assert_false(client.apply_snapshot({"revision":1, "emitted_cursor":1, "next_id":2, "drones":[], "destroyed_ids":["1"]}))
