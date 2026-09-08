extends GutTest

const PROGRESS := preload("res://scripts/backgrounds/n0_n1_v27_progress.gd")
const RUNTIME := preload("res://scripts/rooms/room_runtime.gd")
const GENERATOR := preload("res://scripts/run/sector_generator.gd")
const N0_PRESENTATION := preload("res://scripts/rooms/n0_opening_transition_presentation.gd")
const N1_PRESENTATION := preload("res://scripts/rooms/n1_opening_continuation_presentation.gd")
const CHEST := preload("res://scripts/loot/reward_chest.gd")
const MAIN_SCENE := preload("res://scenes/main/main.tscn")

func _enemy() -> Node:
	var node := Node.new()
	autofree(node)
	return node

func test_real_spawn_resolution_is_deduplicated_and_progress_is_capped() -> void:
	var runtime := RUNTIME.new()
	var enemy := _enemy()
	runtime.configure_expected_spawn_count(2)
	runtime.start()
	runtime.register_spawn(enemy)
	runtime.register_spawn(enemy)
	runtime.mark_spawns_finished()
	runtime.resolve_enemy(enemy, 0)
	runtime.resolve_enemy(enemy, 0)
	var snapshot := runtime.progress_snapshot()
	assert_eq(snapshot.spawned_count, 1)
	assert_eq(snapshot.resolved_count, 1)
	assert_eq(snapshot.active_enemy_count, 0)
	assert_false(snapshot.combat_cleared)

func test_final_clear_publishes_one_terminal_progress_snapshot() -> void:
	var runtime := RUNTIME.new()
	var enemy := _enemy()
	watch_signals(runtime)
	runtime.configure_expected_spawn_count(1)
	runtime.start()
	runtime.register_spawn(enemy)
	runtime.mark_spawns_finished()
	runtime.resolve_enemy(enemy, 0)
	runtime.resolve_enemy(enemy, 0)
	assert_signal_emit_count(runtime, &"room_cleared", 1)
	assert_signal_emit_count(runtime, &"progress_changed", 6)
	var final_snapshot: Dictionary = get_signal_parameters(runtime, &"progress_changed", 5)[0]
	assert_true(final_snapshot.combat_cleared)
	assert_eq(final_snapshot.expected_spawn_count, 1)
	assert_eq(final_snapshot.resolved_count, 1)

func test_progress_is_monotone_and_never_reveals_frame_719_before_clear() -> void:
	var model := PROGRESS.new()
	var snapshot := {"expected_spawn_count": 78, "resolved_count": 77, "combat_cleared": false}
	var first := model.update_from_snapshot(snapshot, 1.0)
	var second := model.update_from_snapshot(snapshot, 1.0)
	assert_true(second >= first)
	assert_lt(second, 92.9)
	assert_lte(int(floor(second / 92.9 * 718.0)), 718)

func test_clear_catchup_is_continuous_before_tail_boundary() -> void:
	var model := PROGRESS.new()
	model.presentation_progress = 40.0
	var value := model.update_from_snapshot({"expected_spawn_count": 78, "resolved_count": 78, "combat_cleared": true}, 1.0 / 30.0)
	assert_gt(value, 40.0)
	assert_lt(value, 92.9)

func test_pause_freezes_n0_and_n1_presentation_processes() -> void:
	var n0 := N0_PRESENTATION.new()
	var n1 := N1_PRESENTATION.new()
	add_child_autofree(n0)
	add_child_autofree(n1)
	await get_tree().process_frame
	get_tree().paused = true
	var n0_frame := n0.player.current_frame if n0.player != null else -1
	var n1_frame := n1.player.current_frame if n1.player != null else -1
	await get_tree().process_frame
	get_tree().paused = false
	assert_eq(n0.player.current_frame, n0_frame)
	assert_eq(n1.player.current_frame, n1_frame)

func test_generator_declares_exact_node0_to_node1_transition_and_n3_regression() -> void:
	var sector := GENERATOR.generate(1, 0)
	assert_eq(sector.get_node(0).transition_profile, &"n0_opening_transition")
	assert_eq(sector.get_children(0), [1])
	assert_eq(sector.get_node(3).transition_profile, &"sector3_upper_transition")
	assert_ne(sector.get_node(3).transition_profile, &"n0_opening_transition")

func test_n0_transition_chest_is_managed_but_default_chest_is_not() -> void:
	var transition_chest := CHEST.new()
	var default_chest := CHEST.new()
	autofree(transition_chest)
	autofree(default_chest)
	transition_chest.configure_transition_managed()
	assert_true(transition_chest._transition_managed)
	assert_false(default_chest._transition_managed)

func test_n1_continuation_starts_at_809_and_is_distinct_from_n3_presentation() -> void:
	var continuation := N1_PRESENTATION.new()
	add_child_autofree(continuation)
	await get_tree().process_frame
	assert_eq(continuation._frame, 809)
	assert_null(continuation.get_node_or_null("Sector3CorePresentation"))

func test_proof_viewport_is_true_1280x720_and_player_keeps_bounded_residency_contract() -> void:
	var main := MAIN_SCENE.instantiate()
	add_child_autofree(main)
	await get_tree().process_frame
	var session := main.get_node("Session") as Session
	session.start_new_run(12345)
	await get_tree().process_frame
	assert_eq(get_viewport().size, Vector2i(1280, 720))
	var player_script := load("res://scripts/backgrounds/n0_n1_v27_player.gd")
	assert_eq(player_script.FRAME_COUNT, 989)
	assert_eq(player_script.MAX_NATIVE_FRAME_CACHE, 4)
