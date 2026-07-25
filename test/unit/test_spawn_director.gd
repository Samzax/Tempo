extends GutTest

const SPAWN_DIRECTOR := preload("res://scripts/directors/spawn_director.gd")

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
	for _frame in 3:
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
	for _frame in 5:
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
