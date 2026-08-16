extends GutTest

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const BRUTA := preload("res://resources/ships/bruta.tres")
const BRUTA_SPRITE_PATH := "res://assets/sprites/bruta-hull.png"
const HEALTH_UNITS := preload("res://scripts/components/health_units.gd")
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


func _player_with_ship(ship_def: ShipDef) -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
	player.ship = ship_def
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
	assert_eq(BRUTA.ability_q, &"")
	assert_eq(BRUTA.movement_style, "omni")
	assert_eq(BRUTA.frame_size, Vector2i(32, 32))
	assert_eq(BRUTA.hurtbox_radius, 10.0)
	assert_eq(BRUTA.collision_shape_type, "circle")
	assert_false(BRUTA.has_muzzle)
	assert_eq(BRUTA.ability_shift, &"bruta_investida")
	assert_false(BRUTA.can_blink)


func test_bruta_resolves_shift_slot_to_bruta_investida() -> void:
	var player: Player = await _bruta_player()

	assert_true(player.uses_bruta_charge_shift())
	assert_not_null(player._ability_shift)
	if player._ability_shift != null:
		assert_eq(player._ability_shift.id, &"bruta_investida")
	assert_eq(AbilityCatalog.get_ability(&"bruta_investida").id, &"bruta_investida")


func test_bruta_shift_input_starts_charge_instead_of_try_blink() -> void:
	var player: Player = await _bruta_player()
	# A investida recaptura a mira quando a fonte ativa e o mouse; portanto,
	# posiciona a nave relativamente ao cursor e atualiza a fonte pelo fluxo real.
	var cursor := player.get_global_mouse_position()
	player.global_position = cursor - Vector2.RIGHT * 100.0
	player._update_aim()
	assert_eq(player._last_aim_source, Player.AimSource.MOUSE)
	_assert_vector_almost_eq(player._aim_vector, Vector2.RIGHT)
	var before := player.global_position
	Input.action_press(&"blink")

	assert_true(player._handle_blink_input())
	assert_true(player._is_bruta_charging())
	assert_eq(player._bruta_charge_direction, Vector2.RIGHT)
	assert_eq(player.global_position, before)
	assert_eq(player.blink_cooldown_ratio(), 0.0)
	assert_gt(player.shift_cooldown_ratio(), 0.0)


func test_bruta_shift_cooldown_rejects_second_activation() -> void:
	var player: Player = await _bruta_player()
	var cursor := player.get_global_mouse_position()
	player.global_position = cursor - Vector2.RIGHT * 100.0
	player._update_aim()
	assert_eq(player._last_aim_source, Player.AimSource.MOUSE)
	_assert_vector_almost_eq(player._aim_vector, Vector2.RIGHT)
	Input.action_press(&"blink")

	assert_true(player._handle_blink_input())
	var windup_before := player._bruta_charge_windup_remaining
	assert_false(player._handle_blink_input())
	assert_eq(player._bruta_charge_windup_remaining, windup_before)
	assert_gt(player.shift_cooldown_ratio(), 0.0)

func test_bruta_collision_knockback_survives_charge_substeps_and_cancel() -> void:
	var player: Player = await _bruta_player()
	player.set_physics_process(false)
	player.global_position = Vector2(100.0, 100.0)
	player._aim_vector = Vector2.RIGHT
	player._bruta_charge_direction = Vector2.RIGHT
	player._bruta_charge_aim_source = Player.AimSource.NONE
	player._bruta_charge_windup_remaining = 0.0
	player._bruta_charge_remaining = 0.75
	player.apply_collision_knockback(Vector2(100.0, 0.0))

	player._update_bruta_charge(0.01)
	var after_first_substep := player._collision_knockback_velocity.x
	player._update_bruta_charge(0.01)
	var after_second_substep := player._collision_knockback_velocity.x

	assert_gt(after_first_substep, 0.0)
	assert_gt(after_second_substep, 0.0)
	assert_lt(after_second_substep, after_first_substep)
	player._cancel_bruta_charge()
	assert_almost_eq(player.velocity.x, player._collision_knockback_velocity.x, 0.00001)
	assert_gt(player.velocity.x, 0.0)

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
	assert_eq(BRUTA.base_stats.size(), 5)
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
		&"collision_damage_resistance": 0.5,
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

	assert_eq(enemy.damage_calls, 0)
	assert_eq(enemy.stun_calls, 1)
	assert_eq(enemy.last_stun_duration, 0.75)
	assert_eq(second_enemy.damage_calls, 0)
	assert_eq(second_enemy.stun_calls, 1)

