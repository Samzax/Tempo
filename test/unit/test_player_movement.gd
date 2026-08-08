extends GutTest

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const MOTION := preload("res://scripts/player/asteroids_motion.gd")

func _player() -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	await get_tree().process_frame
	return player

func _release_inputs() -> void:
	for action in [&"aim_right", &"move_left", &"move_down", &"move_right", &"move_up", &"blink"]:
		Input.action_release(action)

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
	assert_eq(player.global_position, Vector2(190.0, 100.0))
	assert_eq(player._aim_vector, Vector2.RIGHT)

func test_blink_destination_is_clamped_near_arena_edges() -> void:
	var player: Player = await _player()
	player.set_room_bounds(Rect2(Vector2.ZERO, Vector2(100.0, 80.0)))
	player.global_position = Vector2(12.0, 68.0)
	player._aim_vector = Vector2(-1.0, 1.0).normalized()
	Input.action_press(&"aim_right")
	Input.action_press(&"blink")
	player._physics_process(1.0 / 60.0)
	_release_inputs()

	assert_eq(player.global_position, Vector2(90.0, 68.0))
	assert_eq(player.velocity, Vector2.ZERO)

func test_position_is_clamped_to_arena_bounds() -> void:
	var player: Player = await _player()
	player.set_room_bounds(Rect2(Vector2.ZERO, Vector2(100.0, 80.0)))
	player.global_position = Vector2(-20.0, 120.0)
	player._clamp_to_bounds()

	assert_eq(player.global_position, Vector2(10.0, 70.0))
