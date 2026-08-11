extends GutTest

const SCENE := preload("res://scenes/enemies/atirador_de_fresta.tscn")
const SCRIPT := preload("res://scripts/enemies/atirador_de_fresta.gd")

func _enemy() -> Node:
	var enemy := SCENE.instantiate()
	add_child_autofree(enemy)
	await get_tree().process_frame
	return enemy

func _damage(amount: float) -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = amount
	return info

func test_scene_has_approved_assets_and_frames() -> void:
	var enemy := await _enemy()
	assert_eq(enemy.sprite.texture.resource_path, "res://assets/sprites/atirador-de-fresta-spritesheet.png")
	assert_eq(enemy.sprite.texture.get_width(), 192)
	assert_eq(enemy.sprite.texture.get_height(), 32)
	assert_eq(enemy.sprite.hframes, 6)
	assert_eq(enemy.fire_fx.texture.resource_path, "res://assets/sprites/atirador-de-fresta-fx-spritesheet.png")
	assert_eq(enemy.fire_fx.texture.get_width(), 512)
	assert_eq(enemy.fire_fx.texture.get_height(), 64)
	assert_eq(enemy.fire_fx.hframes, 8)
	assert_eq(enemy.health.max_health, 12.0)

func test_telegraph_duration_is_point_seven_and_is_visible_before_fire() -> void:
	var enemy := await _enemy()
	enemy.locked_direction = Vector2.RIGHT
	enemy._enter_state(SCRIPT.AttackState.TELEGRAPH)
	assert_eq(enemy.telegraph_duration, 0.7)
	assert_true(enemy.telegraph.visible)
	enemy._physics_process(0.69)
	assert_eq(enemy.attack_state, SCRIPT.AttackState.TELEGRAPH)
	enemy._physics_process(0.01)
	assert_eq(enemy.attack_state, SCRIPT.AttackState.FIRE)

func test_vulnerability_multiplies_damage_only_after_fire_and_preserves_original() -> void:
	var enemy := await _enemy()
	var original := _damage(2.0)
	enemy._enter_state(SCRIPT.AttackState.TELEGRAPH)
	assert_almost_eq(enemy.take_damage(original), 2.0, 0.001)
	assert_almost_eq(enemy.health.health, 10.0, 0.001)
	enemy._enter_state(SCRIPT.AttackState.VULNERABLE)
	var vulnerable := _damage(2.0)
	assert_almost_eq(enemy.take_damage(vulnerable), 2.0, 0.001)
	assert_almost_eq(enemy.health.health, 4.0, 0.001)
	assert_almost_eq(original.amount, 2.0, 0.001)
	assert_almost_eq(vulnerable.amount, 2.0, 0.001)

func test_vulnerability_returns_normalized_consumption_and_emits_actual_drop() -> void:
	var enemy := await _enemy()
	enemy._enter_state(SCRIPT.AttackState.VULNERABLE)
	watch_signals(enemy.health)

	var info := _damage(2.0)
	assert_almost_eq(enemy.take_damage(info), 2.0, 0.001)
	assert_almost_eq(enemy.health.health, 6.0, 0.001)
	assert_signal_emit_count(enemy.health, &"damaged", 1)

func test_fire_state_is_the_transition_that_opens_vulnerability() -> void:
	var enemy := await _enemy()
	enemy._enter_state(SCRIPT.AttackState.FIRE)
	assert_eq(enemy.attack_state, SCRIPT.AttackState.FIRE)
	var before_fire := _damage(1.0)
	enemy.take_damage(before_fire)
	assert_almost_eq(enemy.health.health, 11.0, 0.001)
	enemy._physics_process(0.0)
	assert_eq(enemy.attack_state, SCRIPT.AttackState.VULNERABLE)
	var after_fire := _damage(1.0)
	enemy.take_damage(after_fire)
	assert_almost_eq(enemy.health.health, 8.0, 0.001)

func test_vulnerability_keeps_enemy_trigger_depth_protection() -> void:
	var enemy := await _enemy()
	enemy._enter_state(SCRIPT.AttackState.VULNERABLE)
	var chained := _damage(2.0)
	chained.trigger_depth = 4
	assert_almost_eq(enemy.take_damage(chained), 0.0, 0.001)
	assert_almost_eq(enemy.health.health, 12.0, 0.001)