func test_bruta_charge_does_not_teleport_and_accelerates_after_windup() -> void:
	var player: Player = await _bruta_player()
	player.global_position = Vector2(100.0, 100.0)
	player._bruta_charge_direction = Vector2.RIGHT
	player._aim_vector = Vector2.RIGHT
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


func test_bruta_charge_windup_tracks_valid_aim_without_displacement() -> void:
	var player: Player = await _bruta_player()
	player.global_position = Vector2(100.0, 100.0)
	player._bruta_charge_direction = Vector2.RIGHT
	player._bruta_charge_windup_remaining = 0.12
	player._bruta_charge_remaining = 0.75
	player._aim_vector = Vector2.DOWN

	player._update_bruta_charge(0.06)

	_assert_vector_almost_eq(player._bruta_charge_direction, Vector2.DOWN)
	_assert_vector_almost_eq(player.global_position, Vector2(100.0, 100.0))
	_assert_vector_almost_eq(player.velocity, Vector2.ZERO)


func test_bruta_charge_active_turn_is_limited_by_turn_rate() -> void:
	var player: Player = await _bruta_player()
	player.global_position = Vector2(100.0, 100.0)
	player._bruta_charge_direction = Vector2.RIGHT
	player._bruta_charge_windup_remaining = 0.0
	player._bruta_charge_remaining = 0.75
	player._aim_vector = Vector2.DOWN
	var active_delta := 0.1

	player._update_bruta_charge(active_delta)

	var turn_limit := Player.BRUTA_CHARGE_TURN_RATE * active_delta
	assert_gt(player._bruta_charge_direction.angle(), 0.0)
	assert_lte(player._bruta_charge_direction.angle(), turn_limit + 0.000001)
	assert_almost_eq(player._bruta_charge_direction.angle(), turn_limit, 0.000001)


func test_bruta_charge_active_deadzone_keeps_current_direction() -> void:
	var player: Player = await _bruta_player()
	player.global_position = Vector2(100.0, 100.0)
	player._bruta_charge_direction = Vector2.RIGHT
	player._bruta_charge_aim_source = Player.AimSource.JOYPAD
	player._bruta_charge_windup_remaining = 0.0
	player._bruta_charge_remaining = 0.75
	player._aim_vector = Vector2.DOWN
	Input.action_press(&"aim_down", 0.1)

	player._update_bruta_charge(0.1)

	_assert_vector_almost_eq(player._bruta_charge_direction, Vector2.RIGHT)
	Input.action_release(&"aim_down")


func test_bruta_charge_hits_target_on_curved_active_segment() -> void:
	var player: Player = await _bruta_player()
	var enemy := ChargeEnemyStub.new()
	# Em 0.1 s, o caminho sobe para fora do segmento horizontal original.
	# O alvo fica fora desse segmento, mas sobre a curva integrada em subpassos.
	enemy.global_position = Vector2(117.0, 111.0)
	add_child_autofree(enemy)
	await get_tree().process_frame
	player.set_physics_process(false)
	player.global_position = Vector2(100.0, 100.0)
	player._bruta_charge_direction = Vector2.RIGHT
	player._aim_vector = Vector2.DOWN
	player._bruta_charge_windup_remaining = 0.0
	player._bruta_charge_remaining = 0.75

	player._update_bruta_charge(0.1)

	assert_gt(player._bruta_charge_direction.angle(), 0.0)
	assert_eq(enemy.damage_calls, 1)
	assert_eq(enemy.stun_calls, 1)


