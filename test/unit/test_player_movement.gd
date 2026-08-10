extends GutTest

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const MOTION := preload("res://scripts/player/asteroids_motion.gd")
const BASE_SHIP := preload("res://resources/ships/base.tres")
const BRUTA_SHIP := preload("res://resources/ships/bruta.tres")
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

func _player() -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	await get_tree().process_frame
	return player

func _blink_player(ship: ShipDef) -> Player:
	var player := await _player()
	assert_true(player.configure_ship(ship))
	player.set_room_bounds(Rect2(Vector2.ZERO, Vector2(2000.0, 2000.0)))
	player.global_position = Vector2(1000.0, 1000.0)
	player.velocity = Vector2(60.0, -40.0)
	player._blink_cd = 0.0
	player._blink_cd_duration = 0.0
	return player

func _engineer_session() -> Session:
	var session := InputTestSession.new()
	add_child_autofree(session)
	var room := Node2D.new()
	var deployables := Node2D.new()
	deployables.name = "Deployables"
	room.add_child(deployables)
	session.add_child(room)
	session._active_room = room
	session._room_active = true
	return session

func _release_inputs() -> void:
	for action in INPUT_ACTIONS:
		Input.action_release(action)

func before_each() -> void:
	_release_inputs()

func after_each() -> void:
	_release_inputs()

func test_heading_points_sprite_nose_and_muzzle_remains_aligned() -> void:
	var player: Player = await _player()
	Input.action_press(&"aim_right")
	player._physics_process(1.0 / 60.0)
	Input.action_release(&"aim_right")

	assert_almost_eq(player.rotation, PI / 2.0, 0.0001)
	assert_almost_eq(player.muzzle.global_position.x, player.global_position.x + 12.0, 0.0001)
	assert_almost_eq(player.muzzle.global_position.y, player.global_position.y, 0.0001)

func test_a_s_d_do_not_change_neutral_pose_or_add_strafe() -> void:
	var player: Player = await _player()
	var before: Vector2 = player.global_position
	for action in [&"move_left", &"move_down", &"move_right"]:
		Input.action_press(action)
		player._physics_process(1.0 / 60.0)
		Input.action_release(action)
	_release_inputs()

	assert_eq(player.velocity, Vector2.ZERO)
	assert_eq(player.global_position, before)
	assert_eq(player.sprite.animation, &"neutral")

func test_thrust_follows_mouse_heading_and_preserves_inertia() -> void:
	var result := MOTION.calculate_velocity(Vector2(10.0, 0.0), Vector2.DOWN, true, 20.0, 0.0, 150.0, 0.5)

	assert_eq(result, Vector2(10.0, 10.0))

func test_release_uses_friction_and_keeps_heading_of_inertia() -> void:
	var result := MOTION.calculate_velocity(Vector2(10.0, 0.0), Vector2.RIGHT, false, 100.0, 3.0, 150.0, 1.0)

	assert_eq(result, Vector2(7.0, 0.0))

func test_velocity_is_zero_after_blink_state_reset() -> void:
	var player: Player = await _player()
	player.global_position = Vector2(100.0, 100.0)
	player._aim_vector = Vector2.RIGHT
	player.velocity = Vector2(90.0, -20.0)
	Input.action_press(&"aim_right")
	Input.action_press(&"move_up")
	Input.action_press(&"blink")
	player._physics_process(1.0 / 60.0)
	_release_inputs()

	assert_eq(player.velocity, Vector2.ZERO)
	assert_gt(player.global_position.x, 100.0)

func test_blink_with_move_up_pressed_keeps_velocity_zero_for_the_frame() -> void:
	var player: Player = await _player()
	player.global_position = Vector2(100.0, 100.0)
	player._aim_vector = Vector2.RIGHT
	player.velocity = Vector2(90.0, -20.0)
	Input.action_press(&"aim_right")
	Input.action_press(&"move_up")
	Input.action_press(&"blink")
	player._physics_process(1.0 / 60.0)
	_release_inputs()

	assert_eq(player.velocity, Vector2.ZERO)
	assert_eq(player.global_position, Vector2(100.0 + player._stats.get_stat(&"blink_distance"), 100.0))
	assert_eq(player._aim_vector, Vector2.RIGHT)

func test_blink_destination_is_clamped_near_arena_edges() -> void:
	var player: Player = await _blink_player(BASE_SHIP)
	player.set_room_bounds(Rect2(Vector2.ZERO, Vector2(100.0, 80.0)))
	player.global_position = Vector2(12.0, 68.0)
	player._aim_vector = Vector2(-1.0, 1.0).normalized()
	assert_true(player.try_blink(player._aim_vector))

	assert_eq(player.global_position, Vector2(10.0, 70.0))
	assert_eq(player.velocity, Vector2.ZERO)