func test_locked_direction_remains_the_projectile_direction() -> void:
	var enemy := await _enemy()
	var player := Node2D.new()
	add_child_autofree(player)
	enemy._player = player
	enemy.global_position = Vector2.ZERO
	player.global_position = Vector2.RIGHT * 230.0
	enemy._lock_target()
	var captured: Vector2 = enemy.locked_direction
	player.global_position = Vector2.LEFT * 100.0
	assert_eq(enemy.locked_direction, captured)
	enemy._fire_projectile()
	var projectile := enemy.get_parent().get_child(enemy.get_parent().get_child_count() - 1) as EnemyProjectile
	assert_eq(projectile._velocity.normalized(), captured)
	projectile.queue_free()

func test_instance_draws_entry_values_once_from_run_rng() -> void:
	var original_state := RunManager.rng.get_state()
	var expected_rng := RunRng.new(RunManager.seed_value)
	expected_rng.set_state(original_state)
	var expected_activation := expected_rng.randf_range(100.0, 200.0)
	var expected_speed := expected_rng.randf_range(90.0, 140.0)
	var expected_time := expected_rng.randf_range(1.2, 1.8)

	var enemy := await _enemy()
	assert_almost_eq(enemy._activation_distance, expected_activation, 0.001)
	assert_almost_eq(enemy._entry_speed, expected_speed, 0.001)
	assert_almost_eq(enemy._max_drift_time, expected_time, 0.001)
	assert_between(enemy._activation_distance, 100.0, 200.0)
	assert_between(enemy._entry_speed, 90.0, 140.0)
	assert_between(enemy._max_drift_time, 1.2, 1.8)
	assert_eq(RunManager.rng.get_state(), expected_rng.get_state())

	enemy._physics_process(0.1)
	assert_eq(RunManager.rng.get_state(), expected_rng.get_state())
	for state in [SCRIPT.AttackState.TELEGRAPH, SCRIPT.AttackState.FIRE, SCRIPT.AttackState.VULNERABLE, SCRIPT.AttackState.IDLE, SCRIPT.AttackState.DRIFT]:
		enemy._enter_state(state)
		enemy._physics_process(0.1)
	assert_eq(RunManager.rng.get_state(), expected_rng.get_state())

func test_drift_moves_straight_from_each_edge() -> void:
	var enemy := await _enemy()
	var player := Node2D.new()
	add_child_autofree(player)
	enemy._player = player
	player.global_position = Vector2(100.0, 100.0)
	enemy.set_room_bounds(Rect2(Vector2.ZERO, Vector2(200.0, 200.0)))
	var edge_cases := [
		[Vector2(-16.0, 100.0), Vector2.RIGHT],
		[Vector2(216.0, 100.0), Vector2.LEFT],
		[Vector2(100.0, -16.0), Vector2.DOWN],
		[Vector2(100.0, 216.0), Vector2.UP],
	]
	for edge_case in edge_cases:
		enemy.global_position = edge_case[0]
		enemy.set_entry_inward(edge_case[1])
		enemy._has_entered_room = false
		enemy._process_drift()
		assert_eq(enemy.velocity, edge_case[1] * enemy._entry_speed)
		enemy.global_position += enemy.velocity * 0.25
		assert_eq(enemy.global_position, edge_case[0] + edge_case[1] * enemy._entry_speed * 0.25)

func test_drift_ignores_player_position_after_entering_room() -> void:
	var enemy := await _enemy()
	var player := Node2D.new()
	add_child_autofree(player)
	enemy._player = player
	enemy.global_position = Vector2(40.0, 100.0)
	player.global_position = Vector2(100.0, 100.0)
	enemy.set_entry_inward(Vector2.RIGHT)
	enemy._has_entered_room = true
	enemy._process_drift()
	assert_eq(enemy.velocity, Vector2.RIGHT * enemy._entry_speed)

	player.global_position = Vector2(-100.0, 0.0)
	enemy._process_drift()
	assert_eq(enemy.velocity, Vector2.RIGHT * enemy._entry_speed)

