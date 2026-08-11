extends GutTest

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const BRUTA := preload("res://resources/ships/bruta.tres")
const BRUTA_SPRITE_PATH := "res://assets/sprites/bruta-hull.png"
const INPUT_ACTIONS: Array[StringName] = [
	&"move_up",
	&"move_left",
	&"move_down",
	&"move_right",
	&"aim_up",
	&"aim_left",
	&"aim_down",
	&"aim_right",
	&"shoot",
	&"blink",
	&"ability_q",
	&"ability_e",
]


func _bruta_player() -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
	player.ship = BRUTA
	add_child_autofree(player)
	await get_tree().process_frame
	return player


func _release_inputs() -> void:
	for action in INPUT_ACTIONS:
		Input.action_release(action)


func _assert_vector_almost_eq(actual: Vector2, expected: Vector2, tolerance: float = 0.0001) -> void:
	assert_almost_eq(actual.x, expected.x, tolerance)
	assert_almost_eq(actual.y, expected.y, tolerance)


func before_each() -> void:
	_release_inputs()


func after_each() -> void:
	_release_inputs()


func test_ship_def_defaults_preserve_legacy_aim_forward_contract() -> void:
	var defaults := ShipDef.new()

	assert_eq(defaults.movement_style, "aim_forward")
	assert_eq(defaults.frame_size, Vector2i(16, 24))
	assert_eq(defaults.hurtbox_radius, 8.0)
	assert_eq(defaults.collision_shape_type, "capsule")
	assert_true(defaults.has_muzzle)


func test_bruta_declares_omni_32_pixel_circle_without_muzzle() -> void:
	assert_eq(BRUTA.id, &"nave_bruta")
	assert_eq(BRUTA.display_name, "Bruta")
	assert_eq(BRUTA.ability_q, &"sobrecarga")
	assert_eq(BRUTA.movement_style, "omni")
	assert_eq(BRUTA.frame_size, Vector2i(32, 32))
	assert_eq(BRUTA.hurtbox_radius, 10.0)
	assert_eq(BRUTA.collision_shape_type, "circle")
	assert_false(BRUTA.has_muzzle)
	assert_eq(BRUTA.ability_shift, &"bruta_investida")
	assert_false(BRUTA.can_blink)

func test_ship_def_accepts_empty_shift_and_rejects_unknown_shift_ability() -> void:
	var empty_shift := ShipDef.new()
	empty_shift.id = &"empty_shift"
	empty_shift.ability_shift = &""
	assert_eq(empty_shift.validate_content(), [])

	var unknown_shift := ShipDef.new()
	unknown_shift.id = &"unknown_shift"
	unknown_shift.ability_shift = &"nao_existe"
	assert_string_contains("\n".join(unknown_shift.validate_content()), "Habilidade de Shift da nave desconhecida")


func test_bruta_declares_only_its_useful_authored_base_stats() -> void:
	assert_eq(BRUTA.base_stats.size(), 4)
	var values_by_stat: Dictionary = {}
	for base_stat in BRUTA.base_stats:
		assert_not_null(base_stat)
		if base_stat != null:
			values_by_stat[base_stat.stat] = base_stat.value

	assert_eq(values_by_stat, {
		&"max_health": 5.0,
		&"max_speed": 125.0,
		&"acceleration": 850.0,
		&"damage": 1.5,
	})


func test_bruta_applies_a_10_pixel_circle_to_body_and_hurtbox() -> void:
	var player: Player = await _bruta_player()
	var body_shape := player.body_collision.shape as CircleShape2D
	var hurtbox_shape := player.hurtbox_collision.shape as CircleShape2D

	assert_not_null(body_shape)
	assert_not_null(hurtbox_shape)
	if body_shape != null:
		assert_almost_eq(body_shape.radius, 10.0, 0.0001)
	if hurtbox_shape != null:
		assert_almost_eq(hurtbox_shape.radius, 10.0, 0.0001)


