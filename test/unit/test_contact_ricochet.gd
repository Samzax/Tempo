extends GutTest

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const ENEMY_SCENE := preload("res://scenes/enemies/enemy.tscn")
const DEBRIS_SCENE := preload("res://scenes/world/debris.tscn")
const ATIRADOR_SCENE := preload("res://scenes/enemies/atirador_de_fresta.tscn")
const BRUTA := preload("res://resources/ships/bruta.tres")
const RESOLVER := preload("res://scripts/combat/collision_impact_resolver.gd")
const HEALTH_UNITS := preload("res://scripts/components/health_units.gd")
const RICOCHET_PATH := "res://scripts/combat/contact_ricochet.gd"

## Corpo de teste com massa e canal de knockback declarados pelo contrato.
class RicochetStub extends CharacterBody2D:
	var knockback_calls: Array[Vector2] = []
	var knockback_total := Vector2.ZERO
	var mass := 1.0
	var push_velocity := false

	func get_collision_mass() -> float:
		return mass

	func apply_collision_knockback(impulse: Vector2) -> void:
		knockback_calls.append(impulse)
		knockback_total += impulse
		if push_velocity:
			velocity += impulse

var _saved_lives := 3
var _final_x := 0.0

func before_each() -> void:
	ContactRicochet.clear_all_state()
	_saved_lives = GameState.player_lives
	GameState.player_lives = 9
	_final_x = 0.0

func after_each() -> void:
	ContactRicochet.clear_all_state()
	GameState.player_lives = _saved_lives

func _contact_player() -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	player.set_physics_process(false)
	return player

func _bruta_player() -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
	player.ship = BRUTA
	add_child_autofree(player)
	await get_tree().process_frame
	player.set_physics_process(false)
	return player

func _enemy(position: Vector2) -> Enemy:
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	add_child_autofree(enemy)
	enemy.set_physics_process(false)
	enemy.set_room_cull_policy(RoomDef.CullPolicy.NONE)
	enemy.global_position = position
	return enemy

func _debris(position: Vector2) -> RigidBody2D:
	var debris := DEBRIS_SCENE.instantiate() as RigidBody2D
	debris.freeze = true
	debris.global_position = position
	add_child_autofree(debris)
	return debris

func _static_body(position: Vector2, radius: float) -> StaticBody2D:
	var body := StaticBody2D.new()
	var collision := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	collision.shape = circle
	body.add_child(collision)
	body.collision_layer = CollisionLayers.WORLD
	body.collision_mask = CollisionLayers.PLAYER
	add_child_autofree(body)
	body.global_position = position
	return body

func _stub(layer: int, mask: int, position: Vector2) -> RicochetStub:
	var stub := RicochetStub.new()
	var collision := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 10.0
	collision.shape = circle
	stub.add_child(collision)
	add_child_autofree(stub)
	stub.set_physics_process(false)
	stub.collision_layer = layer
	stub.collision_mask = mask
	stub.global_position = position
	return stub

## Empurra o movel contra o obstaculo por seis ticks fisicos.
func _push(mover: CharacterBody2D, obstacle: Node2D, obstacle_x: float) -> void:
	mover.global_position = Vector2.ZERO
	obstacle.global_position = Vector2(obstacle_x, 0.0)
	mover.velocity = Vector2.RIGHT * 1200.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	for _step in range(6):
		mover.move_and_slide()
		await get_tree().physics_frame
	_final_x = mover.global_position.x

## Prepara o par, rola o contato e resolve no mesmo quadro fisico.
func _slide_and_resolve(mover: RicochetStub, target: RicochetStub, speed: float) -> void:
	mover.velocity = Vector2.RIGHT * speed
	target.velocity = Vector2.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame
	ContactRicochet.prepare(mover)
	mover.move_and_slide()
	ContactRicochet.restore_after_slide(mover)
	ContactRicochet.resolve(mover)

func _record_damage(info: DamageInfo, _actual_drop: int, sink: Array) -> void:
	sink.append(info.amount)

## Monta o contato D5 com 16.5 px: dentro da margem nova (11 + 7 = 18) e fora
## da margem antiga (8 + 7 = 15).
func _damage_scenario(enemy_first: bool) -> Dictionary:
	var enemy: Enemy
	var player: Player
	if enemy_first:
		enemy = _enemy(Vector2.ZERO)
		player = _contact_player()
	else:
		player = _contact_player()
		enemy = _enemy(Vector2.ZERO)
	player.global_position = Vector2.ZERO
	enemy.global_position = Vector2(16.5, 0.0)
	player.velocity = Vector2.RIGHT * 100.0
	enemy.velocity = Vector2.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame
	var sink: Array = []
	enemy.health.damaged.connect(_record_damage.bind(sink))
	return {"player": player, "enemy": enemy, "hits": sink}

