extends GutTest

const ENEMY_SCENE := preload("res://scenes/enemies/enemy.tscn")

class FakeDirector extends Node:
	signal enemy_spawned(enemy: Enemy)
	signal spawns_finished
	signal spawns_failed(reason: String)

	func start(_spawn_limit: int) -> bool:
		return true

func _runtime() -> RoomRuntime:
	var runtime := RoomRuntime.new()
	watch_signals(runtime)
	return runtime

func _enemy() -> Node:
	var enemy := Node.new()
	autofree(enemy)
	return enemy

func test_new_runtime_is_created_empty_and_not_cleared() -> void:
	var runtime := _runtime()

	assert_eq(runtime.state, RoomRuntime.State.CREATED)
	assert_eq(runtime.active_enemy_count(), 0)
	assert_false(runtime.is_cleared())

func test_start_transitions_to_running_and_is_idempotent() -> void:
	var runtime := _runtime()

	runtime.start()
	runtime.start()

	assert_eq(runtime.state, RoomRuntime.State.RUNNING)
	assert_signal_not_emitted(runtime, &"room_cleared")

func test_register_spawn_counts_unique_nodes_and_ignores_duplicate_and_null() -> void:
	var runtime := _runtime()
	var first := _enemy()
	var second := _enemy()
	runtime.start()

	runtime.register_spawn(first)
	runtime.register_spawn(second)
	runtime.register_spawn(first)
	runtime.register_spawn(null)

	assert_eq(runtime.active_enemy_count(), 2)

func test_resolving_before_spawns_finished_keeps_remaining_enemy_and_not_cleared() -> void:
	var runtime := _runtime()
	var first := _enemy()
	var second := _enemy()
	runtime.start()
	runtime.register_spawn(first)
	runtime.register_spawn(second)

	runtime.resolve_enemy(first, 0)

	assert_eq(runtime.active_enemy_count(), 1)
	assert_false(runtime.is_cleared())
	assert_signal_not_emitted(runtime, &"room_cleared")

func test_finish_with_active_enemies_transitions_to_spawns_done_without_clearing() -> void:
	var runtime := _runtime()
	runtime.start()
	runtime.register_spawn(_enemy())

	runtime.mark_spawns_finished()

	assert_eq(runtime.state, RoomRuntime.State.SPAWNS_DONE)
	assert_false(runtime.is_cleared())
	assert_signal_not_emitted(runtime, &"room_cleared")

func test_resolving_last_enemy_after_finish_clears_once() -> void:
	var runtime := _runtime()
	var enemy := _enemy()
	runtime.start()
	runtime.register_spawn(enemy)
	runtime.mark_spawns_finished()

	runtime.resolve_enemy(enemy, 0)

	assert_eq(runtime.state, RoomRuntime.State.CLEARED)
	assert_true(runtime.is_cleared())
	assert_signal_emit_count(runtime, &"room_cleared", 1)

func test_duplicate_and_unknown_resolutions_do_not_reemit_clear() -> void:
	var runtime := _runtime()
	var enemy := _enemy()
	var unknown := _enemy()
	runtime.start()
	runtime.register_spawn(enemy)
	runtime.mark_spawns_finished()
	runtime.resolve_enemy(enemy, 0)

	runtime.resolve_enemy(enemy, 0)
	runtime.resolve_enemy(unknown, 0)

	assert_eq(runtime.state, RoomRuntime.State.CLEARED)
	assert_signal_emit_count(runtime, &"room_cleared", 1)

func test_resolution_by_instance_id_is_idempotent() -> void:
	var runtime := _runtime()
	var enemy := _enemy()
	runtime.start()
	runtime.register_spawn(enemy)
	runtime.mark_spawns_finished()

	var instance_id := enemy.get_instance_id()
	runtime.resolve_enemy_id(instance_id)
	runtime.resolve_enemy_id(instance_id)

	assert_eq(runtime.active_enemy_count(), 0)
	assert_eq(runtime.state, RoomRuntime.State.CLEARED)
	assert_signal_emit_count(runtime, &"room_cleared", 1)

func test_failed_start_does_not_clear_room() -> void:
	var runtime := _runtime()
	runtime.start()
	runtime.fail_start()

	assert_eq(runtime.state, RoomRuntime.State.FAILED)
	assert_false(runtime.is_cleared())
	assert_signal_not_emitted(runtime, &"room_cleared")