func test_drift_distance_promotes_to_telegraph_and_locks_target() -> void:
	var enemy := await _enemy()
	var player := Node2D.new()
	add_child_autofree(player)
	enemy._player = player
	enemy.global_position = Vector2.ZERO
	enemy._entry_start_position = Vector2.ZERO
	enemy._activation_distance = 120.0
	enemy._entry_speed = 130.0
	enemy._max_drift_time = 1.8
	enemy.set_entry_inward(Vector2.RIGHT)
	enemy._has_entered_room = true
	player.global_position = Vector2.RIGHT * 230.0
	enemy._process_drift()
	enemy.global_position += enemy.velocity * 1.0
	assert_eq(enemy.attack_state, SCRIPT.AttackState.DRIFT)
	assert_eq(enemy.global_position, Vector2.RIGHT * 130.0)
	enemy._physics_process(0.0)

	assert_eq(enemy.attack_state, SCRIPT.AttackState.TELEGRAPH)
	assert_eq(enemy.velocity, Vector2.ZERO)
	assert_almost_eq(enemy.locked_direction.x, 1.0, 0.001)
	assert_almost_eq(enemy.locked_direction.y, 0.0, 0.001)

func test_drift_time_promotes_to_telegraph_before_distance() -> void:
	var enemy := await _enemy()
	enemy.global_position = Vector2.ZERO
	enemy._entry_start_position = Vector2.ZERO
	enemy._activation_distance = 190.0
	enemy._entry_speed = 90.0
	enemy._max_drift_time = 1.2
	enemy.set_entry_inward(Vector2.RIGHT)
	enemy._has_entered_room = true
	enemy._process_drift()
	enemy.global_position += enemy.velocity * 1.2
	enemy._elapsed = 1.2
	assert_eq(enemy.attack_state, SCRIPT.AttackState.DRIFT)
	assert_almost_eq(enemy.global_position.x, 108.0, 0.001)
	assert_almost_eq(enemy.global_position.y, 0.0, 0.001)
	enemy._physics_process(0.0)

	assert_eq(enemy.attack_state, SCRIPT.AttackState.TELEGRAPH)
	assert_eq(enemy.velocity, Vector2.ZERO)

func test_culling_keeps_forty_pixel_room_margin_after_entry() -> void:
	var enemy := await _enemy()
	enemy.set_room_bounds(Rect2(0.0, 0.0, 320.0, 320.0))
	enemy.set_room_cull_policy(RoomDef.CullPolicy.DESPAWN_ALL_BORDERS)
	enemy._has_entered_room = true
	enemy.global_position = Vector2(-40.0, 160.0)
	assert_false(enemy._should_cull())

	enemy.global_position = Vector2(-41.0, 160.0)
	assert_true(enemy._should_cull())

func test_drift_marks_entry_only_after_crossing_room_boundary() -> void:
	var enemy := await _enemy()
	enemy.set_room_bounds(Rect2(0.0, 0.0, 320.0, 320.0))
	enemy.set_entry_inward(Vector2.RIGHT)
	enemy.global_position = Vector2(-10.0, 160.0)
	enemy._has_entered_room = false

	enemy._physics_process(0.016)
	assert_false(enemy._has_entered_room)
	assert_gt(enemy.velocity.dot(Vector2.RIGHT), 0.0)

	enemy.global_position = Vector2(5.0, 160.0)
	enemy._physics_process(0.016)
	assert_true(enemy._has_entered_room)
	assert_true(enemy._entry_start_position.x >= 0.0)
	assert_eq(enemy._entry_start_position.y, enemy.global_position.y)
	assert_lt(enemy._elapsed, 0.02)

func test_normal_spawn_waits_for_post_entry_distance_before_telegraph() -> void:
	var enemy := await _enemy()
	enemy.set_room_bounds(Rect2(0.0, 0.0, 320.0, 320.0))
	enemy.set_entry_inward(Vector2.RIGHT)
	enemy.global_position = Vector2(-16.0, 160.0)
	enemy._entry_speed = 100.0
	enemy._activation_distance = 100.0
	enemy._max_drift_time = 1.2
	enemy._has_entered_room = false

	while not enemy._has_entered_room:
		enemy._physics_process(0.016)
	assert_true(enemy._has_entered_room)
	assert_eq(enemy.attack_state, SCRIPT.AttackState.DRIFT)
	assert_lt(enemy._elapsed, 0.02)
	assert_true(enemy._entry_start_position.x >= 0.0)

	enemy._physics_process(0.0)
	assert_eq(enemy.attack_state, SCRIPT.AttackState.DRIFT)
	while enemy.attack_state == SCRIPT.AttackState.DRIFT:
		enemy._physics_process(0.016)
	assert_eq(enemy.attack_state, SCRIPT.AttackState.TELEGRAPH)