func test_bruta_charge_first_active_frame_starts_at_180_pixels_per_second() -> void:
	var player: Player = await _bruta_player()
	player.set_physics_process(false)
	player.global_position = Vector2(100.0, 100.0)
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
	player.set_physics_process(false)
	player.global_position = Vector2(100.0, 100.0)
	player._aim_vector = Vector2.RIGHT
	player._bruta_charge_direction = Vector2.RIGHT
	player._bruta_charge_aim_source = Player.AimSource.NONE
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
	player.set_physics_process(false)
	player.global_position = Vector2(100.0, 100.0)
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

func test_bruta_charge_stops_at_safe_room_boundary_and_clears_state() -> void:
	var player: Player = await _bruta_player()
	player.set_room_bounds(Rect2(Vector2.ZERO, Vector2(200.0, 160.0)))
	player.global_position = Vector2(100.0, 80.0)
	player._bruta_charge_direction = Vector2.RIGHT
	player._aim_vector = Vector2.RIGHT
	player._bruta_charge_windup_remaining = 0.0
	player._bruta_charge_remaining = 0.75

	player._update_bruta_charge(0.75)

	_assert_vector_almost_eq(player.global_position, Vector2(190.0, 80.0))
	assert_false(player._is_bruta_charging())
	_assert_vector_almost_eq(player._bruta_charge_direction, Vector2.ZERO)
	_assert_vector_almost_eq(player.velocity, Vector2.ZERO)

func test_bruta_charge_integrates_same_active_displacement_at_60hz_and_large_delta() -> void:
	var stepped: Player = await _bruta_player()
	var large_step: Player = await _bruta_player()
	for player in [stepped, large_step]:
		player.global_position = Vector2(100.0, 100.0)
		player._bruta_charge_direction = Vector2.RIGHT
		player._aim_vector = Vector2.RIGHT
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

func test_bruta_charge_steering_static_right_to_down_is_deterministic_and_curved() -> void:
	var players: Array[Player] = []
	for _i in 3:
		var player: Player = await _bruta_player()
		players.append(player)
	for player in players:
		player.set_physics_process(false)
		player.global_position = Vector2(100.0, 100.0)
		player._bruta_charge_direction = Vector2.RIGHT
		player._bruta_charge_aim_source = Player.AimSource.JOYPAD
		player._bruta_charge_windup_remaining = 0.0
		player._bruta_charge_remaining = 0.75
		Input.action_press(&"aim_down")
	# Todos usam o mesmo alvo estático; 1/240 s torna o resultado independente
	# do delta externo, com tolerância pequena para arredondamento de ponto flutuante.
	for _frame in 42:
		players[0]._update_bruta_charge(1.0 / 60.0)
	for _frame in 84:
		players[1]._update_bruta_charge(1.0 / 120.0)
	players[2]._update_bruta_charge(0.70)
	Input.action_release(&"aim_down")

	_assert_vector_almost_eq(players[0].global_position, players[1].global_position, 0.05)
	_assert_vector_almost_eq(players[0].global_position, players[2].global_position, 0.05)
	_assert_vector_almost_eq(players[0]._bruta_charge_direction, players[1]._bruta_charge_direction, 0.0002)
	_assert_vector_almost_eq(players[0]._bruta_charge_direction, players[2]._bruta_charge_direction, 0.0002)
	assert_gt(players[0].global_position.x, 100.0)
	assert_gt(players[0].global_position.y, 100.0)
	assert_gt(players[0]._bruta_charge_direction.angle(), 0.05)
	# No meio da carga, a posição não pode estar na corda instantânea RIGHT->DOWN.
	var midpoint: Player = await _bruta_player()
	midpoint.set_physics_process(false)
	midpoint.global_position = Vector2(100.0, 100.0)
	midpoint._bruta_charge_direction = Vector2.RIGHT
	midpoint._bruta_charge_aim_source = Player.AimSource.JOYPAD
	midpoint._bruta_charge_windup_remaining = 0.0
	midpoint._bruta_charge_remaining = 0.70
	Input.action_press(&"aim_down")
	midpoint._update_bruta_charge(0.35)
	Input.action_release(&"aim_down")
	assert_gt(midpoint.global_position.x - 100.0, 1.0)
	assert_gt(midpoint.global_position.y - 100.0, 1.0)

