extends GutTest

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const BRUTA := preload("res://resources/ships/bruta.tres")
const RASTREADORA := preload("res://resources/ships/rastreadora.tres")


func _player() -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	await get_tree().process_frame
	return player


func test_loadout_switch_emits_capacity_and_resets_health_to_bruta_and_rastreadora() -> void:
	var player := await _player()
	watch_signals(player)

	player.health.health = 100
	assert_true(player.configure_ship(BRUTA))
	assert_eq(player.health.max_health, 500)
	assert_eq(player.health.health, 500)
	assert_signal_emitted_with_parameters(player, &"health_capacity_changed", [500])

	player.health.health = 100
	assert_true(player.configure_ship(RASTREADORA))
	assert_eq(player.health.max_health, 200)
	assert_eq(player.health.health, 200)
	assert_signal_emitted_with_parameters(player, &"health_capacity_changed", [200])
	assert_signal_emit_count(player, &"health_capacity_changed", 2)
	assert_signal_emitted_with_parameters(player, &"health_capacity_changed", [200])
	assert_signal_emit_count(player, &"health_capacity_changed", 2)


func test_sandbox_max_health_override_emits_and_clamps_current_health() -> void:
	var player := await _player()
	watch_signals(player)
	player.health.health = player.health.max_health

	assert_true(player.sandbox_set_stat_override(&"max_health", 2.0))
	assert_eq(player.health.max_health, 200)
	assert_eq(player.health.health, 200)
	assert_signal_emitted_with_parameters(player, &"health_capacity_changed", [200])


func test_sandbox_max_health_override_has_no_universal_maximum() -> void:
	var player := await _player()
	const LARGE_HP := 100001.0

	assert_true(player.sandbox_set_stat_override(&"max_health", LARGE_HP))
	assert_eq(player.health.max_health, 10000100)
	assert_eq(player._stats.get_stat(&"max_health"), LARGE_HP)


func test_capacity_signal_is_absent_when_effective_max_health_does_not_change() -> void:
	var player := await _player()
	watch_signals(player)
	var current_max := player.health.max_health

	assert_true(player.sandbox_set_stat_override(&"max_health", float(current_max) / 100.0))
	assert_signal_not_emitted(player, &"health_capacity_changed")


func test_loadout_switch_resets_health_to_max_when_capacity_is_reduced() -> void:
	var player := await _player()
	watch_signals(player)

	assert_true(player.configure_ship(BRUTA))
	player.health.health = 100
	assert_true(player.configure_ship(RASTREADORA))

	assert_eq(player.health.max_health, 200)
	assert_eq(player.health.health, 200)
