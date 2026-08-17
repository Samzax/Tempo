extends GutTest

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const HEALTH_UNITS := preload("res://scripts/components/health_units.gd")

func _player() -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	await get_tree().process_frame
	return player

func _damage(amount: float) -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = HEALTH_UNITS.from_hp(amount)
	return info

func test_apply_stun_reports_active_and_reapplication_keeps_maximum_remaining_duration() -> void:
	var player := await _player()

	player.apply_stun(0.5)
	assert_true(player.is_stunned())
	player._physics_process(0.2)
	assert_true(player.is_stunned())
	player.apply_stun(0.1)
	player._physics_process(0.2)
	assert_true(player.is_stunned())
	player._physics_process(0.1)
	assert_false(player.is_stunned())

func test_stun_expires_on_physics_tick_and_blocks_controlled_movement_while_active() -> void:
	var player := await _player()
	player.velocity = Vector2.RIGHT * 100.0
	player.apply_stun(0.2)
	player._physics_process(0.1)

	assert_true(player.is_stunned())
	assert_eq(player.velocity, Vector2.ZERO)

	player._physics_process(0.1)
	assert_false(player.is_stunned())

func test_stun_does_not_change_health_or_add_damage_iframes() -> void:
	var player := await _player()
	GameState.player_lives = 3
	player.apply_stun(1.0)

	assert_eq(player.take_damage(_damage(1.0)), 100)
	assert_eq(player.health.health, 200)
	assert_false(player.is_invulnerable())
	assert_eq(player.take_damage(_damage(1.0)), 100)
	assert_eq(player.health.health, 100)
	assert_false(player.is_invulnerable())
