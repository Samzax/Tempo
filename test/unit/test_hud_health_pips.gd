extends GutTest

const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const BRUTA := preload("res://resources/ships/bruta.tres")
const RASTREADORA := preload("res://resources/ships/rastreadora.tres")
const FULL_COLOR := Color(1.0, 0.3, 0.35)
const EMPTY_COLOR := Color(0.25, 0.25, 0.3)


func _hud() -> Control:
	var hud := HUD_SCENE.instantiate() as Control
	add_child_autofree(hud)
	await get_tree().process_frame
	return hud


func _player(ship: ShipDef) -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
	player.ship = ship
	add_child_autofree(player)
	await get_tree().process_frame
	return player


func _pip_count(hud: Control) -> int:
	return hud._pips_row.get_child_count()


func test_hud_with_bruta_shows_exactly_five_pips() -> void:
	var hud := await _hud()
	var player := await _player(BRUTA)

	hud._bind_player(player)

	assert_eq(_pip_count(hud), 5)
	assert_eq(hud._pips.size(), 5)

func test_hud_uses_charge_indicator_for_bruta_and_blink_for_common_ship() -> void:
	var hud := await _hud()
	var bruta_player := await _player(BRUTA)
	hud._bind_player(bruta_player)
	hud._process(0.0)
	assert_true(hud._blink_icon.use_charge_indicator)

	var common_player := await _player(RASTREADORA)
	hud._bind_player(common_player)
	hud._process(0.0)
	assert_false(hud._blink_icon.use_charge_indicator)


func test_hud_with_rastreadora_shows_exactly_two_pips() -> void:
	var hud := await _hud()
	var player := await _player(RASTREADORA)

	hud._bind_player(player)

	assert_eq(_pip_count(hud), 2)
	assert_eq(hud._pips.size(), 2)


func test_health_capacity_changed_rebuilds_without_duplicate_pips() -> void:
	var hud := await _hud()
	var player := await _player(BRUTA)
	hud._bind_player(player)

	player.health_capacity_changed.emit(2.0)
	assert_eq(_pip_count(hud), 2)
	assert_eq(hud._pips.size(), 2)

	player.health_capacity_changed.emit(5.0)
	assert_eq(_pip_count(hud), 5)
	assert_eq(hud._pips.size(), 5)


func test_hud_ready_before_player_late_binds_and_reads_capacity() -> void:
	var hud := await _hud()
	assert_null(hud._player)
	assert_eq(_pip_count(hud), 0)

	var player := await _player(RASTREADORA)
	await get_tree().process_frame

	assert_eq(hud._player, player)
	assert_eq(_pip_count(hud), 2)
	assert_true(player.health_capacity_changed.is_connected(hud._on_player_health_capacity_changed))


func test_pip_colors_reflect_current_health() -> void:
	var hud := await _hud()
	var player := await _player(BRUTA)
	hud._bind_player(player)
	player.health.health = 2.0
	hud._process(0.0)

	assert_eq(hud._pips[0].color, FULL_COLOR)
	assert_eq(hud._pips[1].color, FULL_COLOR)
	assert_eq(hud._pips[2].color, EMPTY_COLOR)
	assert_eq(hud._pips[4].color, EMPTY_COLOR)


func test_invisible_hud_does_not_poll_or_change_pips() -> void:
	var hud := await _hud()
	var player := await _player(BRUTA)
	hud._bind_player(player)
	var initial_colors: Array[Color] = []
	for pip: ColorRect in hud._pips:
		initial_colors.append(pip.color)
	hud.hide()
	player.health.health = 1.0

	await get_tree().process_frame
	hud._process(0.0)

	assert_false(hud.visible)
	for index in initial_colors.size():
		assert_eq(hud._pips[index].color, initial_colors[index])
	assert_eq(_pip_count(hud), 5)
