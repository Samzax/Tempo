extends GutTest

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const SHIP_IDS: Array[StringName] = [
	&"nave_base",
	&"nave_bruta",
	&"nave_engenheira",
	&"nave_interceptadora",
	&"nave_interestelar",
	&"nave_rastreadora",
]

func _player() -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	await get_tree().process_frame
	return player

func _release_inputs() -> void:
	for action in [&"move_up", &"move_left", &"move_down", &"move_right", &"aim_up", &"aim_left", &"aim_down", &"aim_right"]:
		Input.action_release(action)

func before_each() -> void:
	_release_inputs()

func after_each() -> void:
	_release_inputs()

func _thrust_deterministically(player: Player, delta: float) -> Vector2:
	Input.action_press(&"aim_right")
	Input.action_press(&"move_up")
	player._physics_process(delta)
	_release_inputs()
	return player.velocity

func test_all_playable_ships_and_default_ship_move_through_player_physics() -> void:
	var player := await _player()
	for ship_id in SHIP_IDS:
		assert_true(player.configure_ship(ShipCatalog.get_ship(ship_id)), str(ship_id))
		player.velocity = Vector2.ZERO
		var result := _thrust_deterministically(player, 1.0 / 60.0)
		assert_gt(result.length(), 0.0, str(ship_id))
		assert_lte(result.length(), player._stats.get_stat(&"max_speed"), str(ship_id))
		if player.ship.movement_style == "omni":
			assert_almost_eq(result.normalized().dot(Vector2.UP), 1.0, 0.0001, str(ship_id))
		else:
			assert_almost_eq(result.normalized().dot(Vector2.RIGHT), 1.0, 0.0001, str(ship_id))

	assert_true(player.configure_ship(ShipDef.new()))
	player.velocity = Vector2.ZERO
	var default_result := _thrust_deterministically(player, 1.0 / 60.0)
	assert_gt(default_result.length(), 0.0)
	assert_lte(default_result.length(), player._stats.get_stat(&"max_speed"))

func test_default_resource_values_are_raw_and_unscaled() -> void:
	var player := await _player()
	assert_true(player.configure_ship(ShipDef.new()))
	player.velocity = Vector2.ZERO
	assert_eq(player._stats.get_stat(&"acceleration"), 1000.0)
	assert_eq(player._stats.get_stat(&"friction"), 1300.0)
	assert_eq(player._stats.get_stat(&"max_speed"), 150.0)

func test_acceleration_uses_raw_stat_times_player_factor() -> void:
	var player := await _player()
	assert_true(player.configure_ship(ShipCatalog.get_ship(&"nave_base")))
	player.velocity = Vector2.ZERO
	var delta := 0.1
	var raw_acceleration := player._stats.get_stat(&"acceleration")
	var result := _thrust_deterministically(player, delta)

	assert_almost_eq(result.length(), raw_acceleration * 0.60 * delta, 0.0001)

func test_friction_uses_raw_stat_times_player_factor() -> void:
	var player := await _player()
	assert_true(player.configure_ship(ShipCatalog.get_ship(&"nave_base")))
	assert_eq(player._stats.get_stat(&"max_speed"), 150.0)
	var delta := 0.01
	var initial_speed := 100.0
	var raw_friction := player._stats.get_stat(&"friction")
	player.velocity = Vector2(initial_speed, 0.0)
	player._physics_process(delta)

	assert_almost_eq(player.velocity.length(), initial_speed - raw_friction * 0.35 * delta, 0.0001)
	assert_almost_eq(player.velocity.normalized().dot(Vector2.RIGHT), 1.0, 0.0001)

func test_max_speed_is_observed_and_blink_distance_is_not_scaled() -> void:
	var player := await _player()
	assert_true(player.configure_ship(ShipCatalog.get_ship(&"nave_base")))
	var result := _thrust_deterministically(player, 1.0)
	assert_eq(result.length(), player._stats.get_stat(&"max_speed"))
	player.set_room_bounds(Rect2(Vector2.ZERO, Vector2(1000.0, 1000.0)))
	player.global_position = Vector2(500.0, 500.0)
	player.velocity = Vector2(48.0, -16.0)
	assert_true(player.try_blink(Vector2.RIGHT))
	assert_eq(player.global_position, Vector2(500.0 + player._stats.get_stat(&"blink_distance"), 500.0))
	assert_eq(player.velocity, Vector2(48.0, -16.0))
