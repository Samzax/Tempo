extends GutTest

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const BASE_SHIP := preload("res://resources/ships/base.tres")

var _root: Node2D
var _projectiles: Node2D
var _player: Player

func before_each() -> void:
	_root = Node2D.new()
	add_child_autofree(_root)
	_projectiles = Node2D.new()
	_projectiles.add_to_group("projectiles")
	_root.add_child(_projectiles)
	_player = PLAYER_SCENE.instantiate() as Player
	_player.position = Vector2(120.0, 100.0)
	_root.add_child(_player)
	await get_tree().process_frame

func after_each() -> void:
	for action in [&"aim_left", &"aim_right", &"aim_up", &"aim_down", &"shoot"]:
		Input.action_release(action)

func _mouse_at(position: Vector2) -> void:
	get_viewport().warp_mouse(position)
	await get_tree().process_frame

func test_fire_direction_uses_muzzle_origin_and_differs_from_player_origin() -> void:
	_player.muzzle.position = Vector2(20.0, 10.0)
	await _mouse_at(Vector2(260.0, 180.0))
	_player._joypad_aim_was_active = false
	var expected := (_mouse_at_global() - _player.muzzle.global_position).normalized()
	var from_player := (_mouse_at_global() - _player.global_position).normalized()

	_player._fire()
	assert_eq(_projectiles.get_child_count(), 1)
	var bullet := _projectiles.get_child(0)
	assert_true(bullet._active)
	assert_true(bullet.global_position.is_equal_approx(_player.muzzle.global_position))
	assert_true(bullet._velocity.normalized().is_equal_approx(expected))
	assert_gt(expected.dot(from_player), -1.0)
	assert_gt(expected.distance_to(from_player), 0.01)

func _mouse_at_global() -> Vector2:
	return _player.get_global_mouse_position()

func test_fire_direction_falls_back_to_aim_vector_when_mouse_coincides_with_muzzle() -> void:
	_player._aim_vector = Vector2.LEFT
	_player._joypad_aim_was_active = false
	await _mouse_at(_player.muzzle.global_position)

	assert_true(_player._fire_direction_from_muzzle().is_equal_approx(Vector2.LEFT))

func test_visual_aim_crosses_real_wrap_boundary_by_finite_shortest_progress() -> void:
	_player._visual_aim_global_angle = -PI + 0.1
	_player._aim_vector = Vector2.RIGHT.rotated(PI / 2.0 - 0.1)
	var before := _player._visual_aim_global_angle

	_player._update_visual_aim(0.1)
	var after := _player._visual_aim_global_angle

	assert_true(is_finite(after))
	assert_gt(absf(angle_difference(before, after)), 0.0)
	assert_lt(absf(angle_difference(after, PI - 0.1)), absf(angle_difference(before, PI - 0.1)))

func test_physical_rotation_and_real_reset_then_visual_aim_do_not_zero_visual_rotation() -> void:
	await _mouse_at(_player.global_position + Vector2.RIGHT * 180.0)
	_player._visual_aim_global_angle = 0.0
	_player.rotation = 0.0
	var before := _player.visual_root.global_rotation
	var target := PI / 2.0

	_player._physics_process(0.1)
	var after := _player.visual_root.global_rotation

	assert_true(is_finite(after))
	assert_gt(absf(angle_difference(before, after)), 0.001)
	assert_gt(absf(angle_difference(before, target)), absf(angle_difference(after, target)))
	assert_gt(absf(angle_difference(after, target)), 0.001)

func test_bruta_omni_does_not_receive_visual_aim() -> void:
	var omni := BASE_SHIP.duplicate(true) as ShipDef
	omni.movement_style = "omni"
	assert_true(_player.configure_ship(omni))
	_player.visual_root.rotation = 0.37
	_player._aim_vector = Vector2.LEFT

	_player._update_visual_aim(0.25)

	assert_almost_eq(_player.visual_root.rotation, 0.37, 0.00001)

func test_active_joystick_owns_aim_and_mouse_returns_after_stick_release() -> void:
	await _mouse_at(Vector2(300.0, 200.0))
	Input.action_press("aim_right", 1.0)
	var mouse_motion := InputEventMouseMotion.new()
	mouse_motion.position = Vector2(40.0, 40.0)
	_player._input(mouse_motion)
	_player._update_aim()

	assert_eq(_player._last_aim_source, Player.AimSource.JOYPAD)
	assert_true(_player._joypad_aim_was_active)
	assert_true(_player._aim_vector.is_equal_approx(Vector2.RIGHT))
	_player._fire()
	var joystick_bullet := _projectiles.get_child(0)
	assert_true(joystick_bullet._velocity.normalized().is_equal_approx(Vector2.RIGHT))

	Input.action_release("aim_right")
	_player._update_aim()

	assert_eq(_player._last_aim_source, Player.AimSource.MOUSE)
	assert_false(_player._joypad_aim_was_active)
	_player._fire()
	var mouse_bullet := _projectiles.get_child(1)
	var mouse_direction := (_mouse_at_global() - _player.muzzle.global_position).normalized()
	assert_true(mouse_bullet._velocity.normalized().is_equal_approx(mouse_direction))
	assert_false(mouse_bullet._velocity.normalized().is_equal_approx(Vector2.RIGHT))
