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

	player.health.health = 1.0
	assert_true(player.configure_ship(BRUTA))
	assert_almost_eq(player.health.max_health, 5.0, 0.0001)
	assert_almost_eq(player.health.health, 5.0, 0.0001)
	assert_signal_emitted_with_parameters(player, &"health_capacity_changed", [5.0])

	player.health.health = 1.0
	assert_true(player.configure_ship(RASTREADORA))
	assert_almost_eq(player.health.max_health, 2.0, 0.0001)
	assert_almost_eq(player.health.health, 2.0, 0.0001)
	assert_signal_emitted_with_parameters(player, &"health_capacity_changed", [2.0])
	assert_signal_emit_count(player, &"health_capacity_changed", 2)
	assert_signal_emitted_with_parameters(player, &"health_capacity_changed", [2.0])
	assert_signal_emit_count(player, &"health_capacity_changed", 2)


func test_sandbox_max_health_override_emits_and_clamps_current_health() -> void:
	var player := await _player()
	watch_signals(player)
	player.health.health = player.health.max_health

	assert_true(player.sandbox_set_stat_override(&"max_health", 2.0))
	assert_almost_eq(player.health.max_health, 2.0, 0.0001)
	assert_almost_eq(player.health.health, 2.0, 0.0001)
	assert_signal_emitted_with_parameters(player, &"health_capacity_changed", [2.0])


func test_capacity_signal_is_absent_when_effective_max_health_does_not_change() -> void:
	var player := await _player()
	watch_signals(player)
	var current_max := player.health.max_health

	assert_true(player.sandbox_set_stat_override(&"max_health", current_max))
	assert_signal_not_emitted(player, &"health_capacity_changed")


func test_loadout_switch_resets_health_to_max_when_capacity_is_reduced() -> void:
	var player := await _player()
	watch_signals(player)

	assert_true(player.configure_ship(BRUTA))
	player.health.health = 1.0
	assert_true(player.configure_ship(RASTREADORA))

	assert_almost_eq(player.health.max_health, 2.0, 0.0001)
	assert_almost_eq(player.health.health, 2.0, 0.0001)
