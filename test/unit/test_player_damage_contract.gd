extends GutTest

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

func _player() -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	await get_tree().process_frame
	return player

func _damage(amount: float) -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = amount
	return info

func test_danos_comuns_consecutivos_acumulam_e_publicam_cada_acerto() -> void:
	var player := await _player()
	GameState.player_lives = 3
	watch_signals(EventBus)
	var initial_health := player.health.health

	player.take_damage(_damage(0.5))
	player.take_damage(_damage(0.75))

	assert_almost_eq(player.health.health, initial_health - 1.25, 0.001)
	assert_false(player.is_invulnerable())
	assert_signal_emit_count(EventBus, &"player_hit", 2)

func test_invulnerabilidade_deliberada_bloqueia_sem_consumir_vida() -> void:
	var player := await _player()
	GameState.player_lives = 3
	var initial_health := player.health.health

	player.grant_invuln(10.0)
	player.take_damage(_damage(1.0))

	assert_true(player.is_invulnerable())
	assert_almost_eq(player.health.health, initial_health, 0.001)
	assert_eq(GameState.player_lives, 3)

func test_carga_de_escudo_absorve_um_acerto_e_o_seguinte_passa() -> void:
	var player := await _player()
	var initial_health := player.health.health
	player.grant_shield_charge(&"teste")

	player.take_damage(_damage(1.0))
	assert_almost_eq(player.health.health, initial_health, 0.001)

	player.take_damage(_damage(1.0))
	assert_almost_eq(player.health.health, initial_health - 1.0, 0.001)

func test_protecao_de_respawn_impede_consumo_multiplo_de_vidas_na_mesma_sequencia() -> void:
	var player := await _player()
	GameState.player_lives = 3
	player.health.health = 1.0

	player.take_damage(_damage(1.0))
	assert_eq(GameState.player_lives, 2)
	assert_true(player.is_invulnerable())
	player.take_damage(_damage(1.0))

	assert_eq(GameState.player_lives, 2)
	assert_almost_eq(player.health.health, player.health.max_health, 0.001)