func test_bruta_charge_steering_uses_short_path_across_pi_wrap() -> void:
	var player: Player = await _bruta_player()
	player.set_physics_process(false)
	player.global_position = Vector2(100.0, 100.0)
	player._bruta_charge_direction = Vector2(-1.0, 0.01).normalized()
	player._bruta_charge_aim_source = Player.AimSource.JOYPAD
	player._bruta_charge_windup_remaining = 0.0
	player._bruta_charge_remaining = 0.75
	Input.action_press(&"aim_left")
	player._update_bruta_charge(0.01)
	Input.action_release(&"aim_left")
	assert_almost_eq(player._bruta_charge_direction.length(), 1.0, 0.000001)
	assert_lt(absf(player._bruta_charge_direction.angle() - PI), 0.05)

func test_bruta_charge_captures_mouse_aim_against_joystick_during_charge() -> void:
	var player: Player = await _bruta_player()
	player.set_physics_process(false)
	player.set_room_bounds(Rect2(Vector2(-1000.0, -1000.0), Vector2(2000.0, 2000.0)))
	var cursor := player.get_global_mouse_position()
	player.global_position = cursor - Vector2.RIGHT * 100.0
	player._update_aim()
	assert_eq(player._last_aim_source, Player.AimSource.MOUSE)
	assert_true(player.start_bruta_charge())
	assert_eq(player._bruta_charge_aim_source, Player.AimSource.MOUSE)
	_assert_vector_almost_eq(player._bruta_charge_direction, Vector2.RIGHT)
	player._bruta_charge_windup_remaining = 0.0
	player.global_position = cursor - Vector2.DOWN * 100.0

	Input.action_press(&"aim_left")
	player._update_bruta_charge(0.1)
	Input.action_release(&"aim_left")

	assert_gt(player._bruta_charge_direction.angle(), 0.0)
	assert_lt(player._bruta_charge_direction.angle(), PI / 2.0)

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

func test_bruta_charge_does_not_apply_generic_damage_mitigation() -> void:
	var player: Player = await _bruta_player()
	var info := DamageInfo.new()
	info.amount = HEALTH_UNITS.from_hp(1.0)
	player._bruta_charge_remaining = 0.75
	var before := player.health.health
	player.take_damage(info)
	assert_eq(player.health.health, before - HEALTH_UNITS.from_hp(1.0))


func test_bruta_collision_resistance_is_half_while_enemy_receives_full_impact() -> void:
	var bruta: Player = await _bruta_player()
	var base: Player = await _player_with_ship(preload("res://resources/ships/base.tres"))
	var bruta_enemy := CollisionEnemyStub.new()
	var base_enemy := CollisionEnemyStub.new()
	for enemy in [bruta_enemy, base_enemy]:
		add_child_autofree(enemy)
	await get_tree().process_frame
	bruta.global_position = Vector2(100.0, 100.0)
	base.global_position = Vector2(100.0, 200.0)
	bruta_enemy.global_position = Vector2(115.0, 100.0)
	base_enemy.global_position = Vector2(115.0, 200.0)
	bruta.velocity = Vector2.RIGHT * 100.0
	base.velocity = Vector2.RIGHT * 100.0
	CollisionImpactResolver.resolve_segment(bruta, bruta.global_position, bruta.global_position + Vector2.RIGHT * 20.0, {})
	CollisionImpactResolver.resolve_segment(base, base.global_position, base.global_position + Vector2.RIGHT * 20.0, {})

	var bruta_damage := bruta.health.max_health - bruta.health.health
	var base_damage := base.health.max_health - base.health.health
	assert_eq(bruta_damage, base_damage / 2)
	assert_eq(bruta_enemy.damage_amounts[0], base_enemy.damage_amounts[0])


