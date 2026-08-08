extends GutTest

const HUNTER_SCENE := preload("res://scenes/enemies/hunter.tscn")
const HUNTER_SCRIPT := preload("res://scripts/enemies/hunter.gd")
const SPAWN_DIRECTOR := preload("res://scripts/directors/spawn_director.gd")

func _hunter() -> Node:
	var hunter: Node = HUNTER_SCENE.instantiate()
	add_child_autofree(hunter)
	await get_tree().process_frame
	return hunter

func _damage(amount: float) -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = amount
	return info

func _session_for_run_paths() -> Session:
	var session := Session.new()
	var player := preload("res://scenes/player/player.tscn").instantiate()
	player.name = "Player"
	var camera := Camera2D.new()
	camera.name = "Camera"
	var room_host := Node.new()
	room_host.name = "RoomHost"
	var hyperspace := HyperspaceUI.new()
	hyperspace.name = "HyperspaceUI"
	session.add_child(player)
	session.add_child(camera)
	session.add_child(room_host)
	session.add_child(hyperspace)
	session.player_path = NodePath("Player")
	session.camera_path = NodePath("Camera")
	session.room_host_path = NodePath("RoomHost")
	session.hyperspace_path = NodePath("HyperspaceUI")
	add_child_autofree(session)
	await get_tree().process_frame
	return session

func test_hunter_cycles_through_attack_states_using_exported_durations() -> void:
	var hunter := await _hunter()
	hunter.telegraph_duration = 0.05
	hunter.dash_duration = 0.05
	hunter.recover_duration = 0.05
	hunter.enter_attack_state(HUNTER_SCRIPT.AttackState.TELEGRAPH)
	assert_eq(hunter.attack_state, HUNTER_SCRIPT.AttackState.TELEGRAPH)
	hunter._physics_process(0.06)
	assert_eq(hunter.attack_state, HUNTER_SCRIPT.AttackState.DASH)
	hunter._physics_process(0.06)
	assert_eq(hunter.attack_state, HUNTER_SCRIPT.AttackState.RECOVER)
	hunter._physics_process(0.06)
	assert_eq(hunter.attack_state, HUNTER_SCRIPT.AttackState.CHASE)

func test_telegraph_pulses_and_dash_keeps_captured_direction() -> void:
	var hunter := await _hunter()
	var player := Node2D.new()
	add_child_autofree(player)
	hunter._player = player
	hunter.global_position = Vector2.ZERO
	player.global_position = Vector2.RIGHT * 100.0
	hunter.enter_attack_state(HUNTER_SCRIPT.AttackState.TELEGRAPH)
	assert_eq(hunter.sprite.modulate, hunter.tint.lightened(0.35))
	assert_true(is_instance_valid(hunter._telegraph_tween))
	hunter._physics_process(hunter.telegraph_duration + 0.01)
	assert_eq(hunter.attack_state, HUNTER_SCRIPT.AttackState.DASH)
	var captured: Vector2 = hunter.dash_direction
	player.global_position = Vector2.LEFT * 100.0
	hunter._physics_process(0.01)
	assert_eq(hunter.dash_direction, captured)
	assert_eq(hunter.velocity.normalized(), captured.normalized())

func test_dash_tick_boundary_moves_at_dash_speed_before_recovering() -> void:
	var hunter := await _hunter()
	hunter.dash_duration = 0.1
	hunter.dash_speed = 240.0
	hunter.dash_direction = Vector2.RIGHT
	hunter.global_position = Vector2.ZERO
	hunter.enter_attack_state(HUNTER_SCRIPT.AttackState.DASH)
	hunter._physics_process(0.06)
	var before_final_tick: Vector2 = hunter.global_position
	hunter._physics_process(0.06)
	var displacement: Vector2 = hunter.global_position - before_final_tick
	assert_gt(displacement.x, 0.0)
	assert_lte(displacement.x, hunter.dash_speed * 0.04)
	assert_almost_eq(displacement.y, 0.0, 0.01)
	assert_eq(hunter.attack_state, HUNTER_SCRIPT.AttackState.RECOVER)

func test_death_during_telegraph_cancels_pulse_and_prevents_motion() -> void:
	var hunter := await _hunter()
	hunter.enter_attack_state(HUNTER_SCRIPT.AttackState.TELEGRAPH)
	hunter._on_died(_damage(999.0))
	assert_true(hunter._dead)
	assert_null(hunter._telegraph_tween)
	assert_eq(hunter.velocity, Vector2.ZERO)
	hunter._physics_process(10.0)
	assert_eq(hunter.velocity, Vector2.ZERO)

func test_death_during_dash_cancels_cycle_and_prevents_motion() -> void:
	var hunter := await _hunter()
	hunter.dash_direction = Vector2.RIGHT
	hunter.enter_attack_state(HUNTER_SCRIPT.AttackState.DASH)
	hunter._on_died(_damage(999.0))
	assert_true(hunter._dead)
	assert_eq(hunter.velocity, Vector2.ZERO)

func test_health_component_damage_causes_real_death_and_cancels_attack() -> void:
	var hunter := await _hunter()
	hunter.enter_attack_state(HUNTER_SCRIPT.AttackState.TELEGRAPH)
	assert_true(is_instance_valid(hunter.health))
	hunter.take_damage(_damage(hunter.health.max_health))
	assert_true(hunter._dead)
	assert_eq(hunter.attack_state, HUNTER_SCRIPT.AttackState.TELEGRAPH)
	assert_null(hunter._telegraph_tween)
	assert_eq(hunter.velocity, Vector2.ZERO)
	hunter._physics_process(10.0)
	assert_eq(hunter.velocity, Vector2.ZERO)

