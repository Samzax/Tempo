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

func test_debris_does_not_block_clear_and_controller_emits_each_completion_signal_once() -> void:
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
	var debris := preload("res://scenes/world/debris.tscn").instantiate()
	room_root.add_child(debris)
	director.spawns_finished.emit()
	assert_eq(controller.runtime.state, RoomRuntime.State.CLEARED)
	assert_signal_emit_count(controller, &"combat_cleared", 1)
	assert_signal_emit_count(controller, &"room_completed", 1)
	controller.runtime.room_cleared.emit()
	assert_signal_emit_count(controller, &"combat_cleared", 1)
	assert_signal_emit_count(controller, &"room_completed", 1)

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

func _legacy_room_controller_warning_fx_first_pair() -> void:
	var room_root := Node.new()
	add_child_autofree(room_root)
	var effects := Node.new()
	effects.add_to_group(&"effects")
	room_root.add_child(effects)
	var container := Node.new()
	container.add_to_group(&"enemies_container")
	room_root.add_child(container)
	var director := preload("res://scripts/directors/spawn_director.gd").new()
	director.name = "Director"
	room_root.add_child(director)
	var controller := RoomController.new()
	var room_def := RoomDef.new()
	room_def.wave_specs = [room_def.get_phase_one_waves()[0]]
	controller.room_def = room_def
	controller.director_path = ^"../Director"
	room_root.add_child(controller)
	watch_signals(controller)
	await get_tree().process_frame
	var warning_times: Array[float] = []
	var warning_points: Array[Vector2] = []
	var spawn_times: Array[float] = []
	var elapsed: Array[float] = [0.0]
	controller.spawn_warning_observed.connect(func(_wave: int, _spawn: int, point: Vector2) -> void:
		warning_times.append(elapsed[0])
		warning_points.append(point)
	)
	director.enemy_spawned.connect(func(_enemy: Enemy) -> void: spawn_times.append(elapsed[0]))
	var advance := func(delta: float) -> void:
		elapsed[0] += delta
		director._physics_process(delta)
	var initial_state: Dictionary = director.get_wave_execution_state()
	assert_eq(initial_state.reserved_slots, 0)
	assert_eq(initial_state.active_count, 0)
	advance.call(0.01)
	assert_eq(warning_times.size(), 1)
	assert_eq(warning_points.size(), 1)
	var agenda: Array[Dictionary] = director.get_spawn_agenda()
	assert_eq(director.get_wave_execution_state().reserved_slots, 2)
	assert_eq(effects.get_child_count(), 1)
	assert_eq(warning_points[0], agenda[0].point)
	assert_eq(effects.get_child(0).global_position, agenda[0].point)
	assert_eq(float(effects.get_child(0).get(&"duration")), 0.45)
	assert_eq(container.get_child_count(), 0)
	advance.call(0.34)
	assert_eq(warning_times.size(), 1)
	advance.call(0.01)
	assert_eq(warning_times.size(), 2)
	assert_almost_eq(warning_times[1] - warning_times[0], 0.35, 0.001)
	assert_eq(warning_points[1], agenda[1].point)
	assert_eq(effects.get_child_count(), 2)
	assert_eq(effects.get_child(1).global_position, agenda[1].point)
	assert_eq(float(effects.get_child(1).get(&"duration")), 0.45)
	assert_eq(container.get_child_count(), 0)
	assert_eq(director.get_wave_execution_state().reserved_slots, 2)
	advance.call(0.09)
	assert_eq(container.get_child_count(), 0)
	advance.call(0.01)
	assert_eq(container.get_child_count(), 1)
	assert_eq(spawn_times.size(), 1)
	assert_almost_eq(spawn_times[0] - warning_times[0], 0.45, 0.001)
	assert_eq(director.get_wave_execution_state().reserved_slots, 1)
	advance.call(0.34)
	assert_eq(container.get_child_count(), 1)
	advance.call(0.01)
	assert_eq(container.get_child_count(), 2)
	assert_eq(spawn_times.size(), 2)
	assert_almost_eq(spawn_times[1] - warning_times[1], 0.45, 0.001)
	assert_almost_eq(warning_times[1] - warning_times[0], 0.35, 0.001)
	assert_eq(director.get_wave_execution_state().reserved_slots, 0)
	assert_eq(director.get_wave_execution_state().active_count, 2)
	assert_eq(agenda[0].next_event_delay, 2.4)
	assert_eq(agenda[1].next_event_delay, 2.4)
	assert_true(is_instance_valid(container.get_child(0)))
	# O diretor ainda pode estar aguardando a emissão; interrompa o ciclo antes
	# que o autofree libere o enemies_container no teardown do GUT.
	director.stop()