func test_tree_exit_resolves_registered_enemy_once() -> void:
	var room_root := Node.new()
	add_child_autofree(room_root)
	var director := FakeDirector.new()
	director.name = "Director"
	room_root.add_child(director)
	var controller := RoomController.new()
	controller.room_def = RoomDef.new()
	controller.director_path = ^"../Director"
	room_root.add_child(controller)
	watch_signals(controller)
	await get_tree().process_frame

	var enemy := ENEMY_SCENE.instantiate() as Enemy
	room_root.add_child(enemy)
	director.enemy_spawned.emit(enemy)
	director.spawns_finished.emit()
	enemy.queue_free()
	await get_tree().process_frame

	assert_eq(controller.runtime.active_enemy_count(), 0)
	assert_true(controller.runtime.is_cleared())
	assert_signal_emit_count(controller, &"room_cleared", 1)

func test_resolved_then_tree_exit_is_idempotent_and_clears_once() -> void:
	var room_root := Node.new()
	add_child_autofree(room_root)
	var director := FakeDirector.new()
	director.name = "Director"
	room_root.add_child(director)
	var controller := RoomController.new()
	controller.room_def = RoomDef.new()
	controller.director_path = ^"../Director"
	room_root.add_child(controller)
	watch_signals(controller)
	await get_tree().process_frame

	var enemy := ENEMY_SCENE.instantiate() as Enemy
	room_root.add_child(enemy)
	director.enemy_spawned.emit(enemy)
	director.spawns_finished.emit()
	enemy.resolved.emit(enemy, 0)
	enemy.queue_free()
	await get_tree().process_frame

	assert_eq(controller.runtime.active_enemy_count(), 0)
	assert_true(controller.runtime.is_cleared())
	assert_signal_emit_count(controller, &"room_cleared", 1)

func test_spawn_failure_marks_controller_runtime_failed() -> void:
	var room_root := Node.new()
	add_child_autofree(room_root)
	var director := FakeDirector.new()
	director.name = "Director"
	room_root.add_child(director)
	var controller := RoomController.new()
	controller.room_def = RoomDef.new()
	controller.director_path = ^"../Director"
	room_root.add_child(controller)
	await get_tree().process_frame

	director.spawns_failed.emit("missing enemies container")

	assert_eq(controller.runtime.state, RoomRuntime.State.FAILED)
	assert_false(controller.runtime.is_cleared())

func test_missing_director_container_fails_controller_runtime_without_clearing() -> void:
	var room_root := Node.new()
	add_child_autofree(room_root)
	var director := preload("res://scripts/directors/spawn_director.gd").new()
	director.name = "Director"
	room_root.add_child(director)
	watch_signals(director)
	var controller := RoomController.new()
	var room_def := RoomDef.new()
	room_def.finite_spawn_count = 1
	controller.room_def = room_def
	controller.director_path = ^"../Director"
	room_root.add_child(controller)
	watch_signals(controller)
	await get_tree().process_frame

	assert_eq(controller.runtime.state, RoomRuntime.State.FAILED)
	assert_false(controller.runtime.is_cleared())
	assert_signal_emit_count(director, &"spawns_failed", 1)
	assert_signal_not_emitted(director, &"spawns_finished")
	assert_signal_not_emitted(controller, &"room_cleared")

func test_finish_with_zero_enemies_clears_immediately_once() -> void:
	var runtime := _runtime()
	runtime.start()

	runtime.mark_spawns_finished()

	assert_eq(runtime.state, RoomRuntime.State.CLEARED)
	assert_true(runtime.is_cleared())
	assert_signal_emit_count(runtime, &"room_cleared", 1)

func test_register_spawn_is_ignored_after_spawns_done_or_cleared() -> void:
	var runtime := _runtime()
	var after_finish := _enemy()
	runtime.start()
	runtime.mark_spawns_finished()
	runtime.register_spawn(after_finish)

	assert_eq(runtime.state, RoomRuntime.State.CLEARED)
	assert_eq(runtime.active_enemy_count(), 0)
	assert_signal_emit_count(runtime, &"room_cleared", 1)

	var cleared_enemy := _enemy()
	runtime.register_spawn(cleared_enemy)
	assert_eq(runtime.active_enemy_count(), 0)
	assert_signal_emit_count(runtime, &"room_cleared", 1)

func test_room_def_defaults_and_finite_spawn_count() -> void:
	var room_def := RoomDef.new()

	assert_eq(room_def.room_type, RoomDef.RoomType.OPENING)
	assert_eq(room_def.camera_policy, RoomDef.CameraPolicy.FIXED)
	assert_eq(room_def.cull_policy, RoomDef.CullPolicy.DESPAWN_BOTTOM)
	assert_eq(room_def.clear_policy, RoomDef.ClearPolicy.ALL_SPAWNS_RESOLVED)
	assert_eq(room_def.finite_spawn_count, 5)