func test_hunter_death_grants_one_echo_directly_without_pickup() -> void:
	var hunter := await _hunter()
	GameState.reset_for_new_run()
	watch_signals(GameState)
	watch_signals(EventBus)
	hunter._on_died(_damage(999.0))
	assert_eq(GameState.temporal_echoes, 1)
	assert_signal_emitted_with_parameters(GameState, &"temporal_echoes_changed", [1, 1])
	assert_signal_emitted_with_parameters(EventBus, &"temporal_echoes_credited", [1, 1])
	assert_eq(hunter.get_tree().get_nodes_in_group(&"pickups").size(), 0)
	hunter._on_died(_damage(999.0))
	assert_eq(GameState.temporal_echoes, 1)
	assert_signal_emit_count(GameState, &"temporal_echoes_changed", 1)

func test_hunter_reward_is_configurable_and_defaults_to_one() -> void:
	var hunter := await _hunter()
	GameState.reset_for_new_run()
	assert_eq(hunter.temporal_echo_reward, 1)
	hunter.temporal_echo_reward = 3
	hunter.take_damage(_damage(hunter.health.max_health))
	assert_eq(GameState.temporal_echoes, 3)

func test_hunter_zero_reward_does_not_credit_echoes() -> void:
	var hunter := await _hunter()
	GameState.reset_for_new_run()
	hunter.temporal_echo_reward = 0
	hunter.take_damage(_damage(hunter.health.max_health))
	assert_eq(GameState.temporal_echoes, 0)

func test_zero_and_negative_echo_values_do_not_change_balance() -> void:
	GameState.reset_for_new_run()
	watch_signals(GameState)
	GameState.add_temporal_echoes(0)
	GameState.add_temporal_echoes(-4)
	assert_eq(GameState.temporal_echoes, 0)
	assert_signal_not_emitted(GameState, &"temporal_echoes_changed")

func test_reset_for_new_run_zeros_echoes_and_emits_correct_totals() -> void:
	GameState.temporal_echoes = 7
	watch_signals(GameState)
	GameState.reset_for_new_run()
	assert_eq(GameState.temporal_echoes, 0)
	assert_signal_emitted_with_parameters(GameState, &"temporal_echoes_changed", [0, 0])

func test_start_new_run_resets_echoes_but_preserves_internal_reentrancy_guard() -> void:
	var session := await _session_for_run_paths()
	GameState.temporal_echoes = 9
	session.start_new_run(1337)
	var first_sector := session.sector
	assert_eq(GameState.temporal_echoes, 0)
	assert_true(session._has_started)
	session.start_new_run(7331)
	assert_eq(session.sector, first_sector)
	assert_eq(session.run_state.run_seed, 1337)

func test_sandbox_warp_resets_echoes_without_resetting_transition_generation() -> void:
	var session := await _session_for_run_paths()
	session.start_new_run(1337)
	var target := session.sector.get_node(session.sector.start_node_id) as SectorNode
	var generation_before := session._room_generation
	GameState.temporal_echoes = 6
	assert_true(session.sandbox_warp(1337, 0, target.id, target.node_type))
	assert_eq(GameState.temporal_echoes, 0)
	assert_gt(session._room_generation, generation_before)
	assert_true(session._room_active)
	assert_false(session._awaiting_boss_advance)

func test_spawn_director_keeps_regular_enemies_and_selects_hunter_on_fifth() -> void:
	var root := Node.new()
	add_child_autofree(root)
	var container := Node.new()
	container.add_to_group(&"enemies_container")
	root.add_child(container)
	var director := SPAWN_DIRECTOR.new()
	root.add_child(director)
	director.interval = 0.0
	await get_tree().process_frame
	assert_true(director.start(8))
	for _i in 16:
		await get_tree().physics_frame
		if container.get_child_count() == 8:
			break
	var spawned := container.get_children()
	assert_eq(spawned.size(), 8)
	assert_true(spawned[0] is Enemy)
	assert_ne(spawned[0].get_script(), HUNTER_SCRIPT)
	assert_true(spawned[1] is Enemy)
	assert_ne(spawned[1].get_script(), HUNTER_SCRIPT)
	assert_true(spawned[3] is Enemy)
	assert_ne(spawned[3].get_script(), HUNTER_SCRIPT)
	assert_true(spawned[4].get_script() == HUNTER_SCRIPT)
	assert_true(spawned[5] is Enemy)
	assert_ne(spawned[5].get_script(), HUNTER_SCRIPT)
	assert_true(spawned[6] is Enemy)
	assert_ne(spawned[6].get_script(), HUNTER_SCRIPT)
	assert_true(spawned[7] is Enemy)
	assert_ne(spawned[7].get_script(), HUNTER_SCRIPT)
	assert_eq((spawned[0] as Enemy).movement, Enemy.Movement.CHASE)
	assert_eq((spawned[1] as Enemy).movement, Enemy.Movement.DESCEND)
	assert_eq((spawned[2] as Enemy).movement, Enemy.Movement.SINE)
	assert_eq((spawned[5] as Enemy).movement, Enemy.Movement.DESCEND)
	assert_eq((spawned[6] as Enemy).movement, Enemy.Movement.SINE)
	assert_eq((spawned[7] as Enemy).movement, Enemy.Movement.CHASE)