func test_room_controller_registers_warning_fx_at_agenda_point_for_contract_duration() -> void:
	var room_root := Node.new()
	add_child_autofree(room_root)
	var effects := Node.new()
	effects.add_to_group(&"effects")
	room_root.add_child(effects)
	var container := Node.new()
	container.add_to_group(&"enemies_container")
	room_root.add_child(container)
	var director := preload("res://scripts/directors/spawn_director.gd").new()
	director.name = "Director"
	room_root.add_child(director)
	var controller := RoomController.new()
	var room_def := RoomDef.new()
	room_def.wave_specs = [room_def.get_phase_one_waves()[0]]
	controller.room_def = room_def
	controller.director_path = ^"../Director"
	room_root.add_child(controller)
	await get_tree().process_frame

	var elapsed: Array[float] = [0.0]
	var warning_times: Array[float] = []
	var warning_indices: Array[int] = []
	var warning_points: Array[Vector2] = []
	var fx_points: Array[Vector2] = []
	var spawn_times: Array[float] = []
	controller.spawn_warning_observed.connect(func(_wave: int, spawn_index: int, point: Vector2) -> void:
		warning_times.append(elapsed[0])
		warning_indices.append(spawn_index)
		warning_points.append(point)
		fx_points.append(controller.last_spawn_warning_fx.global_position)
	)
	director.enemy_spawned.connect(func(_enemy: Enemy) -> void: spawn_times.append(elapsed[0]))
	var advance := func(delta: float) -> void:
		elapsed[0] += delta
		director._physics_process(delta)
	var agenda: Array[Dictionary] = director.get_spawn_agenda()
	assert_eq(agenda.size(), 6)
	assert_true(agenda.all(func(entry: Dictionary) -> bool: return entry.max_active == 2))

	advance.call(0.01)
	for pair_index in 3:
		var first_member := pair_index * 2
		var second_member := first_member + 1
		assert_eq(warning_indices.back(), first_member)
		assert_eq(warning_points.back(), agenda[first_member].point)
		assert_eq(fx_points.back(), agenda[first_member].point)
		assert_eq(float(effects.get_child(first_member).get(&"duration")), 0.45)
		assert_eq(director.get_wave_execution_state().reserved_slots, 2)
		assert_eq(director.get_wave_execution_state().active_count, 0)

		advance.call(0.35)
		assert_eq(warning_indices.back(), second_member)
		assert_almost_eq(warning_times[second_member] - warning_times[first_member], 0.35, 0.001)
		assert_eq(warning_points.back(), agenda[second_member].point)
		assert_eq(fx_points.back(), agenda[second_member].point)
		assert_eq(float(effects.get_child(second_member).get(&"duration")), 0.45)
		assert_eq(director.get_wave_execution_state().reserved_slots, 2)

		advance.call(0.10)
		assert_almost_eq(spawn_times[first_member] - warning_times[first_member], 0.45, 0.001)
		assert_eq(director.get_wave_execution_state().reserved_slots, 1)
		assert_eq(director.get_wave_execution_state().active_count, 1)
		advance.call(0.35)
		assert_almost_eq(spawn_times[second_member] - warning_times[second_member], 0.45, 0.001)
		assert_eq(director.get_wave_execution_state().reserved_slots, 0)
		assert_eq(director.get_wave_execution_state().active_count, 2)
		for enemy in container.get_children():
			if is_instance_valid(enemy):
				(enemy as Enemy).resolved.emit(enemy, 0)
		assert_eq(director.get_wave_execution_state().active_count, 0)
		if pair_index < 2:
			advance.call(1.60)
			assert_almost_eq(warning_times[first_member + 2] - warning_times[first_member], 2.4, 0.001)

	assert_eq(warning_indices, [0, 1, 2, 3, 4, 5])
	assert_eq(warning_times.size(), 6)
	assert_eq(spawn_times.size(), 6)
	assert_almost_eq(warning_times[0], 0.0, 0.02)
	assert_almost_eq(warning_times[2], 2.4, 0.02)
	assert_almost_eq(warning_times[4], 4.8, 0.02)
	for index in 6:
		assert_eq(warning_points[index], agenda[index].point)
		assert_eq(fx_points[index], agenda[index].point)
		assert_almost_eq(spawn_times[index] - warning_times[index], 0.45, 0.02)
	assert_eq(director.get_wave_execution_state().active_count, 0)
	director.stop()
	assert_false(director.is_physics_processing())


func test_w5_finishes_immediately_after_the_last_enemy_resolves_without_a_breather() -> void:
	var room_root := Node.new()
	add_child_autofree(room_root)
	var container := Node.new()
	container.add_to_group(&"enemies_container")
	room_root.add_child(container)
	var director := preload("res://scripts/directors/spawn_director.gd").new()
	director.name = "Director"
	room_root.add_child(director)
	var controller := RoomController.new()
	var room_def := RoomDef.new()
	room_def.wave_specs = [room_def.get_phase_one_waves()[4]]
	controller.room_def = room_def
	controller.director_path = ^"../Director"
	room_root.add_child(controller)
	watch_signals(director)
	await get_tree().process_frame

	for spawn_index in 30:
		director._physics_process(0.01 if spawn_index == 0 else 0.30)
		director._physics_process(0.45)
		var enemy := container.get_child(spawn_index) as Enemy
		enemy.resolved.emit(enemy, 0)

	assert_signal_not_emitted(director, &"spawns_finished")
	director._physics_process(0.01)
	assert_signal_emit_count(director, &"spawns_finished", 1)
	assert_eq(director.get_wave_execution_state().breather_remaining, -1.0)
	assert_true(controller.runtime.is_cleared())


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
