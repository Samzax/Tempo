extends GutTest

const SPAWN_DIRECTOR := preload("res://scripts/directors/spawn_director.gd")
const ROOM_DEF := preload("res://scripts/rooms/room_def.gd")

func _director() -> Node:
	var director := SPAWN_DIRECTOR.new()
	add_child_autofree(director)
	watch_signals(director)
	return director

func _director_with_container() -> Dictionary:
	var room_root := Node.new()
	add_child_autofree(room_root)
	var container := Node.new()
	container.add_to_group(&"enemies_container")
	room_root.add_child(container)
	var director := SPAWN_DIRECTOR.new()
	room_root.add_child(director)
	watch_signals(director)
	await get_tree().process_frame
	return {"container": container, "director": director}

func test_start_zero_is_one_shot_and_emits_finished_once() -> void:
	var director := _director()

	assert_true(director.start(0))
	assert_false(director.start(0))

	assert_signal_emit_count(director, &"spawns_finished", 1)
	assert_signal_not_emitted(director, &"spawns_failed")

func test_start_after_finish_does_not_restart_or_emit_again() -> void:
	var director := _director()

	director.start(0)
	assert_false(director.start(5))

	assert_signal_emit_count(director, &"spawns_finished", 1)
	assert_signal_not_emitted(director, &"enemy_spawned")

func test_repeated_start_while_running_does_not_restart_or_duplicate_signals() -> void:
	var fixture := await _director_with_container()
	var director: Node = fixture.director
	director.interval = 0.0

	assert_true(director.start(3))
	assert_false(director.start(3))
	for _frame in 4:
		await get_tree().physics_frame

	assert_signal_emit_count(director, &"enemy_spawned", 3)
	assert_signal_emit_count(director, &"spawns_finished", 1)
	assert_signal_not_emitted(director, &"spawns_failed")
	assert_false(director.start(3))
	assert_signal_emit_count(director, &"enemy_spawned", 3)
	assert_signal_emit_count(director, &"spawns_finished", 1)

func test_normal_five_spawns_emit_five_enemies_and_finish_once() -> void:
	var fixture := await _director_with_container()
	var director: Node = fixture.director
	director.interval = 0.0

	assert_true(director.start(5))
	for _frame in 6:
		await get_tree().physics_frame

	assert_signal_emit_count(director, &"enemy_spawned", 5)
	assert_signal_emit_count(director, &"spawns_finished", 1)
	assert_signal_not_emitted(director, &"spawns_failed")

func test_lost_container_fails_once_without_false_finish() -> void:
	var fixture := await _director_with_container()
	var director: Node = fixture.director
	var container: Node = fixture.container
	director.interval = 0.0

	assert_true(director.start(2))
	container.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame

	assert_signal_emit_count(director, &"spawns_failed", 1)
	assert_signal_not_emitted(director, &"spawns_finished")
	assert_signal_not_emitted(director, &"enemy_spawned")
	assert_false(director.is_physics_processing())
	assert_false(director.start(2))
	assert_signal_emit_count(director, &"spawns_failed", 1)

func test_start_with_missing_container_fails_without_false_finish() -> void:
	var director := _director()

	assert_false(director.start(5))
	assert_signal_emit_count(director, &"spawns_failed", 1)
	assert_signal_not_emitted(director, &"spawns_finished")
	assert_false(director.is_physics_processing())
	assert_false(director.start(5))
	assert_signal_emit_count(director, &"spawns_failed", 1)

func test_phase_one_agenda_has_contract_counts_and_event_cadences() -> void:
	var director := _director()
	var waves := ROOM_DEF.new().get_phase_one_waves()
	var agenda: Array[Dictionary] = director._build_wave_agenda(waves)
	var events: Array[Dictionary] = director._build_wave_events(agenda)

	assert_eq(agenda.size(), 78)
	for wave_index in waves.size():
		var entries := agenda.filter(func(entry: Dictionary) -> bool: return entry.wave_index == wave_index)
		var wave_events := events.filter(func(event: Dictionary) -> bool: return event.wave_index == wave_index)
		var wave := waves[wave_index]
		assert_eq(entries.size(), wave.common_count + wave.hunter_count)
		assert_true(entries.all(func(entry: Dictionary) -> bool: return entry.max_active == wave.max_active))
		for event in wave_events:
			assert_eq(event.cadence, wave.cadence)
	assert_eq(events[0].members.size(), 2)
	assert_eq(events.filter(func(event: Dictionary) -> bool: return event.wave_index == 2).size(), 2)