func _assert_single_touch(sink: Array, player: Player) -> void:
	RESOLVER.resolve_overlaps(player, player._collision_impact_pairs)
	assert_eq(sink.size(), 1, "o contato dentro da margem D5 danifica uma unica vez")
	RESOLVER.resolve_overlaps(player, player._collision_impact_pairs)
	assert_eq(sink.size(), 1, "repetir a leitura nao redanifica")
	player._collision_impact_pairs.clear()
	RESOLVER.resolve_overlaps(player, player._collision_impact_pairs)
	assert_eq(sink.size(), 2, "retocar o par rearma o dano")

## Inimigo real de raio 12 (>= 11), usado para conferir o escopo da margem D5.
func _atirador(position: Vector2) -> Enemy:
	var enemy := ATIRADOR_SCENE.instantiate() as Enemy
	add_child_autofree(enemy)
	enemy.set_physics_process(false)
	enemy.set_room_cull_policy(RoomDef.CullPolicy.NONE)
	enemy.global_position = position
	return enemy

## Prepara, desliza e restaura na ordem do tick real, dentro do mesmo quadro.
func _tick_prepare_slide(body: CharacterBody2D, speed: float) -> void:
	body.velocity = Vector2.RIGHT * speed
	ContactRicochet.prepare(body)
	body.move_and_slide()
	ContactRicochet.restore_after_slide(body)

## Contatos do ultimo deslizamento que apontam para o corpo pedido.
func _slide_hits_on(body: CharacterBody2D, other: Node) -> int:
	var hits := 0
	for index in body.get_slide_collision_count():
		if body.get_slide_collision(index).get_collider() == other:
			hits += 1
	return hits

func test_cenas_declaram_mascaras_de_contato_do_contrato() -> void:
	var player := _contact_player()
	var enemy := _enemy(Vector2.ZERO)
	var debris := _debris(Vector2.ZERO)

	assert_eq(player.collision_mask, CollisionLayers.WORLD | CollisionLayers.PLAYER | CollisionLayers.ENEMY)
	assert_eq(enemy.collision_mask, CollisionLayers.PLAYER | CollisionLayers.ENEMY)
	assert_eq(enemy.collision_layer, CollisionLayers.ENEMY)
	assert_eq(debris.collision_layer, CollisionLayers.WORLD)
	assert_eq(debris.collision_mask, CollisionLayers.PLAYER)

func test_jogador_trava_no_inimigo_pela_mascara_mutua() -> void:
	var player := _contact_player()
	var enemy := _enemy(Vector2(60.0, 0.0))
	await _push(player, enemy, 60.0)
	assert_gt(_final_x, 0.0, "o jogador avanca ate o contato")
	assert_lt(_final_x, 60.0, "o jogador nao atravessa o inimigo")

func test_inimigo_trava_no_jogador_pela_mascara_mutua() -> void:
	var player := _contact_player()
	var enemy := _enemy(Vector2(60.0, 0.0))
	await _push(enemy, player, 60.0)
	assert_gt(_final_x, 0.0, "o inimigo avanca ate o contato")
	assert_lt(_final_x, 60.0, "o inimigo nao atravessa o jogador")

func test_inimigos_travam_entre_si() -> void:
	var first := _enemy(Vector2.ZERO)
	var second := _enemy(Vector2(60.0, 0.0))
	await _push(first, second, 60.0)
	assert_gt(_final_x, 0.0, "o primeiro inimigo avanca ate o contato")
	assert_lt(_final_x, 60.0, "inimigos nao se atravessam")

func test_jogador_trava_no_debris_pelo_bit_de_mundo() -> void:
	var player := _contact_player()
	var debris := _debris(Vector2(60.0, 0.0))
	await _push(player, debris, 60.0)
	assert_gt(_final_x, 0.0, "o jogador avanca ate o contato")
	assert_lt(_final_x, 60.0, "o jogador nao atravessa o debris")

func test_inimigo_atravessa_debris_sem_bit_de_mundo() -> void:
	var enemy := _enemy(Vector2.ZERO)
	var debris := _debris(Vector2(60.0, 0.0))
	await _push(enemy, debris, 60.0)
	assert_gt(_final_x, 60.0, "sem bit de mundo o inimigo segue reto")

func test_formula_de_impulso_reparte_massa_com_restituicao_aprovada() -> void:
	var impulse := ContactRicochet.compute_impulse(
		Vector2.RIGHT * 100.0, Vector2.ZERO, Vector2.RIGHT, 1.0, 1.0)
	assert_true(impulse[&"applied"])
	assert_almost_eq(float(impulse[&"j"]), 92.5, 0.0001)
	var delta_a: Vector2 = impulse[&"da"]
	var delta_b: Vector2 = impulse[&"db"]
	assert_almost_eq(delta_a.x, -92.5, 0.0001)
	assert_almost_eq(delta_b.x, 92.5, 0.0001)
	assert_almost_eq(delta_a.y + delta_b.y, 0.0, 0.0001)

	var heavy := ContactRicochet.compute_impulse(
		Vector2.RIGHT * 100.0, Vector2.ZERO, Vector2.RIGHT, 6.0, 1.0)
	assert_true(heavy[&"applied"])
	var heavy_a: Vector2 = heavy[&"da"]
	var heavy_b: Vector2 = heavy[&"db"]
	assert_lt(absf(heavy_a.x), absf(heavy_b.x), "o corpo leve recebe mais delta")