func test_bruta_uses_standalone_32_by_32_rgba_texture() -> void:
	assert_not_null(BRUTA.hull_texture)
	if BRUTA.hull_texture == null:
		return
	assert_eq(BRUTA.hull_texture.resource_path, BRUTA_SPRITE_PATH)

	var image := Image.load_from_file(ProjectSettings.globalize_path(BRUTA_SPRITE_PATH))
	assert_not_null(image, "A textura standalone da Bruta deve carregar.")
	if image == null:
		return

	assert_eq(image.get_size(), Vector2i(32, 32))
	assert_eq(image.get_format(), Image.FORMAT_RGBA8)


func test_player_scene_has_visual_root_and_four_anchored_omni_thrusters() -> void:
	var player: Player = await _bruta_player()
	assert_not_null(player.visual_root)
	assert_eq(player.thrusters.size(), 4)

	var expected := {
		&"Thruster": [Vector2(0, 12), Vector2.DOWN],
		&"ThrusterTop": [Vector2(0, -12), Vector2.UP],
		&"ThrusterLeft": [Vector2(-12, 0), Vector2.LEFT],
		&"ThrusterRight": [Vector2(12, 0), Vector2.RIGHT],
	}
	for thruster_name in expected:
		var current := player.visual_root.get_node(NodePath(thruster_name)) as CPUParticles2D
		assert_not_null(current, "VisualRoot deve conter %s." % thruster_name)
		if current == null:
			continue
		assert_eq(current.get_parent(), player.visual_root)
		_assert_vector_almost_eq(current.position, expected[thruster_name][0])
		_assert_vector_almost_eq(current.direction, expected[thruster_name][1])

	var particle_children := 0
	for child in player.visual_root.get_children():
		if child is CPUParticles2D:
			particle_children += 1
	assert_eq(particle_children, 4, "VisualRoot deve ter exatamente os quatro thrusters omni.")


func test_bruta_root_stays_unrotated_when_aim_changes() -> void:
	var player: Player = await _bruta_player()
	player.rotation = 0.4
	Input.action_press(&"aim_right")
	player._update_aim()
	_assert_vector_almost_eq(player._aim_vector, Vector2.RIGHT)
	player._physics_process(0.0)
	_release_inputs()

	assert_almost_eq(player.rotation, 0.0, 0.0001)


func test_bruta_wasd_and_diagonals_produce_independent_omni_directions() -> void:
	var player: Player = await _bruta_player()
	var cases := [
		[[&"move_up"], Vector2.UP],
		[[&"move_left"], Vector2.LEFT],
		[[&"move_down"], Vector2.DOWN],
		[[&"move_right"], Vector2.RIGHT],
		[[&"move_up", &"move_left"], Vector2(-1, -1).normalized()],
		[[&"move_up", &"move_right"], Vector2(1, -1).normalized()],
		[[&"move_down", &"move_left"], Vector2(-1, 1).normalized()],
		[[&"move_down", &"move_right"], Vector2(1, 1).normalized()],
	]
	for test_case in cases:
		for action in test_case[0]:
			Input.action_press(action)
		var direction := player._omni_movement_direction()
		_assert_vector_almost_eq(direction, test_case[1])
		if test_case[0].size() == 2:
			assert_almost_eq(direction.length(), 1.0, 0.0001)
		_release_inputs()


func test_bruta_visual_settle_changes_only_visual_root() -> void:
	var player: Player = await _bruta_player()
	player.rotation = 0.37
	player.hurtbox.rotation = -0.22
	player.body_collision.rotation = 0.18
	player.visual_root.rotation = 0.1

	player._update_bank(Vector2.LEFT)

	assert_almost_eq(player.rotation, 0.37, 0.0001)
	assert_almost_eq(player.hurtbox.rotation, -0.22, 0.0001)
	assert_almost_eq(player.body_collision.rotation, 0.18, 0.0001)
	assert_almost_eq(player.visual_root.rotation, lerpf(0.1, -deg_to_rad(3.0), 0.2), 0.0001)

func test_bruta_spawn_stopped_does_not_start_spin() -> void:
	var player: Player = await _bruta_player()
	player._update_omni_stop_spin(0.1, Vector2.ZERO)

	assert_almost_eq(player.visual_root.rotation, 0.0, 0.0001)

func test_bruta_movement_below_omni_threshold_does_not_start_spin() -> void:
	var player: Player = await _bruta_player()
	player.velocity = Vector2(49.9, 0.0)
	player._update_omni_stop_spin(0.0, Vector2.ZERO)

	assert_eq(player._omni_stop_spin_state, Player.SpinState.IDLE)
	assert_almost_eq(player.visual_root.rotation, 0.0, 0.0001)