func test_wave_one_is_three_mirrored_pairs_with_member_and_pair_delays() -> void:
	var director := _director()
	director.set_room_bounds(Rect2(Vector2.ZERO, Vector2(720, 405)))
	var agenda: Array[Dictionary] = director._build_wave_agenda(ROOM_DEF.new().get_phase_one_waves())

	for pair_index in 3:
		var first: Dictionary = agenda[pair_index * 2]
		var second: Dictionary = agenda[pair_index * 2 + 1]
		assert_false(first.hunter)
		assert_false(second.hunter)
		assert_eq(second.edge, director._opposite_edge(first.edge))
		assert_eq(second.point, director._mirror_point(first.point))
		assert_eq(first.member_delay, 0.0)
		assert_eq(second.member_delay, 0.35)
		assert_eq(first.cadence, 2.4)

func test_mixed_waves_interleave_types_and_keep_hunter_pairs_separated() -> void:
	var director := _director()
	director.set_room_bounds(Rect2(Vector2.ZERO, Vector2(720, 405)))
	var agenda: Array[Dictionary] = director._build_wave_agenda(ROOM_DEF.new().get_phase_one_waves())
	for wave_index in [1, 2, 3, 4]:
		var entries := agenda.filter(func(entry: Dictionary) -> bool: return entry.wave_index == wave_index)
		assert_true(entries.any(func(entry: Dictionary) -> bool: return entry.hunter) == (wave_index >= 2))
		if wave_index >= 2:
			var hunters := entries.filter(func(entry: Dictionary) -> bool: return entry.hunter)
			for hunter_index in range(0, hunters.size(), 2):
				if hunter_index + 1 < hunters.size():
					assert_gte(hunters[hunter_index].point.distance_to(hunters[hunter_index + 1].point), 240.0)

func test_same_run_seed_produces_the_same_agenda() -> void:
	var waves := ROOM_DEF.new().get_phase_one_waves()
	RunManager.start_run(7744)
	var first_director := _director()
	first_director.set_room_bounds(Rect2(Vector2.ZERO, Vector2(720, 405)))
	var first: Array[Dictionary] = first_director.build_spawn_agenda(waves)
	RunManager.start_run(7744)
	var second_director := _director()
	second_director.set_room_bounds(Rect2(Vector2.ZERO, Vector2(720, 405)))
	var second: Array[Dictionary] = second_director.build_spawn_agenda(waves)
	assert_eq(first, second)

func test_start_waves_emits_wave_warning_spawn_and_finish_in_order() -> void:
	var fixture := await _director_with_container()
	var director: Node = fixture.director
	var waves: Array[RoomDef.WaveSpec] = [ROOM_DEF.WaveSpec.new(2, 0, 2, 0.25, true)]
	var order: Array[String] = []
	director.wave_started.connect(func(_index: int) -> void: order.append("wave"))
	director.spawn_warning_started.connect(func(_wave: int, _spawn: int) -> void: order.append("warning"))
	director.enemy_spawned.connect(func(_enemy: Enemy) -> void: order.append("spawn"))
	director.spawns_finished.connect(func() -> void: order.append("finished"))
	assert_true(director.start_waves(waves))
	for _i in 30:
		director._physics_process(0.25)
		for enemy in fixture.container.get_children():
			if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
				enemy.resolved.emit(enemy, 0)
		if order.has("finished"):
			break
	assert_eq(order[0], "wave")
	assert_eq(order[1], "warning")
	assert_true(order.find("spawn") > order.find("warning"))
	assert_eq(order.back(), "finished")