func test_bruta_collision_contact_is_spent_once_and_rearms_after_separation() -> void:
	var player: Player = await _bruta_player()
	var enemy := CollisionEnemyStub.new()
	add_child_autofree(enemy)
	await get_tree().process_frame
	player.global_position = Vector2(100.0, 100.0)
	enemy.global_position = Vector2(115.0, 100.0)
	player.velocity = Vector2.RIGHT * 100.0
	var pairs: Dictionary = {}
	CollisionImpactResolver.resolve_segment(player, Vector2(100.0, 100.0), Vector2(120.0, 100.0), pairs)
	CollisionImpactResolver.resolve_segment(player, Vector2(100.0, 100.0), Vector2(120.0, 100.0), pairs)
	assert_eq(enemy.damage_amounts.size(), 1)
	CollisionImpactResolver.resolve_segment(player, Vector2(200.0, 100.0), Vector2(220.0, 100.0), pairs)
	player.velocity = Vector2.RIGHT * 100.0
	CollisionImpactResolver.resolve_segment(player, Vector2(100.0, 100.0), Vector2(120.0, 100.0), pairs)
	assert_eq(enemy.damage_amounts.size(), 2)


func test_bruta_projectile_enemy_projectile_and_generic_damage_are_not_mitigated() -> void:
	var player: Player = await _bruta_player()
	for tag in [&"projectile", &"enemy_projectile", &"generic"]:
		var info := DamageInfo.new()
		info.amount = HEALTH_UNITS.from_hp(1.0)
		info.tags = [tag]
		player._invuln_timer = 0.0
		var before := player.health.health
		player.take_damage(info)
		assert_eq(player.health.health, before - HEALTH_UNITS.from_hp(1.0), String(tag))


func test_bruta_lethal_first_charge_subpass_aborts_remaining_targets_and_state() -> void:
	var player: Player = await _bruta_player()
	var first := CollisionEnemyStub.new()
	var second := CollisionEnemyStub.new()
	add_child_autofree(first)
	add_child_autofree(second)
	await get_tree().process_frame
	var prior_lives := GameState.player_lives
	GameState.player_lives = 1
	player.set_physics_process(false)
	player.global_position = Vector2(100.0, 100.0)
	player.health.health = HEALTH_UNITS.from_hp(0.01)
	player._bruta_charge_direction = Vector2.RIGHT
	player._bruta_charge_windup_remaining = 0.0
	player._bruta_charge_remaining = 0.75
	first.global_position = Vector2(112.0, 100.0)
	# Ambos precisam estar no primeiro subpasso; caso contrario, o teste
	# passaria mesmo que a geração continuasse depois da morte.
	second.global_position = Vector2(116.0, 100.0)

	player._update_bruta_charge(0.1)

	assert_gt(first.damage_amounts.size(), 0)
	assert_eq(second.damage_amounts.size(), 0)
	assert_eq(second.stun_calls, 0)
	assert_false(player._is_bruta_charging())
	_assert_vector_almost_eq(player.velocity, Vector2.ZERO)
	_assert_vector_almost_eq(player._collision_knockback_velocity, Vector2.ZERO)
	GameState.player_lives = prior_lives


func test_bruta_loadout_reconfiguration_clears_shift_cooldown_and_charge_state() -> void:
	var player: Player = await _bruta_player()
	player._ability_shift_cd = 3.0
	player._ability_shift_cd_duration = 5.0
	player._bruta_charge_direction = Vector2.RIGHT
	player._bruta_charge_windup_remaining = 0.12
	player._bruta_charge_remaining = 0.75
	player.velocity = Vector2.RIGHT * 200.0

	player._configure_loadout()

	assert_almost_eq(player._ability_shift_cd, 0.0, 0.001)
	assert_almost_eq(player._ability_shift_cd_duration, 0.0, 0.001)
	assert_false(player._is_bruta_charging())
	_assert_vector_almost_eq(player.velocity, Vector2.ZERO)