func test_bruta_significant_movement_then_stop_starts_spin() -> void:
	var player: Player = await _bruta_player()
	player.velocity = Vector2(50.0, 0.0)
	player._update_omni_stop_spin(0.0, Vector2.RIGHT)
	player.velocity = Vector2(30.1, 0.0)
	player._update_omni_stop_spin(0.0, Vector2.ZERO)
	player.velocity = Vector2(29.9, 0.0)
	player._update_omni_stop_spin(0.0, Vector2.ZERO)

	assert_eq(player._omni_stop_spin_state, Player.SpinState.SPINNING)
	player._update_omni_stop_spin(0.05, Vector2.ZERO)
	assert_ne(player.visual_root.rotation, 0.0)
	player._update_omni_stop_spin(0.30, Vector2.ZERO)
	assert_eq(player.visual_root.rotation, 0.0)

func test_bruta_spin_rotates_only_visual_root() -> void:
	var player: Player = await _bruta_player()
	player.rotation = 0.37
	player.body_collision.rotation = 0.18
	player.hurtbox.rotation = -0.22
	player.velocity = Vector2(60.0, 0.0)
	player._update_omni_stop_spin(0.0, Vector2.RIGHT)
	player.velocity = Vector2(5.0, 0.0)
	player._update_omni_stop_spin(0.0, Vector2.ZERO)
	player._update_omni_stop_spin(0.05, Vector2.ZERO)

	assert_ne(player.visual_root.rotation, 0.0)
	assert_almost_eq(player.rotation, 0.37, 0.0001)
	assert_almost_eq(player.body_collision.rotation, 0.18, 0.0001)
	assert_almost_eq(player.hurtbox.rotation, -0.22, 0.0001)

func test_bruta_spin_finishes_at_zero_and_does_not_repeat_while_stopped() -> void:
	var player: Player = await _bruta_player()
	player.velocity = Vector2(60.0, 0.0)
	player._update_omni_stop_spin(0.0, Vector2.RIGHT)
	player.velocity = Vector2(5.0, 0.0)
	player._update_omni_stop_spin(0.0, Vector2.ZERO)
	player._update_omni_stop_spin(0.1, Vector2.ZERO)
	player._update_omni_stop_spin(0.1, Vector2.ZERO)
	player._update_omni_stop_spin(0.15, Vector2.ZERO)
	assert_almost_eq(player.visual_root.rotation, 0.0, 0.0001)
	player._update_omni_stop_spin(0.1, Vector2.ZERO)
	assert_almost_eq(player.visual_root.rotation, 0.0, 0.0001)

func test_bruta_stop_events_alternate_spin_direction() -> void:
	var player: Player = await _bruta_player()
	player.velocity = Vector2(60.0, 0.0)
	player._update_omni_stop_spin(0.0, Vector2.RIGHT)
	player.velocity = Vector2(5.0, 0.0)
	player._update_omni_stop_spin(0.0, Vector2.ZERO)
	player._update_omni_stop_spin(0.01, Vector2.ZERO)
	var first_rotation := player.visual_root.rotation
	player._update_omni_stop_spin(0.35, Vector2.ZERO)
	player.velocity = Vector2(60.0, 0.0)
	player._update_omni_stop_spin(0.0, Vector2.RIGHT)
	player.velocity = Vector2(5.0, 0.0)
	player._update_omni_stop_spin(0.0, Vector2.ZERO)
	player._update_omni_stop_spin(0.01, Vector2.ZERO)

	assert_true(first_rotation < 0.0)
	assert_true(player.visual_root.rotation > 0.0)

func test_bruta_new_input_cancels_spin_and_restores_visual_root() -> void:
	var player: Player = await _bruta_player()
	player.velocity = Vector2(60.0, 0.0)
	player._update_omni_stop_spin(0.0, Vector2.RIGHT)
	player.velocity = Vector2(5.0, 0.0)
	player._update_omni_stop_spin(0.0, Vector2.ZERO)
	player._update_omni_stop_spin(0.05, Vector2.ZERO)
	player._update_omni_stop_spin(0.0, Vector2.RIGHT)

	assert_almost_eq(player.visual_root.rotation, 0.0, 0.0001)