func test_wave_cadence_is_measured_between_warning_starts_without_adding_fx_window() -> void:
	var fixture := await _director_with_container()
	var director: Node = fixture.director
	var waves: Array[RoomDef.WaveSpec] = [ROOM_DEF.WaveSpec.new(0, 2, 2, 0.25, false)]
	# Lambdas capturam escalares pelo valor em GDScript; o array mantem um
	# relogio mutavel compartilhado com os callbacks dos sinais.
	var elapsed: Array[float] = [0.0]
	var warning_times: Array[float] = []
	var spawn_times: Array[float] = []
	director.spawn_warning_started.connect(func(_wave: int, _spawn: int) -> void: warning_times.append(elapsed[0]))
	director.enemy_spawned.connect(func(_enemy: Enemy) -> void: spawn_times.append(elapsed[0]))
	assert_true(director.start_waves(waves))

	elapsed[0] += 0.01; director._physics_process(0.01)
	elapsed[0] += 0.24; director._physics_process(0.24)
	assert_eq(warning_times.size(), 1)
	elapsed[0] += 0.01; director._physics_process(0.01)
	assert_eq(warning_times.size(), 2)
	assert_almost_eq(warning_times[1] - warning_times[0], 0.25, 0.001)
	assert_eq(spawn_times.size(), 0)
	elapsed[0] += 0.19; director._physics_process(0.19)
	assert_eq(spawn_times.size(), 0)
	elapsed[0] += 0.01; director._physics_process(0.01)
	assert_eq(spawn_times.size(), 1)
	assert_almost_eq(spawn_times[0] - warning_times[0], 0.45, 0.001)
	for enemy in fixture.container.get_children():
		if is_instance_valid(enemy):
			(enemy as Enemy).resolved.emit(enemy, 0)
	director.stop()

func test_max_active_blocks_agenda_until_enemy_resolves_then_resumes() -> void:
	var fixture := await _director_with_container()
	var director: Node = fixture.director
	var waves: Array[RoomDef.WaveSpec] = [ROOM_DEF.WaveSpec.new(2, 0, 1, 0.1, false)]
	assert_true(director.start_waves(waves))
	director._physics_process(0.01)
	director._physics_process(0.45)
	assert_eq(fixture.container.get_child_count(), 1)
	var blocked: Dictionary = director.get_wave_execution_state()
	director._physics_process(1.0)
	assert_eq(director.get_wave_execution_state().event_cursor, blocked.event_cursor)
	(fixture.container.get_child(0) as Enemy).resolved.emit(fixture.container.get_child(0), 0)
	director._physics_process(0.01)
	director._physics_process(0.45)
	assert_eq(fixture.container.get_child_count(), 2)

func test_wave_breather_requires_three_seconds_after_clear() -> void:
	var fixture := await _director_with_container()
	var director: Node = fixture.director
	var waves: Array[RoomDef.WaveSpec] = [ROOM_DEF.WaveSpec.new(1, 0, 1, 0.1), ROOM_DEF.WaveSpec.new(1, 0, 1, 0.1)]
	director.start_waves(waves)
	director._physics_process(0.01)
	director._physics_process(0.45)
	var first: Enemy = fixture.container.get_child(0) as Enemy
	first.resolved.emit(first, 0)
	director._physics_process(0.01)
	var before: Dictionary = director.get_wave_execution_state()
	assert_true(before.waiting_for_wave_clear)
	assert_eq(before.wave_index, 0)
	director._physics_process(2.98)
	assert_eq(director.get_wave_execution_state().wave_index, 0)
	director._physics_process(0.02)
	assert_eq(director.get_wave_execution_state().wave_index, -1)
	director._physics_process(0.01)
	assert_eq(director.get_wave_execution_state().wave_index, 1)

func test_public_agenda_composition_is_six_eighteen_two_twenty_two_thirty() -> void:
	var director := _director()
	var waves: Array[RoomDef.WaveSpec] = ROOM_DEF.new().get_phase_one_waves()
	var agenda: Array[Dictionary] = director.build_spawn_agenda(waves)
	var counts: Array[int] = []
	for index in waves.size():
		counts.append(agenda.filter(func(entry: Dictionary) -> bool: return entry.wave_index == index).size())
	assert_eq(counts, [6, 18, 2, 22, 30])

func test_different_run_seed_can_change_public_agenda() -> void:
	var waves := ROOM_DEF.new().get_phase_one_waves()
	RunManager.start_run(1)
	var first: Array[Dictionary] = _director().build_spawn_agenda(waves)
	RunManager.start_run(2)
	var second: Array[Dictionary] = _director().build_spawn_agenda(waves)
	assert_ne(first, second)