func test_bruta_death_clears_shift_state_even_on_terminal_life() -> void:
	var player: Player = await _bruta_player()
	var prior_lives := GameState.player_lives
	GameState.player_lives = 1
	player._ability_shift_cd = 3.0
	player._ability_shift_cd_duration = 5.0
	player._bruta_charge_direction = Vector2.RIGHT
	player._bruta_charge_windup_remaining = 0.12
	player._bruta_charge_remaining = 0.75
	player.velocity = Vector2.RIGHT * 200.0

	player._on_died(DamageInfo.new())

	assert_eq(GameState.player_lives, 0)
	assert_almost_eq(player._ability_shift_cd, 0.0, 0.001)
	assert_almost_eq(player._ability_shift_cd_duration, 0.0, 0.001)
	assert_false(player._is_bruta_charging())
	_assert_vector_almost_eq(player._bruta_charge_direction, Vector2.ZERO)
	_assert_vector_almost_eq(player.velocity, Vector2.ZERO)
	assert_false(player.visible)
	GameState.player_lives = prior_lives


func test_bruta_charge_stops_at_obstacle_before_bounded_endpoint() -> void:
	var player: Player = await _bruta_player()
	player.global_position = Vector2(100.0, 100.0)
	var obstacle := StaticBody2D.new()
	obstacle.global_position = Vector2(180.0, 100.0)
	var collision_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(20.0, 100.0)
	collision_shape.shape = rectangle
	obstacle.add_child(collision_shape)
	add_child_autofree(obstacle)
	await get_tree().physics_frame
	player._bruta_charge_direction = Vector2.RIGHT
	player._aim_vector = Vector2.RIGHT
	player._bruta_charge_remaining = 0.75

	player._update_bruta_charge(0.75)

	assert_lt(player.global_position.x, 170.0)
	assert_false(player._is_bruta_charging())
	_assert_vector_almost_eq(player.velocity, Vector2.ZERO)

func test_bruta_charge_takes_full_damage_during_windup() -> void:
	var player: Player = await _bruta_player()
	var info := DamageInfo.new()
	info.amount = HEALTH_UNITS.from_hp(1.0)
	player._bruta_charge_windup_remaining = 0.12
	player._bruta_charge_remaining = 0.75
	var before := player.health.health
	player.take_damage(info)
	assert_eq(player.health.health, before - HEALTH_UNITS.from_hp(1.0))

func test_bruta_charge_takes_full_damage_after_active_window() -> void:
	var player: Player = await _bruta_player()
	var info := DamageInfo.new()
	info.amount = HEALTH_UNITS.from_hp(1.0)
	player._bruta_charge_remaining = 0.0
	var before := player.health.health
	player.take_damage(info)
	assert_eq(player.health.health, before - HEALTH_UNITS.from_hp(1.0))

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

	assert_eq(enemy.damage_calls, 0)
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

	func take_damage(_info: DamageInfo) -> int:
		damage_calls += 1
		return HEALTH_UNITS.from_hp(2.0)

	func apply_stun(duration: float) -> void:
		stun_calls += 1
		last_stun_duration = duration


class CollisionEnemyStub extends Node2D:
	var damage_amounts: Array[int] = []
	var stun_calls := 0
	var knockback := Vector2.ZERO

	func _ready() -> void:
		add_to_group(&"enemies")

	func take_damage(info: DamageInfo) -> int:
		damage_amounts.append(info.amount)
		return info.amount

	func apply_stun(_duration: float) -> void:
		stun_calls += 1

	func apply_collision_knockback(impulse: Vector2) -> void:
		knockback += impulse
