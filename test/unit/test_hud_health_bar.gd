extends GutTest

const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const ENEMY_SCENE := preload("res://scenes/enemies/enemy.tscn")
const BRUTA := preload("res://resources/ships/bruta.tres")
const RASTREADORA := preload("res://resources/ships/rastreadora.tres")


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


func _enemy() -> Enemy:
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	add_child_autofree(enemy)
	await get_tree().process_frame
	return enemy


func test_public_hud_has_no_gut_addon_dependency() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	assert_false(source.contains("res://addons/gut"))
	var hud := await _hud()
	assert_not_null(hud)
	assert_not_null(hud._hp_bar)
	assert_not_null(hud._hp_label)
	assert_not_null(hud._hp_row)
	assert_false("_pips" in hud)
	assert_false("_pips_row" in hud)


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


func test_hud_with_bruta_shows_full_health_bar_and_ratio() -> void:
	var hud := await _hud()
	var player := await _player(BRUTA)

	hud._bind_player(player)

	assert_eq(hud._hp_label.text, "500 / 500")
	assert_true(is_equal_approx(hud._hp_bar.ratio, 1.0))


func test_hud_health_damage_updates_ratio_and_label() -> void:
	var hud := await _hud()
	var player := await _player(BRUTA)
	hud._bind_player(player)

	player.health.health = 340
	hud._process(0.0)
	assert_eq(hud._hp_label.text, "340 / 500")
	assert_true(is_equal_approx(hud._hp_bar.ratio, 0.68))

	player.health.health = 60
	hud._process(0.0)
	assert_eq(hud._hp_label.text, "60 / 500")
	assert_true(is_equal_approx(hud._hp_bar.ratio, 0.12))


func test_hud_with_rastreadora_shows_proportional_bar() -> void:
	var hud := await _hud()
	var player := await _player(RASTREADORA)

	hud._bind_player(player)

	assert_eq(hud._hp_label.text, "200 / 200")
	assert_true(is_equal_approx(hud._hp_bar.ratio, 1.0))


func test_health_capacity_changed_updates_label_without_duplicating_nodes() -> void:
	var hud := await _hud()
	var player := await _player(BRUTA)
	hud._bind_player(player)

	assert_eq(hud._hp_row.get_child_count(), 2)
	assert_eq(hud._hp_label.text, "500 / 500")

	player.health.max_health = 200
	player.health.health = mini(player.health.health, player.health.max_health)
	player.health_capacity_changed.emit(200)

	assert_eq(hud._hp_row.get_child_count(), 2)
	assert_eq(hud._hp_label.text, "200 / 200")
	assert_true(is_equal_approx(hud._hp_bar.ratio, 1.0))

	player.health.max_health = 500
	player.health.health = 500
	player.health_capacity_changed.emit(500)

	assert_eq(hud._hp_row.get_child_count(), 2)
	assert_eq(hud._hp_label.text, "500 / 500")
	assert_true(is_equal_approx(hud._hp_bar.ratio, 1.0))


func test_hud_ready_before_player_late_binds_and_reads_bar() -> void:
	var hud := await _hud()
	assert_null(hud._player)
	assert_eq(hud._hp_row.get_child_count(), 2)

	var player := await _player(RASTREADORA)
	await get_tree().process_frame

	assert_eq(hud._player, player)
	assert_eq(hud._hp_label.text, "200 / 200")
	assert_true(is_equal_approx(hud._hp_bar.ratio, 1.0))
	assert_true(player.health_capacity_changed.is_connected(hud._on_player_health_capacity_changed))


func test_invisible_hud_does_not_poll_or_change_bar() -> void:
	var hud := await _hud()
	var player := await _player(BRUTA)
	hud._bind_player(player)
	assert_eq(hud._hp_label.text, "500 / 500")
	assert_true(is_equal_approx(hud._hp_bar.ratio, 1.0))

	hud.hide()
	player.health.health = 100

	await get_tree().process_frame
	hud._process(0.0)

	assert_false(hud.visible)
	assert_eq(hud._hp_label.text, "500 / 500")
	assert_true(is_equal_approx(hud._hp_bar.ratio, 1.0))


func test_enemy_health_bar_contract_redraw_and_visibility() -> void:
	var enemy := await _enemy()
	assert_not_null(enemy)
	assert_not_null(enemy.health)
	assert_true(enemy.health.damaged.is_connected(enemy._on_health_damaged))
	assert_eq(enemy.health.health, enemy.health.max_health)

	# 1. Vida cheia: _draw() descarta desenho (health == max_health)
	enemy._draw()

	# 2. Dano parcial: dispara sinal health.damaged, queue_redraw e rect proporcional em [16, 40]
	watch_signals(enemy.health)
	var info := DamageInfo.new()
	info.amount = 100
	var damage_taken := enemy.take_damage(info)
	assert_gt(damage_taken, 0)
	assert_signal_emitted(enemy.health, "damaged")
	assert_true(enemy.health.health > 0 and enemy.health.health < enemy.health.max_health)

	var bar_rect: Rect2 = enemy._health_bar_rect()
	assert_between(bar_rect.size.x, 16.0, 40.0)
	assert_eq(bar_rect.size.y, 3.0)

	# 3. Morte / vida zerada: _draw() descarta desenho (health <= 0)
	enemy.health.health = 0
	enemy._draw()
