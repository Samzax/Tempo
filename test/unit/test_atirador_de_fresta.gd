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
	enemy.take_damage(original)
	assert_almost_eq(enemy.health.health, 10.0, 0.001)
	enemy._enter_state(SCRIPT.AttackState.VULNERABLE)
	var vulnerable := _damage(2.0)
	enemy.take_damage(vulnerable)
	assert_almost_eq(enemy.health.health, 4.0, 0.001)
	assert_almost_eq(original.amount, 2.0, 0.001)
	assert_almost_eq(vulnerable.amount, 2.0, 0.001)

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
	enemy.take_damage(chained)
	assert_almost_eq(enemy.health.health, 12.0, 0.001)

func test_locked_direction_remains_the_projectile_direction() -> void:
	var enemy := await _enemy()
	var player := Node2D.new()
	add_child_autofree(player)
	enemy._player = player
	enemy.global_position = Vector2.ZERO
	player.global_position = Vector2.RIGHT * 100.0
	enemy._lock_target()
	var captured: Vector2 = enemy.locked_direction
	player.global_position = Vector2.LEFT * 100.0
	assert_eq(enemy.locked_direction, captured)

func test_drift_enters_from_each_edge_before_using_player_lateral_motion() -> void:
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
		assert_eq(enemy.velocity, edge_case[1] * enemy.drift_speed)

func test_drift_uses_player_lateral_motion_after_entering_room() -> void:
	var enemy := await _enemy()
	var player := Node2D.new()
	add_child_autofree(player)
	enemy._player = player
	enemy.global_position = Vector2(40.0, 100.0)
	player.global_position = Vector2(100.0, 100.0)
	enemy.set_entry_inward(Vector2.RIGHT)
	enemy._has_entered_room = true
	enemy._process_drift()
	assert_almost_eq(enemy.velocity.x, 0.0, 0.001)
	assert_almost_eq(enemy.velocity.y, enemy.drift_speed, 0.001)

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