func test_formula_sem_fechamento_nao_aplica_impulso() -> void:
	var separating := ContactRicochet.compute_impulse(
		Vector2.RIGHT * 50.0, Vector2.RIGHT * 90.0, Vector2.RIGHT, 1.0, 1.0)
	assert_false(separating[&"applied"])
	var co_moving := ContactRicochet.compute_impulse(
		Vector2.RIGHT * 80.0, Vector2.RIGHT * 80.0, Vector2.RIGHT, 1.0, 1.0)
	assert_false(co_moving[&"applied"])
	var degenerate := ContactRicochet.compute_impulse(
		Vector2.RIGHT * 80.0, Vector2.ZERO, Vector2.ZERO, 1.0, 1.0)
	assert_false(degenerate[&"applied"])

func test_impulso_unico_por_par_por_frame_fisico() -> void:
	var mover := _stub(
		CollisionLayers.PLAYER,
		CollisionLayers.PLAYER | CollisionLayers.ENEMY,
		Vector2.ZERO)
	var target := _stub(
		CollisionLayers.ENEMY,
		CollisionLayers.PLAYER | CollisionLayers.ENEMY,
		Vector2(20.5, 0.0))
	await _slide_and_resolve(mover, target, 100.0)

	assert_eq(mover.knockback_calls.size(), 1, "um impulso proprio por frame")
	assert_eq(target.knockback_calls.size(), 1, "um impulso no alvo por frame")

	ContactRicochet.resolve(mover)
	assert_eq(mover.knockback_calls.size(), 1, "resolver de novo no mesmo frame e no-op")
	assert_eq(target.knockback_calls.size(), 1, "o par permanece gasto no frame")

	ContactRicochet.clear_all_state()
	mover.velocity = Vector2.RIGHT * 100.0
	ContactRicochet.prepare(mover)
	mover.move_and_slide()
	ContactRicochet.restore_after_slide(mover)
	ContactRicochet.resolve(mover)
	assert_eq(mover.knockback_calls.size(), 2, "quadro novo rearma o par")
	assert_eq(target.knockback_calls.size(), 2, "quadro novo rearma o alvo")

func test_ricochete_frontal_conserva_a_restituicao_aprovada() -> void:
	var mover := _stub(
		CollisionLayers.PLAYER,
		CollisionLayers.PLAYER | CollisionLayers.ENEMY,
		Vector2.ZERO)
	var target := _stub(
		CollisionLayers.ENEMY,
		CollisionLayers.PLAYER | CollisionLayers.ENEMY,
		Vector2(20.5, 0.0))
	await _slide_and_resolve(mover, target, 100.0)

	var relative := (mover.velocity - (target.velocity + target.knockback_total)).dot(Vector2.RIGHT)
	assert_almost_eq(relative, -85.0, 0.0001, "vrel final igual a -0.85 * 100")

func test_ricochete_frontal_independente_da_ordem_de_criacao() -> void:
	var target := _stub(
		CollisionLayers.ENEMY,
		CollisionLayers.PLAYER | CollisionLayers.ENEMY,
		Vector2(20.5, 0.0))
	var mover := _stub(
		CollisionLayers.PLAYER,
		CollisionLayers.PLAYER | CollisionLayers.ENEMY,
		Vector2.ZERO)
	await _slide_and_resolve(mover, target, 100.0)

	var relative := (mover.velocity - (target.velocity + target.knockback_total)).dot(Vector2.RIGHT)
	assert_almost_eq(relative, -85.0, 0.0001, "a normal canonica nao depende do id")

func test_resolve_sem_prepare_e_noop() -> void:
	var mover := _stub(
		CollisionLayers.PLAYER,
		CollisionLayers.PLAYER | CollisionLayers.ENEMY,
		Vector2.ZERO)
	mover.velocity = Vector2.RIGHT * 100.0

	ContactRicochet.resolve(mover)

	assert_almost_eq(mover.velocity.x, 100.0, 0.0001, "quadro de blink nao integra")
	assert_eq(mover.knockback_calls.size(), 0)

func test_margem_de_contato_d5_danifica_exatamente_uma_vez() -> void:
	var scenario := await _damage_scenario(false)
	var player := scenario["player"] as Player
	var sink := scenario["hits"] as Array

	assert_eq(player.hurtbox.get_shape_radius(), 11.0, "margem D5 aplicada")
	assert_gt(player.hurtbox.get_overlapping_bodies().size(), 0, "16.5 px cai dentro de 11 + 7")
	_assert_single_touch(sink, player)

func test_margem_de_contato_d5_com_ordem_de_criacao_invertida() -> void:
	var scenario := await _damage_scenario(true)
	var player := scenario["player"] as Player
	var sink := scenario["hits"] as Array

	assert_gt(player.hurtbox.get_overlapping_bodies().size(), 0, "ordem nao muda a sobreposicao")
	_assert_single_touch(sink, player)