func test_aim_forward_never_enters_spin_fsm_and_switch_to_base_clears_state() -> void:
	var player: Player = await _bruta_player()
	player.velocity = Vector2(60.0, 0.0)
	player._update_omni_stop_spin(0.0, Vector2.RIGHT)
	player.velocity = Vector2(5.0, 0.0)
	player._update_omni_stop_spin(0.0, Vector2.ZERO)
	player._update_omni_stop_spin(0.01, Vector2.ZERO)
	assert_ne(player.visual_root.rotation, 0.0)
	assert_true(player.configure_ship(ShipCatalog.get_ship(&"nave_base")))
	assert_almost_eq(player.visual_root.rotation, 0.0, 0.0001)
	player._update_omni_stop_spin(0.1, Vector2.ZERO)
	assert_almost_eq(player.visual_root.rotation, 0.0, 0.0001)


func test_bruta_escape_thrusters_are_opposite_to_movement() -> void:
	var player: Player = await _bruta_player()
	var cases := [
		[Vector2.UP, &"Thruster"],
		[Vector2.LEFT, &"ThrusterRight"],
		[Vector2.DOWN, &"ThrusterTop"],
		[Vector2.RIGHT, &"ThrusterLeft"],
	]
	for test_case in cases:
		player._update_thruster(test_case[0])
		for current_thruster in player.thrusters:
			assert_eq(current_thruster.emitting, current_thruster.name == test_case[1])


func test_bruta_hides_muzzle_and_skips_firing() -> void:
	var player: Player = await _bruta_player()
	assert_false(player.muzzle.visible)

	var projectiles := Node2D.new()
	add_child_autofree(projectiles)
	player._projectiles = projectiles
	player._fire()

	assert_eq(projectiles.get_child_count(), 0, "A Bruta nao deve disparar quando has_muzzle e false.")

func test_switching_between_bruta_and_base_restores_contracts() -> void:
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	assert_true(player.configure_ship(BRUTA))
	assert_false(player.muzzle.visible)
	assert_true(player.configure_ship(ShipCatalog.get_ship(&"nave_base")))
	assert_true(player.muzzle.visible)

func test_bruta_charge_hits_each_enemy_once_and_calls_stun_when_api_exists() -> void:
	var player: Player = await _bruta_player()
	player.global_position = Vector2(100.0, 100.0)
	var enemy := ChargeEnemyStub.new()
	var second_enemy := ChargeEnemyStub.new()
	enemy.global_position = Vector2(120.0, 100.0)
	second_enemy.global_position = Vector2(140.0, 100.0)
	add_child_autofree(enemy)
	add_child_autofree(second_enemy)
	await get_tree().process_frame
	player._bruta_charge_direction = Vector2.RIGHT
	player._resolve_bruta_charge_hits(player.global_position, Vector2(160.0, 100.0))
	player._resolve_bruta_charge_hits(player.global_position, Vector2(160.0, 100.0))

	assert_eq(enemy.damage_calls, 1)
	assert_eq(enemy.stun_calls, 1)
	assert_eq(enemy.last_stun_duration, 0.75)
	assert_eq(second_enemy.damage_calls, 1)
	assert_eq(second_enemy.stun_calls, 1)

func test_bruta_charge_does_not_teleport_and_accelerates_after_windup() -> void:
	var player: Player = await _bruta_player()
	player.global_position = Vector2(100.0, 100.0)
	player._bruta_charge_direction = Vector2.RIGHT
	player._bruta_charge_windup_remaining = 0.12
	player._bruta_charge_remaining = 0.75
	player._update_bruta_charge(0.12)
	_assert_vector_almost_eq(player.velocity, Vector2.ZERO)
	_assert_vector_almost_eq(player.global_position, Vector2(100.0, 100.0))
	player._update_bruta_charge(0.001)
	assert_almost_eq(player.velocity.length(), 180.0, 0.01)
	assert_gt(player.global_position.x, 100.0)
	var initial_active_speed := player.velocity.length()
	player._update_bruta_charge(0.001)
	assert_gt(player.velocity.length(), initial_active_speed)