func test_omni_blink_explicit_direction_has_priority_over_wasd_and_aim() -> void:
	var player: Player = await _blink_player(BRUTA_SHIP)
	player._aim_vector = Vector2.LEFT
	Input.action_press(&"move_up")

	assert_true(player.try_blink(Vector2.RIGHT))

	assert_eq(player.global_position, Vector2(1000.0 + player._stats.get_stat(&"blink_distance"), 1000.0))
	assert_eq(player.velocity, Vector2.ZERO)
	assert_gt(player.blink_cooldown_ratio(), 0.0)

func test_omni_blink_uses_wasd_when_available() -> void:
	var player: Player = await _blink_player(BRUTA_SHIP)
	player._aim_vector = Vector2.LEFT
	Input.action_press(&"move_down")

	assert_true(player.try_blink())

	assert_eq(player.global_position, Vector2(1000.0, 1000.0 + player._stats.get_stat(&"blink_distance")))
	assert_eq(player.velocity, Vector2.ZERO)
	assert_gt(player.blink_cooldown_ratio(), 0.0)

func test_omni_blink_falls_back_to_aim_without_wasd() -> void:
	var player: Player = await _blink_player(BRUTA_SHIP)
	player._aim_vector = Vector2.LEFT

	assert_true(player.try_blink())

	assert_eq(player.global_position, Vector2(1000.0 - player._stats.get_stat(&"blink_distance"), 1000.0))
	assert_eq(player.velocity, Vector2.ZERO)
	assert_gt(player.blink_cooldown_ratio(), 0.0)

func test_aim_forward_blink_uses_aim_even_with_wasd() -> void:
	var player: Player = await _blink_player(BASE_SHIP)
	player._aim_vector = Vector2.UP
	Input.action_press(&"move_right")

	assert_true(player.try_blink())

	assert_eq(player.global_position, Vector2(1000.0, 1000.0 - player._stats.get_stat(&"blink_distance")))
	assert_eq(player.velocity, Vector2.ZERO)
	assert_gt(player.blink_cooldown_ratio(), 0.0)

func test_position_is_clamped_to_arena_bounds() -> void:
	var player: Player = await _player()
	player.set_room_bounds(Rect2(Vector2.ZERO, Vector2(100.0, 80.0)))
	player.global_position = Vector2(-20.0, 120.0)
	player._clamp_to_bounds()

	assert_eq(player.global_position, Vector2(10.0, 70.0))

func test_can_blink_defaults_true_for_other_ships_and_false_for_engineer() -> void:
	assert_true(BASE_SHIP.can_blink)
	assert_true(ShipCatalog.get_ship(&"nave_bruta").can_blink)
	assert_false(ShipCatalog.get_ship(&"nave_engenheira").can_blink)

func test_engineer_shift_does_not_teleport_and_commands_drone_path() -> void:
	var session := _engineer_session()
	var player := PLAYER_SCENE.instantiate() as Player
	player.name = "Player"
	session.add_child(player)
	await get_tree().process_frame
	assert_true(player.configure_ship(ShipCatalog.get_ship(&"nave_engenheira")))
	player.set_room_bounds(Rect2(Vector2.ZERO, Vector2(720.0, 405.0)))
	player.global_position = Vector2(360.0, 200.0)
	player._blink_cd = 0.0
	assert_true(session.deploy_engineer_deployable(player))
	var drone := session._active_room.get_node("Deployables").get_child(0) as EngineerDeployable
	drone.global_position = Vector2.ZERO
	var target_before_shift := drone._target_position
	var before := player.global_position
	Input.action_press(&"move_up")
	Input.action_press(&"aim_up")
	player._physics_process(1.0 / 60.0)
	Input.action_release(&"move_up")
	Input.action_release(&"aim_up")
	assert_ne(player.global_position, before)
	assert_eq(drone._target_position, target_before_shift)
	var target_after_aim := session._engineer_target_for(player)
	Input.action_press(&"blink")
	assert_false(player._handle_blink_input())
	Input.action_release(&"blink")
	assert_ne(player.global_position, before)
	assert_eq(player.global_position, before + player.velocity * (1.0 / 60.0))
	assert_eq(drone._target_position, target_after_aim)
	assert_ne(drone._target_position, target_before_shift)

func test_shift_input_keeps_blink_for_common_ship() -> void:
	var player := await _blink_player(BASE_SHIP)
	var before := player.global_position
	Input.action_press(&"blink")
	assert_true(player._handle_blink_input())
	Input.action_release(&"blink")
	assert_ne(player.global_position, before)

class InputTestSession extends Session:
	func _ready() -> void:
		add_to_group(&"session")