func test_delta_adiado_so_entra_na_leitura_de_contatos() -> void:
	var player := _contact_player()
	player.velocity = Vector2.ZERO
	player._collision_knockback_velocity = Vector2.ZERO

	ContactRicochet.defer(player, Vector2(6.0, 0.0))
	assert_almost_eq(player.velocity.x, 0.0, 0.0001, "adiar nao muda nada sozinho")
	assert_almost_eq(player._collision_knockback_velocity.x, 0.0, 0.0001, "adiar nao muda nada sozinho")

	ContactRicochet.flush_deferred(player)
	assert_almost_eq(player.velocity.x, 6.0, 0.0001, "o flush soma na velocidade")
	assert_almost_eq(player._collision_knockback_velocity.x, 6.0, 0.0001, "o flush soma no canal")

	ContactRicochet.flush_deferred(player)
	assert_almost_eq(player.velocity.x, 6.0, 0.0001, "flush repetido e idempotente")
	assert_almost_eq(player._collision_knockback_velocity.x, 6.0, 0.0001, "flush repetido e idempotente")

func test_delta_adiado_expira_apos_a_janela_de_dois_frames() -> void:
	var player := _contact_player()
	player.velocity = Vector2.ZERO
	player._collision_knockback_velocity = Vector2.ZERO

	ContactRicochet.defer(player, Vector2(6.0, 0.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	ContactRicochet.flush_deferred(player)

	assert_almost_eq(player.velocity.x, 0.0, 0.0001, "delta velho e descartado")
	assert_almost_eq(player._collision_knockback_velocity.x, 0.0, 0.0001, "delta velho e descartado")

func test_debris_nao_e_participante_de_contato() -> void:
	var debris := _debris(Vector2.ZERO)
	await get_tree().physics_frame

	assert_false(ContactRicochet.is_participant(debris))
	assert_false(ContactRicochet.is_player_body(debris))

func test_charge_da_bruta_ricocheteia_no_inimigo_sem_cancelar() -> void:
	var player := await _bruta_player()
	player.global_position = Vector2(100.0, 200.0)
	player._aim_vector = Vector2.RIGHT
	player._bruta_charge_direction = Vector2.RIGHT
	player._bruta_charge_aim_source = Player.AimSource.NONE
	player._bruta_charge_windup_remaining = 0.0
	player._bruta_charge_remaining = 0.75
	player.collision_mask = CollisionLayers.WORLD
	var enemy := _enemy(Vector2(130.0, 200.0))
	enemy.velocity = Vector2.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame

	player._update_bruta_charge(0.1)

	assert_true(player._is_bruta_charging(), "participante nao cancela a investida")
	assert_eq(player.collision_mask, CollisionLayers.WORLD, "mascara restaurada no subpasso")
	assert_eq(player._bruta_charge_ricochet_targets.size(), 1, "um unico ricochete por alvo")
	assert_gt(enemy._collision_knockback_velocity.x, 0.0, "o alvo recebe o impulso")

func test_charge_da_bruta_cancela_no_mundo() -> void:
	var player := await _bruta_player()
	player.global_position = Vector2(100.0, 200.0)
	player._aim_vector = Vector2.RIGHT
	player._bruta_charge_direction = Vector2.RIGHT
	player._bruta_charge_aim_source = Player.AimSource.NONE
	player._bruta_charge_windup_remaining = 0.0
	player._bruta_charge_remaining = 0.75
	player.collision_mask = CollisionLayers.WORLD
	_static_body(Vector2(135.0, 200.0), 10.0)
	await get_tree().physics_frame
	await get_tree().physics_frame

	player._update_bruta_charge(0.3)

	assert_false(player._is_bruta_charging(), "o mundo cancela a investida")
	assert_eq(player.collision_mask, CollisionLayers.WORLD, "mascara restaurada no cancel")
	assert_eq(player._bruta_charge_ricochet_targets.size(), 0, "mundo nao gera ricochete")

func test_componente_nao_programa_quique_de_borda() -> void:
	var source := FileAccess.get_file_as_string(RICOCHET_PATH)
	assert_gt(source.length(), 0, RICOCHET_PATH)
	assert_false(source.contains("_clamp_to_bounds"))
	assert_false(source.contains("_room_bounds"))
	assert_false(source.contains("set_room_bounds"))
	assert_false(source.contains("reflect"))
	assert_false(source.contains("bounce"))

func test_clamp_de_borda_continua_intocado() -> void:
	var player := _contact_player()
	player.set_room_bounds(Rect2(0.0, 0.0, 720.0, 405.0))
	player.global_position = Vector2(800.0, 360.0)
	player.velocity = Vector2.RIGHT * 120.0

	player._clamp_to_bounds()

	assert_almost_eq(player.global_position.x, 710.0, 0.0001, "borda ainda prende a posicao")
	assert_almost_eq(player.global_position.y, 360.0, 0.0001, "borda nao mexe no eixo livre")
	assert_almost_eq(player.velocity.x, 120.0, 0.0001, "borda nao inverte velocidade")

func test_dois_jogadores_recebem_impulso_unico_e_o_delta_so_entra_pelo_gate() -> void:
	var a := _contact_player()
	var b := _contact_player()
	a.global_position = Vector2.ZERO
	b.global_position = Vector2(10.5, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame

	_tick_prepare_slide(a, 100.0)
	_tick_prepare_slide(b, 0.0)

	ContactRicochet.flush_deferred(a)
	RESOLVER.resolve_overlaps(a, a._collision_impact_pairs)
	ContactRicochet.resolve(a)

	var a_velocity := a.velocity.x
	assert_lt(a_velocity, 100.0, "quem choca perde momento")
	assert_almost_eq(b.velocity.x, 0.0, 0.0001, "o delta adiado nao vaza para a velocidade antes do gate")
	assert_almost_eq(b._collision_knockback_velocity.x, 0.0, 0.0001, "o canal do outro jogador fica intocado")

	var mass_a: float = ContactRicochet.mass_of(a)
	var mass_b: float = ContactRicochet.mass_of(b)
	ContactRicochet.flush_deferred(b)
	RESOLVER.resolve_overlaps(b, b._collision_impact_pairs)
	var b_velocity := b.velocity.x
	assert_gt(b_velocity, 0.0, "o gate e a unica entrada do delta adiado")
	assert_almost_eq(b._collision_knockback_velocity.x, b_velocity, 0.0001, "o flush soma no canal e na velocidade")
	assert_almost_eq(mass_a * a_velocity + mass_b * b_velocity, mass_a * 100.0, 0.001, "momento conservado")

	ContactRicochet.resolve(b)
	assert_almost_eq(b.velocity.x, b_velocity, 0.0001, "resolver o receptor no mesmo quadro nao soma de novo")

	ContactRicochet.resolve(a)
	ContactRicochet.resolve(a)
	assert_almost_eq(a.velocity.x, a_velocity, 0.0001, "impulso unico por par por quadro")
	assert_almost_eq(b.velocity.x, b_velocity, 0.0001, "nenhum delta novo no mesmo quadro")

func test_par_gasto_no_quadro_n_rearma_no_quadro_seguinte_sem_limpeza() -> void:
	var mover := _stub(
		CollisionLayers.PLAYER,
		CollisionLayers.PLAYER | CollisionLayers.ENEMY,
		Vector2.ZERO)
	var target := _stub(
		CollisionLayers.ENEMY,
		CollisionLayers.PLAYER | CollisionLayers.ENEMY,
		Vector2(20.5, 0.0))
	await _slide_and_resolve(mover, target, 100.0)
	assert_eq(mover.knockback_calls.size(), 1, "primeiro quadro com impulso")
	assert_eq(target.knockback_calls.size(), 1)

	await get_tree().physics_frame
	mover.velocity = Vector2.RIGHT * 100.0
	ContactRicochet.prepare(mover)
	mover.move_and_slide()
	ContactRicochet.restore_after_slide(mover)
	ContactRicochet.resolve(mover)

	assert_eq(mover.knockback_calls.size(), 2, "o par volta a ser elegivel no quadro seguinte")
	assert_eq(target.knockback_calls.size(), 2, "o purge quadro a quadro rearma sem clear_all_state")

func test_delta_adiado_aplica_no_quadro_seguinte() -> void:
	var player := _contact_player()
	player.velocity = Vector2.ZERO
	player._collision_knockback_velocity = Vector2.ZERO

	ContactRicochet.defer(player, Vector2(6.0, 0.0))
	await get_tree().physics_frame
	ContactRicochet.flush_deferred(player)

	assert_almost_eq(player.velocity.x, 6.0, 0.0001, "o delta vale no quadro seguinte")
	assert_almost_eq(player._collision_knockback_velocity.x, 6.0, 0.0001, "e entra no canal de knockback")

	ContactRicochet.flush_deferred(player)
	assert_almost_eq(player.velocity.x, 6.0, 0.0001, "flush repetido nao soma de novo")

func test_blink_no_quadro_n_nao_processa_par_e_no_n1_volta_ao_normal() -> void:
	var mover := _stub(
		CollisionLayers.PLAYER,
		CollisionLayers.PLAYER | CollisionLayers.ENEMY,
		Vector2.ZERO)
	var target := _stub(
		CollisionLayers.ENEMY,
		CollisionLayers.PLAYER | CollisionLayers.ENEMY,
		Vector2(20.5, 0.0))
	await _slide_and_resolve(mover, target, 100.0)
	assert_eq(mover.knockback_calls.size(), 1, "contato antes do blink")
	assert_eq(target.knockback_calls.size(), 1)

	await get_tree().physics_frame
	ContactRicochet.resolve(mover)
	assert_eq(mover.knockback_calls.size(), 1, "o quadro de blink nao integra o par")
	assert_eq(target.knockback_calls.size(), 1, "o quadro de blink nao gera impulso no alvo")

	await get_tree().physics_frame
	mover.velocity = Vector2.RIGHT * 100.0
	ContactRicochet.prepare(mover)
	mover.move_and_slide()
	ContactRicochet.restore_after_slide(mover)
	ContactRicochet.resolve(mover)

	assert_eq(mover.knockback_calls.size(), 2, "sem estado fantasma o quadro seguinte processa")
	assert_eq(target.knockback_calls.size(), 2, "o alvo recebe o impulso do quadro seguinte")

func test_inimigos_trocam_momento_sem_dano_entre_si() -> void:
	var first := _enemy(Vector2.ZERO)
	var second := _enemy(Vector2(14.5, 0.0))
	first.velocity = Vector2.RIGHT * 100.0
	second.velocity = Vector2.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame
	var first_health: int = first.health.health
	var second_health: int = second.health.health

	first._integrate_physics_motion(0.05, 0.05)

	var mass_first: float = first.get_collision_mass()
	var mass_second: float = second.get_collision_mass()
	var momentum := mass_first * first.velocity.x + mass_second * (second.velocity.x + second._collision_knockback_velocity.x)
	assert_gt(second._collision_knockback_velocity.x, 0.0, "o inimigo atingido ganha momento")
	assert_lt(first._collision_knockback_velocity.x, 0.0, "o inimigo que choca perde momento")
	assert_almost_eq(momentum, mass_first * 100.0, 0.001, "momento conservado no choque entre inimigos")
	assert_almost_eq(first.velocity.x - first._collision_knockback_velocity.x, 100.0, 0.0001, "a base controlada fica integra")
	assert_eq(first.health.health, first_health, "sem dano entre inimigos")
	assert_eq(second.health.health, second_health, "sem dano entre inimigos")

func test_contato_pe_no_tick_completo_danifica_e_ricocheteia_uma_vez() -> void:
	var player := _contact_player()
	var enemy := _enemy(Vector2(12.5, 0.0))
	player.global_position = Vector2.ZERO
	player.velocity = Vector2.RIGHT * 100.0
	enemy.velocity = Vector2.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame
	var sink: Array = []
	enemy.health.damaged.connect(_record_damage.bind(sink))

	ContactRicochet.prepare(player)
	player.move_and_slide()
	ContactRicochet.restore_after_slide(player)
	assert_gt(_slide_hits_on(player, enemy), 0, "o inimigo aparece no deslizamento")

	ContactRicochet.flush_deferred(player)
	RESOLVER.resolve_overlaps(player, player._collision_impact_pairs)
	var damage_after_gate: int = sink.size()
	var enemy_knockback_before := enemy._collision_knockback_velocity
	ContactRicochet.resolve(player)
	var ricochet := enemy._collision_knockback_velocity - enemy_knockback_before

	assert_eq(damage_after_gate, 1, "o gate danifica uma unica vez por contato")
	assert_gt(ricochet.x, 0.0, "o ricochete empurra o inimigo para longe")

	var enemy_knockback_after := enemy._collision_knockback_velocity
	RESOLVER.resolve_overlaps(player, player._collision_impact_pairs)
	ContactRicochet.resolve(player)
	assert_eq(sink.size(), 1, "repetir o gate nao redanifica")
	assert_eq(enemy._collision_knockback_velocity, enemy_knockback_after, "resolver de novo nao soma impulso")

func test_charge_da_bruta_deduplica_alvo_no_mesmo_ciclo() -> void:
	var player := await _bruta_player()
	player.global_position = Vector2(100.0, 200.0)
	player._aim_vector = Vector2.RIGHT
	player._bruta_charge_direction = Vector2.RIGHT
	player._bruta_charge_aim_source = Player.AimSource.NONE
	player._bruta_charge_windup_remaining = 0.0
	player._bruta_charge_remaining = 0.75
	player.collision_mask = CollisionLayers.WORLD
	var enemy := _enemy(Vector2(125.0, 200.0))
	enemy.velocity = Vector2.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame
	var sink: Array = []
	enemy.health.damaged.connect(_record_damage.bind(sink))

	player._update_bruta_charge(0.1)

	assert_true(player._is_bruta_charging(), "contato com participante nao cancela a investida")
	assert_eq(player.collision_mask, CollisionLayers.WORLD, "mascara restaurada apos o subpasso")
	assert_eq(player._bruta_charge_ricochet_targets.size(), 1, "o alvo entrou no dedupe do ciclo")
	var knockback_after_first := enemy._collision_knockback_velocity
	assert_gt(knockback_after_first.x, 0.0, "o alvo recebe o impulso da carga")

	player._update_bruta_charge(0.1)

	assert_true(player._is_bruta_charging(), "o segundo toque continua a investida")
	assert_eq(player.collision_mask, CollisionLayers.WORLD, "mascara restaurada no segundo subpasso")
	assert_eq(player._bruta_charge_ricochet_targets.size(), 1, "um unico alvo no dedupe do ciclo")
	assert_eq(enemy._collision_knockback_velocity, knockback_after_first, "o segundo toque nao soma impulso")

	await get_tree().physics_frame
	await get_tree().physics_frame
	RESOLVER.resolve_overlaps(player, player._collision_impact_pairs)
	assert_eq(sink.size(), 1, "a leitura de contatos do quadro seguinte dana o contato da carga")

func test_charge_da_bruta_cancela_no_mundo_logo_apos_tocar_o_ator() -> void:
	var player := await _bruta_player()
	player.global_position = Vector2(100.0, 200.0)
	player._aim_vector = Vector2.RIGHT
	player._bruta_charge_direction = Vector2.RIGHT
	player._bruta_charge_aim_source = Player.AimSource.NONE
	player._bruta_charge_windup_remaining = 0.0
	player._bruta_charge_remaining = 0.75
	player.collision_mask = CollisionLayers.WORLD | CollisionLayers.PLAYER | CollisionLayers.ENEMY
	var enemy := _enemy(Vector2(125.0, 200.0))
	enemy.velocity = Vector2.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame

	player._update_bruta_charge(0.1)

	assert_true(player._is_bruta_charging(), "o ator participante nao cancela a investida")
	assert_eq(player._bruta_charge_ricochet_targets.size(), 1, "o ator gerou ricochete no ciclo")
	assert_eq(player.collision_mask, CollisionLayers.WORLD | CollisionLayers.PLAYER | CollisionLayers.ENEMY, "mascara restaurada apos tocar o ator")

	enemy.global_position = Vector2(125.0, 140.0)
	_static_body(Vector2(140.0, 200.0), 10.0)
	await get_tree().physics_frame
	await get_tree().physics_frame

	player._update_bruta_charge(0.3)

	assert_false(player._is_bruta_charging(), "o mundo logo apos o ator cancela por hit_wall")
	assert_eq(player.collision_mask, CollisionLayers.WORLD | CollisionLayers.PLAYER | CollisionLayers.ENEMY, "mascara restaurada no cancel")
	assert_eq(player._bruta_charge_ricochet_targets.size(), 0, "o cancel limpa o dedupe do ciclo")

func test_margem_d5_nao_muda_o_alcance_nariz_a_nariz_com_inimigo_grande() -> void:
	var player := _contact_player()
	var enemy := _atirador(Vector2.ZERO)
	player.global_position = Vector2.ZERO
	player.velocity = Vector2.RIGHT * 100.0
	enemy.velocity = Vector2.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame

	assert_eq(player.hurtbox.get_shape_radius(), 11.0, "margem D5 do jogador")
	assert_eq(enemy.get_collision_radius(), 12.0, "o atirador de fresta tem raio 12")
	assert_almost_eq((player.body_collision.shape as CapsuleShape2D).radius, 5.0, 0.0001, "corpo do jogador intacto")

	enemy.global_position = Vector2(17.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_gt(player.hurtbox.get_overlapping_bodies().size(), 0, "17 px (5 + 12) esta dentro de 11 + 12")
	var sink: Array = []
	enemy.health.damaged.connect(_record_damage.bind(sink))
	RESOLVER.resolve_overlaps(player, player._collision_impact_pairs)
	assert_eq(sink.size(), 1, "contato nariz a nariz danifica uma unica vez")

	player._collision_impact_pairs.clear()
	sink.clear()
	enemy.global_position = Vector2(24.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(player.hurtbox.get_overlapping_bodies().size(), 0, "24 px fica fora de 11 + 12")
	RESOLVER.resolve_overlaps(player, player._collision_impact_pairs)
	assert_eq(sink.size(), 0, "sem sobreposicao nao ha dano")

	enemy.global_position = Vector2(60.0, 0.0)
	await _push(player, enemy, 60.0)
	assert_almost_eq(_final_x, 43.0, 0.15, "o bloqueio fisico continua nariz a nariz em 5 + 12, com a margem de contato do motor")

## Prepara a Bruta no meio da investida, apontando para a direita.
func _charging_bruta(position: Vector2) -> Player:
	var player := await _bruta_player()
	player.global_position = position
	player._aim_vector = Vector2.RIGHT
	player._bruta_charge_direction = Vector2.RIGHT
	player._bruta_charge_aim_source = Player.AimSource.NONE
	player._bruta_charge_windup_remaining = 0.0
	player._bruta_charge_remaining = 0.75
	player.collision_mask = CollisionLayers.WORLD
	return player

func test_cadaver_e_ator_de_contato_mas_fora_do_calculo_de_impulso() -> void:
	var enemy := _enemy(Vector2.ZERO)
	await get_tree().physics_frame

	assert_true(ContactRicochet.is_contact_actor(enemy), "inimigo vivo e ator D2")
	assert_true(ContactRicochet.is_participant(enemy), "inimigo vivo participa do impulso")

	enemy.queue_free()

	assert_true(ContactRicochet.is_contact_actor(enemy), "cadaver com fila pendente segue sendo ator D2")
	assert_false(ContactRicochet.is_participant(enemy), "cadaver fica fora do calculo de impulso")

func test_cadaver_com_queue_free_pendente_nao_vira_hit_wall() -> void:
	var player := await _charging_bruta(Vector2(100.0, 200.0))
	var enemy := _enemy(Vector2(125.0, 200.0))
	enemy.velocity = Vector2.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame
	var generation_before := player._bruta_charge_generation

	enemy.queue_free()
	player._update_bruta_charge(0.1)

	assert_true(enemy.is_queued_for_deletion(), "o colider entrou na carga ja com queue_free pendente")
	assert_true(player._is_bruta_charging(), "cadaver participante nao vira hit_wall")
	assert_eq(player._bruta_charge_generation, generation_before, "nenhum cancelamento no quadro")
	assert_eq(player.collision_mask, CollisionLayers.WORLD, "mascara restaurada")
	assert_eq(player._bruta_charge_ricochet_targets.size(), 0, "cadaver fora do calculo de impulso")

func test_carga_letal_a_meio_ciclo_nao_cancela_pelo_cadaver() -> void:
	# Corpo em capsula: o contato fisico encosta em 5 + 7, enquanto o
	# resolve_segment mede com a margem de 10 + 7 (sem circulo no corpo, o
	# leitor cai no padrao). Assim o dano letal dentro do subpasso nao depende
	# de arredondamento exato no limite do motor.
	var player := _contact_player()
	player.global_position = Vector2(100.0, 200.0)
	player._aim_vector = Vector2.RIGHT
	player._bruta_charge_direction = Vector2.RIGHT
	player._bruta_charge_aim_source = Player.AimSource.NONE
	player._bruta_charge_windup_remaining = 0.0
	player._bruta_charge_remaining = 0.75
	player.collision_mask = CollisionLayers.WORLD
	var enemy := _enemy(Vector2(125.0, 200.0))
	enemy.velocity = Vector2.ZERO
	enemy.health.max_health = HEALTH_UNITS.from_hp(0.5)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var generation_before := player._bruta_charge_generation

	player._update_bruta_charge(0.1)

	assert_true(enemy.is_queued_for_deletion(), "a carga foi letal dentro do subpasso")
	assert_true(player._is_bruta_charging(), "o cadaver do alvo letal nao cancela a investida")
	assert_eq(player._bruta_charge_generation, generation_before, "nenhum cancelamento no quadro")
	assert_eq(player.collision_mask, CollisionLayers.WORLD, "mascara restaurada")
	assert_eq(player._bruta_charge_ricochet_targets.size(), 0, "o alvo morreu antes do toque fisico e cadaver nao entra no dedupe")

func test_check_contact_le_a_velocidade_pura_antes_do_delta_adiado() -> void:
	var player := _contact_player()
	var enemy := _enemy(Vector2(14.0, 0.0))
	player.global_position = Vector2.ZERO
	player.velocity = Vector2.ZERO
	player._collision_knockback_velocity = Vector2.ZERO
	enemy.velocity = Vector2.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame
	var sink: Array = []
	enemy.health.damaged.connect(_record_damage.bind(sink))
	enemy.knockback_force = 0.0
	ContactRicochet.defer(player, Vector2(6.0, 0.0))

	var contact_current := player._check_contact(0.0)

	assert_true(contact_current, "o jogador segue vivo na leitura")
	assert_eq(sink.size(), 0, "o gate le v0 puro, ainda sem o delta adiado")
	assert_almost_eq(player.velocity.x, 6.0, 0.0001, "o flush entra depois da leitura, no mesmo chamado")
	assert_almost_eq(player._collision_knockback_velocity.x, 6.0, 0.0001, "o canal so enche depois da leitura")

	player._check_contact(0.0)

	assert_eq(sink.size(), 1, "flushado apos a leitura o delta vira velocidade e o proximo gate danifica")
	assert_almost_eq(player.velocity.x, 6.0, 0.0001, "o flush do primeiro chamado persiste")
	assert_almost_eq(player._collision_knockback_velocity.x, 6.0, 0.0001, "o canal continua com o delta flushado")

func test_delta_adiado_e_descartado_quando_o_gate_derruba_o_jogador() -> void:
	var player := _contact_player()
	var enemy := _enemy(Vector2(14.0, 0.0))
	player.global_position = Vector2.ZERO
	player.velocity = Vector2.ZERO
	player._collision_knockback_velocity = Vector2.ZERO
	enemy.velocity = Vector2.LEFT * 4000.0
	enemy.collision_damage_resistance = 1.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	GameState.player_lives = 2
	player.health.health = 1
	ContactRicochet.defer(player, Vector2(6.0, 0.0))
	var generation_before := player.get_collision_impact_generation()

	var contact_current := player._check_contact(0.0)

	assert_false(contact_current, "a leitura de contatos derrubou o jogador")
	assert_eq(player.get_collision_impact_generation(), generation_before + 1, "a morte trocou a geracao")
	assert_eq(player.velocity, Vector2.ZERO, "o reset de morte zera a velocidade")
	assert_eq(player._collision_knockback_velocity, Vector2.ZERO, "o reset de morte zera o canal")

	ContactRicochet.flush_deferred(player)
	assert_eq(player.velocity, Vector2.ZERO, "o delta adiado foi descartado e nao reacende a velocidade")
	assert_eq(player._collision_knockback_velocity, Vector2.ZERO, "o canal continua zerado apos o flush tardio")
	await get_tree().process_frame