func test_bruta_charge_preparation_012_seconds_has_no_displacement() -> void:
	var player: Player = await _bruta_player()
	player.global_position = Vector2(100.0, 100.0)
	player._bruta_charge_direction = Vector2.RIGHT
	player._bruta_charge_windup_remaining = 0.12
	player._bruta_charge_remaining = 0.75

	player._update_bruta_charge(0.12)

	_assert_vector_almost_eq(player.global_position, Vector2(100.0, 100.0))
	_assert_vector_almost_eq(player.velocity, Vector2.ZERO)
	assert_almost_eq(player._bruta_charge_windup_remaining, 0.0, 0.000001)
	assert_almost_eq(player._bruta_charge_remaining, 0.75, 0.000001)


func test_bruta_charge_first_active_frame_starts_at_180_pixels_per_second() -> void:
	var player: Player = await _bruta_player()
	player._bruta_charge_direction = Vector2.RIGHT
	player._bruta_charge_windup_remaining = 0.12
	player._bruta_charge_remaining = 0.75

	player._update_bruta_charge(0.12 + 1.0 / 60.0)

	# O primeiro frame tambem consome 1/60 s da fase ativa; a curva integrada
	# portanto ja avancou ligeiramente acima da velocidade inicial.
	assert_almost_eq(player.velocity.length(), 180.2172839506, 0.001)
	assert_gte(player.velocity.length(), 180.0)
	assert_lte(player.velocity.length(), 181.0)


func test_bruta_charge_last_active_frame_reaches_620_pixels_per_second() -> void:
	var player: Player = await _bruta_player()
	player._bruta_charge_direction = Vector2.RIGHT
	player._bruta_charge_windup_remaining = 0.0
	player._bruta_charge_remaining = 0.75

	var frame_delta := 1.0 / 60.0
	for _frame in 44:
		player._update_bruta_charge(frame_delta)
	player._update_bruta_charge(frame_delta - 0.000001)

	assert_almost_eq(player.velocity.length(), 620.0, 0.01)
	assert_gt(player._bruta_charge_remaining, 0.0)
	assert_lt(player._bruta_charge_remaining, 0.00001)


func test_bruta_charge_delta_crossing_windup_consumes_only_active_excess() -> void:
	var player: Player = await _bruta_player()
	player._bruta_charge_direction = Vector2.RIGHT
	player._bruta_charge_windup_remaining = 0.12
	player._bruta_charge_remaining = 0.75

	player._update_bruta_charge(0.20)

	assert_almost_eq(player._bruta_charge_windup_remaining, 0.0, 0.000001)
	assert_almost_eq(player._bruta_charge_remaining, 0.67, 0.000001)
	assert_almost_eq(player.velocity.length(), 180.0 + (440.0 * (0.08 / 0.75) * (0.08 / 0.75)), 0.01)


func test_bruta_charge_active_duration_never_exceeds_075_seconds() -> void:
	var player: Player = await _bruta_player()
	player._bruta_charge_direction = Vector2.RIGHT
	player._bruta_charge_windup_remaining = 0.0
	player._bruta_charge_remaining = 0.75

	player._update_bruta_charge(1.5)

	assert_almost_eq(player._bruta_charge_remaining, 0.0, 0.000001)
	assert_false(player._is_bruta_charging())
	_assert_vector_almost_eq(player.velocity, Vector2.ZERO)

func test_bruta_charge_integrates_same_active_displacement_at_60hz_and_large_delta() -> void:
	var stepped: Player = await _bruta_player()
	var large_step: Player = await _bruta_player()
	for player in [stepped, large_step]:
		player.global_position = Vector2(100.0, 100.0)
		player._bruta_charge_direction = Vector2.RIGHT
		player._bruta_charge_windup_remaining = 0.0
		player._bruta_charge_remaining = 0.75

	for _frame in 45:
		stepped._update_bruta_charge(1.0 / 60.0)
	large_step._update_bruta_charge(0.75)

	var stepped_displacement := stepped.global_position.x - 100.0
	var large_displacement := large_step.global_position.x - 100.0
	assert_almost_eq(stepped_displacement, 245.0, 0.01)
	assert_almost_eq(large_displacement, 245.0, 0.01)
	assert_almost_eq(stepped_displacement, large_displacement, 0.01)
	assert_almost_eq(stepped.velocity.length(), 0.0, 0.001)
	assert_almost_eq(large_step.velocity.length(), 0.0, 0.001)

