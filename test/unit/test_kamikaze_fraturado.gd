extends GutTest

const SCENE := preload("res://scenes/enemies/kamikaze_fraturado.tscn")
const SCRIPT := preload("res://scripts/enemies/kamikaze_fraturado.gd")

func _enemy() -> Node:
	var enemy := SCENE.instantiate()
	add_child_autofree(enemy)
	await get_tree().process_frame
	return enemy

func test_telegraph_is_point_four_five_seconds() -> void:
	var enemy := await _enemy()
	enemy._enter_state(SCRIPT.AttackState.TELEGRAPH)
	assert_eq(enemy.telegraph_duration, 0.45)
	enemy._physics_process(0.44)
	assert_eq(enemy.attack_state, SCRIPT.AttackState.TELEGRAPH)
	enemy._physics_process(0.01)
	assert_eq(enemy.attack_state, SCRIPT.AttackState.DASH)

func test_dash_direction_is_captured_once_without_homing() -> void:
	var enemy := await _enemy()
	var player := Node2D.new()
	add_child_autofree(player)
	enemy._player = player
	enemy.global_position = Vector2.ZERO
	player.global_position = Vector2.RIGHT * 100.0
	enemy._enter_state(SCRIPT.AttackState.TELEGRAPH)
	enemy._physics_process(0.46)
	assert_eq(enemy.attack_state, SCRIPT.AttackState.DASH)
	var captured: Vector2 = enemy.dash_direction
	player.global_position = Vector2.LEFT * 100.0
	enemy._physics_process(0.01)
	assert_eq(enemy.dash_direction, captured)
	assert_eq(enemy.velocity.normalized(), captured.normalized())

func test_death_adds_only_existing_burst_feedback() -> void:
	var enemy := await _enemy()
	var effects := Node2D.new()
	effects.add_to_group("effects")
	add_child_autofree(effects)
	enemy._effects = effects
	enemy._on_died(DamageInfo.new())
	# Duas rajadas deslocadas representam os fragmentos; a terceira e a
	# explosao normal da classe Enemy.
	assert_eq(effects.get_child_count(), 3)