func test_far_external_spawn_resets_activation_clock_and_origin_on_entry() -> void:
	var enemy := await _enemy()
	enemy.set_room_bounds(Rect2(0.0, 0.0, 320.0, 320.0))
	enemy.set_entry_inward(Vector2.RIGHT)
	enemy.global_position = Vector2(-500.0, 160.0)
	enemy._entry_speed = 100.0
	enemy._activation_distance = 100.0
	enemy._max_drift_time = 1.2
	enemy._has_entered_room = false

	var pre_entry_elapsed := 0.0
	var pre_entry_distance := 0.0
	while not enemy._has_entered_room:
		pre_entry_elapsed = enemy._elapsed
		pre_entry_distance = enemy.global_position.distance_to(enemy._entry_start_position)
		enemy._physics_process(0.016)
	assert_gt(pre_entry_elapsed, enemy._max_drift_time)
	assert_gt(pre_entry_distance, enemy._activation_distance)
	assert_true(enemy._has_entered_room)
	assert_eq(enemy.attack_state, SCRIPT.AttackState.DRIFT)
	assert_lt(enemy._elapsed, 0.02)
	assert_true(enemy._entry_start_position.x >= 0.0)

	# The first frame in the room begins the new measurement; it cannot telegraph.
	enemy._physics_process(0.0)
	assert_eq(enemy.attack_state, SCRIPT.AttackState.DRIFT)
	while enemy.attack_state == SCRIPT.AttackState.DRIFT:
		enemy._physics_process(0.016)
	assert_eq(enemy.attack_state, SCRIPT.AttackState.TELEGRAPH)

func test_legacy_anchor_and_engagement_distance_contracts_are_absent() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/enemies/atirador_de_fresta.gd")
	assert_false(source.contains("_find_anchor"))
	assert_false(source.contains("_anchor"))
	assert_false(source.contains("engagement_distance"))

func test_vulnerable_duration_is_point_seven() -> void:
	var enemy := await _enemy()
	enemy._enter_state(SCRIPT.AttackState.VULNERABLE)
	enemy._physics_process(0.69)
	assert_eq(enemy.attack_state, SCRIPT.AttackState.VULNERABLE)
	enemy._physics_process(0.01)
	assert_eq(enemy.attack_state, SCRIPT.AttackState.IDLE)

func test_idle_duration_is_one_second() -> void:
	var enemy := await _enemy()
	enemy._enter_state(SCRIPT.AttackState.IDLE)
	enemy._physics_process(0.99)
	assert_eq(enemy.attack_state, SCRIPT.AttackState.IDLE)

	enemy._enter_state(SCRIPT.AttackState.IDLE)
	enemy._physics_process(1.0)
	assert_eq(enemy.attack_state, SCRIPT.AttackState.DRIFT)

func test_idle_stops_movement_hides_effects_and_takes_normal_damage() -> void:
	var enemy := await _enemy()
	enemy._enter_state(SCRIPT.AttackState.IDLE)
	enemy._physics_process(0.0)
	assert_eq(enemy.velocity, Vector2.ZERO)
	assert_false(enemy.telegraph.visible)
	assert_false(enemy.fire_fx.visible)
	var damage := _damage(2.0)
	assert_almost_eq(enemy.take_damage(damage), 2.0, 0.001)
	assert_almost_eq(enemy.health.health, 10.0, 0.001)

func test_vulnerable_return_matches_effective_loss_after_chained_damage() -> void:
	var enemy := await _enemy()
	enemy._enter_state(SCRIPT.AttackState.VULNERABLE)
	var damage := _damage(5.0)
	assert_almost_eq(enemy.take_damage(damage), 4.0, 0.001)
	assert_almost_eq(enemy.health.health, 0.0, 0.001)