func test_bruta_charge_uses_mouse_direction_when_mouse_is_active() -> void:
	var player: Player = await _bruta_player()
	player.global_position = Vector2(200.0, 200.0)
	player._last_aim_source = Player.AimSource.MOUSE
	player._aim_vector = Vector2.UP
	player.get_viewport().warp_mouse(Vector2(300.0, 200.0))
	assert_true(player.start_bruta_charge())
	assert_eq(player._bruta_charge_direction, Vector2.RIGHT)

func test_bruta_charge_uses_active_joypad_direction_over_opposite_cursor() -> void:
	var player: Player = await _bruta_player()
	player.global_position = Vector2(200.0, 200.0)
	player.get_viewport().warp_mouse(Vector2(100.0, 200.0))
	Input.action_press(&"aim_right")
	player._update_aim()
	assert_eq(player._last_aim_source, Player.AimSource.JOYPAD)
	assert_true(player.start_bruta_charge())
	Input.action_release(&"aim_right")
	assert_eq(player._bruta_charge_direction, Vector2.RIGHT)

func test_bruta_charge_mitigates_damage_during_active_window() -> void:
	var player: Player = await _bruta_player()
	var info := DamageInfo.new()
	info.amount = 1.0
	player._bruta_charge_remaining = 0.75
	var before := player.health.health
	player.take_damage(info)
	assert_almost_eq(player.health.health, before - 0.6, 0.001)

func test_bruta_charge_takes_full_damage_during_windup() -> void:
	var player: Player = await _bruta_player()
	var info := DamageInfo.new()
	info.amount = 1.0
	player._bruta_charge_windup_remaining = 0.12
	player._bruta_charge_remaining = 0.75
	var before := player.health.health
	player.take_damage(info)
	assert_almost_eq(player.health.health, before - 1.0, 0.001)

func test_bruta_charge_takes_full_damage_after_active_window() -> void:
	var player: Player = await _bruta_player()
	var info := DamageInfo.new()
	info.amount = 1.0
	player._bruta_charge_remaining = 0.0
	var before := player.health.health
	player.take_damage(info)
	assert_almost_eq(player.health.health, before - 1.0, 0.001)

func test_bruta_charge_uses_large_target_collision_shape_when_tangential() -> void:
	var player: Player = await _bruta_player()
	player.global_position = Vector2(100.0, 100.0)
	var enemy := ChargeEnemyStub.new()
	enemy.global_position = Vector2(130.0, 100.0)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 25.0
	shape.shape = circle
	enemy.add_child(shape)
	add_child_autofree(enemy)
	await get_tree().process_frame
	player._resolve_bruta_charge_hits(player.global_position, Vector2(110.0, 100.0))

	assert_eq(enemy.damage_calls, 1)
	assert_eq(enemy.stun_calls, 1)
	assert_almost_eq(enemy.last_stun_duration, 0.75, 0.0001)

func test_bruta_charge_leaves_target_outside_collision_extension_intact() -> void:
	var player: Player = await _bruta_player()
	player.global_position = Vector2(100.0, 100.0)
	var enemy := ChargeEnemyStub.new()
	enemy.global_position = Vector2(130.0, 150.0)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 25.0
	shape.shape = circle
	enemy.add_child(shape)
	add_child_autofree(enemy)
	await get_tree().process_frame
	player._resolve_bruta_charge_hits(player.global_position, Vector2(160.0, 100.0))

	assert_eq(enemy.damage_calls, 0)
	assert_eq(enemy.stun_calls, 0)

class ChargeEnemyStub extends Node2D:
	var damage_calls := 0
	var stun_calls := 0
	var last_stun_duration := 0.0

	func _ready() -> void:
		add_to_group(&"enemies")

	func take_damage(_info: DamageInfo) -> float:
		damage_calls += 1
		return 2.0

	func apply_stun(duration: float) -> void:
		stun_calls += 1
		last_stun_duration = duration
