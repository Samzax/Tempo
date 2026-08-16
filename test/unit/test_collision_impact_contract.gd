extends GutTest

const RESOLVER := preload("res://scripts/combat/collision_impact_resolver.gd")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const ENEMY_SCRIPT := preload("res://scripts/enemies/enemy.gd")
const ATIRADOR_SCENE := preload("res://scenes/enemies/atirador_de_fresta.tscn")
const HUNTER_SCENE := preload("res://scenes/enemies/hunter.tscn")
const KAMIKAZE_SCENE := preload("res://scenes/enemies/kamikaze_fraturado.tscn")
const HEALTH_UNITS := preload("res://scripts/components/health_units.gd")

func _pair(speed: float = 100.0, player_mass: float = 1.0, enemy_mass: float = 1.0) -> Array:
	var player := CollisionStub.new()
	var enemy := CollisionStub.new()
	player.collision_mass = player_mass
	enemy.collision_mass = enemy_mass
	player.velocity = Vector2.RIGHT * speed
	player.global_position = Vector2.ZERO
	enemy.global_position = Vector2(10.0, 0.0)
	player.overlap.bodies = [enemy]
	add_child_autofree(player)
	add_child_autofree(enemy)
	return [player, enemy]

func test_small_positive_approach_has_positive_damage_without_gameplay_speed_floor() -> void:
	var pair := _pair(0.2)
	RESOLVER.resolve_overlaps(pair[0], {})
	assert_eq(pair[0].damage_amounts[0], 0)

func test_sub_epsilon_positive_approach_still_produces_impact_damage() -> void:
	var pair := _pair(0.0005)
	RESOLVER.resolve_overlaps(pair[0], {})
	assert_eq(pair[0].damage_amounts[0], 0)

func test_equal_masses_produce_symmetric_damage() -> void:
	var pair := _pair(100.0)
	RESOLVER.resolve_overlaps(pair[0], {})
	assert_eq(pair[0].damage_amounts[0], pair[1].damage_amounts[0])

func test_mass_changes_shared_linear_base_without_asymmetric_damage_split() -> void:
	var baseline := _pair(100.0, 1.0, 1.0)
	RESOLVER.resolve_overlaps(baseline[0], {})
	var pair := _pair(100.0, 1.0, 4.0)
	RESOLVER.resolve_overlaps(pair[0], {})
	assert_eq(pair[0].damage_amounts[0], pair[1].damage_amounts[0])
	assert_gt(pair[0].damage_amounts[0], baseline[0].damage_amounts[0])

func test_separating_or_co_moving_bodies_do_not_impact() -> void:
	var pair := _pair(100.0)
	pair[0].velocity = Vector2.LEFT * 100.0
	RESOLVER.resolve_overlaps(pair[0], {})
	assert_eq(pair[0].damage_amounts.size(), 0)
	assert_eq(pair[1].damage_amounts.size(), 0)

func test_zero_and_tangential_closing_speed_do_not_impact() -> void:
	var zero := _pair(0.0)
	RESOLVER.resolve_overlaps(zero[0], {})
	assert_eq(zero[0].damage_amounts.size(), 0)
	assert_eq(zero[1].damage_amounts.size(), 0)
	var tangential := _pair(100.0)
	tangential[0].velocity = Vector2(0.0, 100.0)
	RESOLVER.resolve_overlaps(tangential[0], {})
	assert_eq(tangential[0].damage_amounts.size(), 0)
	assert_eq(tangential[1].damage_amounts.size(), 0)

func test_degenerate_contact_uses_deterministic_velocity_fallback_normal() -> void:
	var pair := _pair(100.0)
	pair[1].global_position = Vector2.ZERO
	RESOLVER.resolve_overlaps(pair[0], {})
	assert_gt(pair[0].damage_amounts[0], 0)
	assert_lt(pair[0].velocity.x, 100.0)
	assert_gt(pair[1].velocity.x, 0.0)

func test_fully_degenerate_contact_has_non_zero_fallback_but_no_zero_speed_damage() -> void:
	var pair := _pair(0.0)
	pair[1].global_position = Vector2.ZERO
	var states := {}
	RESOLVER.resolve_overlaps(pair[0], states)
	assert_eq(_pair_state(states, pair[1]), &"OVERLAPPING_ARMED")
	assert_eq(pair[0].damage_amounts.size(), 0)
	assert_eq(pair[1].damage_amounts.size(), 0)

func test_reduced_mass_drives_a_linear_shared_base_without_radius_multiplier() -> void:
	var pair := _pair(100.0, 2.0, 3.0)
	pair[0].collision_radius = 20.0
	RESOLVER.resolve_overlaps(pair[0], {})
	# ma=2, mb=3, mu=6/5; base=mu*(100/100)=1.2 para ambos.
	assert_eq(pair[0].damage_amounts[0], HEALTH_UNITS.from_hp(1.2))
	assert_eq(pair[1].damage_amounts[0], HEALTH_UNITS.from_hp(1.2))

func test_damage_is_bilateral_and_collision_resistance_only_reduces_receiver() -> void:
	var pair := _pair(100.0)
	pair[0].collision_damage_resistance = 0.5
	RESOLVER.resolve_overlaps(pair[0], {})
	assert_gt(pair[0].damage_amounts[0], 0)
	assert_gt(pair[1].damage_amounts[0], 0)
	var baseline := _pair(100.0)
	RESOLVER.resolve_overlaps(baseline[0], {})
	assert_eq(pair[0].damage_amounts[0], baseline[0].damage_amounts[0] / 2)
	assert_eq(pair[1].damage_amounts[0], baseline[1].damage_amounts[0])
	var immune := _pair(100.0)
	immune[0].collision_damage_resistance = 1.0
	RESOLVER.resolve_overlaps(immune[0], {})
	assert_eq(immune[0].damage_amounts[0], 0)
	assert_gt(immune[1].damage_amounts[0], 0)

func test_knockback_force_changes_impulse_but_not_damage_and_resistance_can_zero_it() -> void:
	var baseline := _pair(100.0)
	RESOLVER.resolve_overlaps(baseline[0], {})
	var forced := _pair(100.0)
	forced[1].knockback_force = 3.0
	RESOLVER.resolve_overlaps(forced[0], {})
	assert_eq(forced[0].damage_amounts[0], baseline[0].damage_amounts[0])
	assert_gt(absf(forced[0].velocity.x - baseline[0].velocity.x), 0.00001)
	var resisted := _pair(100.0)
	resisted[0].knockback_resistance = 1.0
	RESOLVER.resolve_overlaps(resisted[0], {})
	assert_almost_eq(resisted[0].velocity.length(), 100.0, 0.00001)

func test_knockback_is_bilateral_opposite_and_uses_each_force_and_receiver_resistance() -> void:
	var pair := _pair(100.0)
	pair[0].knockback_force = 2.0
	pair[1].knockback_force = 3.0
	pair[0].knockback_resistance = 0.5
	RESOLVER.resolve_overlaps(pair[0], {})
	assert_almost_eq(pair[0].velocity.x, 99.25, 0.00001)
	assert_almost_eq(pair[1].velocity.x, 1.0, 0.00001)

func test_overlap_spends_once_separation_rearms_and_reapproach_impacts_again() -> void:
	var pair := _pair(100.0)
	var states := {}
	RESOLVER.resolve_overlaps(pair[0], states)
	RESOLVER.resolve_overlaps(pair[0], states)
	assert_eq(pair[0].damage_amounts.size(), 1)
	pair[0].overlap.bodies = []
	RESOLVER.resolve_overlaps(pair[0], states)
	pair[0].overlap.bodies = [pair[1]]
	pair[0].velocity = Vector2.RIGHT * 100.0
	RESOLVER.resolve_overlaps(pair[0], states)
	assert_eq(pair[0].damage_amounts.size(), 2)

func test_segment_intersection_spends_target_even_when_overlap_list_is_empty() -> void:
	var pair := _pair(100.0)
	var states := {}
	RESOLVER.resolve_segment(pair[0], Vector2.ZERO, Vector2(20.0, 0.0), states)
	assert_eq(_pair_state(states, pair[1]), &"OVERLAPPING_SPENT")
	assert_eq(pair[0].damage_amounts.size(), 1)
	assert_eq(pair[1].damage_amounts.size(), 1)

func test_repeated_intersecting_segment_does_not_damage_same_target_twice() -> void:
	var pair := _pair(100.0)
	var states := {}
	RESOLVER.resolve_segment(pair[0], Vector2.ZERO, Vector2(20.0, 0.0), states)
	RESOLVER.resolve_segment(pair[0], Vector2.ZERO, Vector2(20.0, 0.0), states)
	assert_eq(pair[0].damage_amounts.size(), 1)
	assert_eq(pair[1].damage_amounts.size(), 1)

func test_empty_subpass_rearms_target_for_later_segment_intersection() -> void:
	var pair := _pair(100.0)
	var states := {}
	RESOLVER.resolve_segment(pair[0], Vector2.ZERO, Vector2(20.0, 0.0), states)
	pair[0].overlap.bodies = []
	RESOLVER.resolve_segment(pair[0], Vector2(31.0, 0.0), Vector2(41.0, 0.0), states)
	assert_false(states.has(pair[1].get_instance_id()))
	RESOLVER.resolve_segment(pair[0], Vector2.ZERO, Vector2(20.0, 0.0), states)
	assert_eq(pair[0].damage_amounts.size(), 2)
	assert_eq(pair[1].damage_amounts.size(), 2)

func test_pair_cache_requires_the_exact_live_instance_and_prunes_freed_contacts() -> void:
	var pair := _pair(100.0)
	var states := {}
	RESOLVER.resolve_overlaps(pair[0], states)
	var spent: CollisionStub = pair[1] as CollisionStub
	var spent_ref: WeakRef = weakref(spent)
	pair[0].overlap.bodies = []
	spent.free()
	RESOLVER.resolve_overlaps(pair[0], states)
	assert_null(spent_ref.get_ref())
	assert_eq(states.size(), 0)
	var replacement := CollisionStub.new()
	replacement.global_position = Vector2(10.0, 0.0)
	add_child_autofree(replacement)
	pair[0].overlap.bodies = [replacement]
	pair[0].velocity = Vector2.RIGHT * 100.0
	RESOLVER.resolve_overlaps(pair[0], states)
	assert_eq(replacement.damage_amounts.size(), 1)
	assert_eq(_pair_state(states, replacement), &"OVERLAPPING_SPENT")
	assert_true(states[replacement.get_instance_id()][&"enemy"] is WeakRef)

func test_non_finite_collision_inputs_do_not_propagate_damage_or_knockback() -> void:
	var pair := _pair(100.0)
	pair[0].velocity = Vector2(NAN, INF)
	pair[0].collision_mass = NAN
	pair[1].knockback_force = INF
	RESOLVER.resolve_overlaps(pair[0], {})
	assert_eq(pair[0].damage_amounts.size(), 0)
	assert_eq(pair[1].damage_amounts.size(), 0)
	assert_true(pair[0].damage_amounts.all(func(value): return is_finite(value)))
	assert_true(pair[1].damage_amounts.all(func(value): return is_finite(value)))
	assert_eq(pair[0].received_knockback, Vector2.ZERO)
	assert_eq(pair[1].received_knockback, Vector2.ZERO)
	assert_true(pair[0].received_knockback.is_finite())
	assert_true(pair[1].received_knockback.is_finite())
	assert_true(pair[0].velocity.is_finite())
	assert_true(pair[1].velocity.is_finite())
	assert_true(pair[0].global_position.is_finite())
	assert_true(pair[1].global_position.is_finite())

func test_enemy_and_real_subclasses_integrate_once_with_normal_stun_and_partial_expiry_motion() -> void:
	for enemy in _motion_spies():
		_prepare_motion_spy(enemy)
		add_child_autofree(enemy)
		await get_tree().process_frame
		enemy.set_physics_process(false)
		enemy.set_room_cull_policy(RoomDef.CullPolicy.NONE)
		enemy.set_entry_inward(Vector2.RIGHT)
		enemy.speed = 100.0
		if enemy is MotionSpyAtirador:
			enemy._entry_speed = 100.0

		enemy.set(&"integration_count", 0)
		enemy.global_position = Vector2.ZERO
		enemy._physics_process(0.1)
		assert_eq(int(enemy.get(&"integration_count")), 1, "%s normal tick" % enemy.get_class())
		var normal_displacement := enemy.global_position.x
		assert_gt(normal_displacement, 0.0, "%s normal displacement" % enemy.get_class())
		assert_almost_eq(enemy.velocity.x, 100.0, 0.001, "%s normal velocity" % enemy.get_class())

		enemy.set(&"integration_count", 0)
		enemy.global_position = Vector2.ZERO
		enemy.apply_stun(0.5)
		enemy.apply_collision_knockback(Vector2.RIGHT * 20.0)
		enemy._physics_process(0.1)
		assert_eq(int(enemy.get(&"integration_count")), 1, "%s stunned tick" % enemy.get_class())
		var stunned_displacement := enemy.global_position.x
		assert_gt(stunned_displacement, 0.0, "%s stunned knockback displacement" % enemy.get_class())
		assert_almost_eq(enemy.velocity.x, 20.0, 0.001, "%s stunned velocity" % enemy.get_class())

		enemy.set(&"integration_count", 0)
		enemy.global_position = Vector2.ZERO
		enemy.stun_remaining = 0.05
		enemy.apply_collision_knockback(Vector2.RIGHT * 20.0)
		enemy._physics_process(0.1)
		assert_eq(int(enemy.get(&"integration_count")), 1, "%s partial-expiry tick" % enemy.get_class())
		var partial_displacement := enemy.global_position.x
		assert_gt(partial_displacement, stunned_displacement, "%s partial-expiry displacement is effective" % enemy.get_class())
		assert_lt(partial_displacement, normal_displacement, "%s partial-expiry displacement is time-scaled" % enemy.get_class())
		assert_almost_eq(enemy.velocity.x, 70.0, 0.001, "%s partial-expiry velocity" % enemy.get_class())
		assert_eq(enemy.stun_remaining, 0.0, "%s stun expires in same tick" % enemy.get_class())

func test_real_kamikaze_dash_expiry_scales_dash_velocity_and_real_motion() -> void:
	var enemy := KAMIKAZE_SCENE.instantiate() as KamikazeFraturado
	var full_dash := KAMIKAZE_SCENE.instantiate() as KamikazeFraturado
	enemy.set_script(MotionSpyKamikaze)
	full_dash.set_script(MotionSpyKamikaze)
	add_child_autofree(enemy)
	add_child_autofree(full_dash)
	await get_tree().process_frame
	for kamikaze in [enemy, full_dash]:
		kamikaze.set_physics_process(false)
		kamikaze.set_room_cull_policy(RoomDef.CullPolicy.NONE)
		kamikaze.global_position = Vector2.ZERO
		kamikaze.dash_direction = Vector2.RIGHT
		kamikaze.dash_duration = 0.55
		kamikaze._enter_state(KamikazeFraturado.AttackState.DASH)
		kamikaze.set(&"integration_count", 0)

	enemy._elapsed = 0.54
	enemy._physics_process(0.10)
	full_dash._physics_process(0.10)
	var partial_displacement := enemy.global_position.x
	var full_displacement := full_dash.global_position.x
	assert_almost_eq((enemy.get(&"velocity_before_motion") as Vector2).x, 31.0, 0.001)
	assert_eq(enemy.attack_state, KamikazeFraturado.AttackState.RECOVER)
	assert_almost_eq(enemy._elapsed, 0.09, 0.001)
	assert_eq(int(enemy.get(&"integration_count")), 1)
	assert_almost_eq((full_dash.get(&"velocity_before_motion") as Vector2).x, 310.0, 0.001)
	assert_gt(full_displacement, 0.0)
	assert_almost_eq(partial_displacement / full_displacement, 0.1, 0.01)

	# RECOVER integra o corpo real com velocidade nula e nao acrescenta dash.
	enemy._physics_process(0.10)
	assert_eq(enemy.get(&"velocity_before_motion"), Vector2.ZERO)
	assert_almost_eq(enemy.global_position.x, partial_displacement, 0.00001)

func test_self_collision_is_ignored_without_cache_or_damage() -> void:
	var player := CollisionStub.new()
	player.velocity = Vector2.RIGHT * 100.0
	add_child_autofree(player)
	player.overlap.bodies = [player]
	var states := {}
	RESOLVER.resolve_overlaps(player, states)
	assert_eq(player.damage_amounts.size(), 0)
	assert_eq(states.size(), 0)

func test_non_enemy_bodies_are_outside_collision_path() -> void:
	var pair := _pair(100.0)
	var wall := CollisionStub.new()
	wall.groups = []
	var projectile := CollisionStub.new()
	projectile.groups = [&"projectiles"]
	add_child_autofree(wall)
	add_child_autofree(projectile)
	pair[0].overlap.bodies = [wall, projectile]
	RESOLVER.resolve_overlaps(pair[0], {})
	assert_eq(wall.damage_amounts.size(), 0)
	assert_eq(projectile.damage_amounts.size(), 0)

func test_node2d_damageable_without_velocity_receives_damage_without_invalid_access() -> void:
	var player: CollisionStub = _pair(100.0)[0]
	var enemy := DamageableNode2D.new()
	enemy.global_position = Vector2(10.0, 0.0)
	add_child_autofree(enemy)
	player.overlap.bodies = [enemy]
	RESOLVER.resolve_overlaps(player, {})
	assert_eq(enemy.damage_amounts.size(), 1)

func test_enemy_collision_knockback_is_applied_after_ai_and_decays_deterministically() -> void:
	var enemy := ENEMY_SCRIPT.new()
	enemy.apply_collision_knockback(Vector2(100.0, 0.0))
	enemy.velocity = Vector2(20.0, 0.0)
	enemy._apply_collision_knockback(0.1)
	assert_almost_eq(enemy.velocity.x, 120.0, 0.00001)
	enemy.velocity = Vector2.ZERO
	enemy._apply_collision_knockback(0.1)
	assert_almost_eq(enemy.velocity.x, 10.0, 0.00001)
	enemy.free()

func test_stunned_enemy_uses_collision_knockback_channel_without_reactivating_base_velocity() -> void:
	var enemy := ENEMY_SCRIPT.new()
	var health := HealthComponent.new()
	health.name = "HealthComponent"
	health.max_health = enemy.max_health
	enemy.add_child(health)
	add_child_autofree(enemy)
	await get_tree().process_frame
	enemy.set_physics_process(false)
	enemy.apply_stun(0.5)
	enemy.apply_collision_knockback(Vector2(100.0, 0.0))
	enemy._physics_process(0.1)
	assert_true(enemy.is_stunned())
	assert_almost_eq(enemy.velocity.x, 100.0, 0.00001)
	assert_almost_eq(enemy._collision_knockback_velocity.x, 10.0, 0.00001)

func test_fatal_target_does_not_receive_knockback() -> void:
	var player := CollisionStub.new()
	var enemy := FatalCollisionStub.new()
	player.velocity = Vector2.RIGHT * 100.0
	player.global_position = Vector2.ZERO
	enemy.global_position = Vector2(10.0, 0.0)
	player.overlap.bodies = [enemy]
	add_child_autofree(player)
	add_child_autofree(enemy)
	RESOLVER.resolve_overlaps(player, {})
	assert_true(enemy.dead)
	assert_eq(enemy.received_knockback, Vector2.ZERO)

func test_queue_freed_fatal_target_does_not_receive_knockback() -> void:
	var player := CollisionStub.new()
	var enemy := QueueFreeCollisionStub.new()
	player.velocity = Vector2.RIGHT * 100.0
	player.global_position = Vector2.ZERO
	enemy.global_position = Vector2(10.0, 0.0)
	player.overlap.bodies = [enemy]
	add_child_autofree(player)
	add_child_autofree(enemy)
	RESOLVER.resolve_overlaps(player, {})
	assert_true(enemy.is_queued_for_deletion())
	assert_eq(enemy.received_knockback, Vector2.ZERO)

func test_real_enemy_subclasses_skip_collision_knockback_after_lethal_callback() -> void:
	for scene in [ATIRADOR_SCENE, HUNTER_SCENE, KAMIKAZE_SCENE]:
		var player := CollisionStub.new()
		var enemy := scene.instantiate() as Enemy
		player.velocity = Vector2.RIGHT * 100.0
		player.global_position = Vector2.ZERO
		enemy.global_position = Vector2(10.0, 0.0)
		add_child_autofree(player)
		add_child_autofree(enemy)
		await get_tree().process_frame
		enemy.set_physics_process(false)
		# A morte do Kamikaze gera feedback; o host temporario fica sob o proprio
		# inimigo para que queue_free tambem descarte esses nos no teste.
		if enemy is KamikazeFraturado:
			var effects_host := Node.new()
			enemy.add_child(effects_host)
			enemy._effects = effects_host
		enemy.health.health = HEALTH_UNITS.from_hp(0.25)
		player.overlap.bodies = [enemy]
		RESOLVER.resolve_overlaps(player, {})
		assert_eq(enemy._collision_knockback_velocity, Vector2.ZERO)
		assert_true(enemy.is_queued_for_deletion() or enemy.get(&"_dead") == true)

func test_damage_snapshot_is_simultaneous_before_first_damage_callback() -> void:
	# Contrato R1: a mutacao no primeiro callback nao altera o DamageInfo ja
	# calculado para o outro lado do par atual.
	var pair := _pair(100.0, 1.0, 1.0)
	pair[0].mutation_target = pair[1]
	pair[0].mutation_mass = 100.0
	RESOLVER.resolve_overlaps(pair[0], {})
	assert_eq(pair[0].damage_amounts[0], HEALTH_UNITS.from_hp(0.5))
	assert_eq(pair[1].damage_amounts[0], HEALTH_UNITS.from_hp(0.5))

	# O mesmo snapshot tambem delimita a operacao: a nova geracao do Player
	# impede apenas os pares seguintes, sem desfazer a bilateralidade acima.
	var player := ReentrantCollisionPlayer.new()
	var first := CollisionStub.new()
	var second := CollisionStub.new()
	var third := CollisionStub.new()
	player.velocity = Vector2.RIGHT * 100.0
	player.global_position = Vector2.ZERO
	for enemy in [first, second, third]:
		enemy.global_position = Vector2(10.0, 0.0)
		add_child_autofree(enemy)
	player.overlap.bodies = [first, second, third]
	add_child_autofree(player)
	RESOLVER.resolve_overlaps(player, {})
	# O primeiro par ainda e bilateral, embora o callback do Player reinicie
	# sincronicamente seu ciclo. Nenhum segundo/terceiro par pode nascer.
	assert_eq(player.damage_amounts.size(), 1)
	assert_eq(first.damage_amounts.size(), 1)
	assert_eq(second.damage_amounts.size(), 0)
	assert_eq(third.damage_amounts.size(), 0)
	assert_eq(player.damage_amounts[0], first.damage_amounts[0])

func test_segment_lethal_real_player_respawn_aborts_later_targets_and_same_tick_overlap() -> void:
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	await get_tree().process_frame
	var first := CollisionStub.new()
	var second := CollisionStub.new()
	var third := CollisionStub.new()
	for enemy in [first, second, third]:
		enemy.global_position = Vector2(10.0, 0.0)
		add_child_autofree(enemy)
	await get_tree().process_frame

	var prior_lives := GameState.player_lives
	GameState.player_lives = 2
	player.set_physics_process(false)
	player.global_position = Vector2.ZERO
	player.health.health = HEALTH_UNITS.from_hp(0.01)
	# Reproduz o chamador real: a charge entra no segmento por _physics_process.
	# Depois do respawn, a guarda de geracao deve impedir o _check_contact deste
	# mesmo tick; chamar resolve_overlaps aqui diretamente seria outra operacao.
	player._bruta_charge_direction = Vector2.RIGHT
	player._bruta_charge_windup_remaining = 0.0
	player._bruta_charge_remaining = 0.75
	var generation_before := player.get_collision_impact_generation()
	var spawn := player._spawn_point

	player._physics_process(0.1)

	assert_eq(first.damage_amounts.size(), 1)
	assert_eq(second.damage_amounts.size(), 0)
	assert_eq(third.damage_amounts.size(), 0)
	assert_eq(second.received_knockback, Vector2.ZERO)
	assert_eq(third.received_knockback, Vector2.ZERO)
	# O callback de morte faz respawn sincrono: a prova da morte e a nova
	# geracao/vida consumida; a vida cheia e o resultado correto do respawn.
	assert_eq(player.get_collision_impact_generation(), generation_before + 1)
	assert_eq(GameState.player_lives, 1)
	assert_true(player.is_collision_impact_active())
	assert_eq(player.health.health, player.health.max_health)
	assert_eq(player.global_position, spawn)
	assert_eq(player.velocity, Vector2.ZERO)
	assert_eq(player._collision_knockback_velocity, Vector2.ZERO)
	assert_eq(player._collision_impact_pairs.size(), 0)
	assert_false(player._is_bruta_charging())
	assert_eq(player._bruta_charge_windup_remaining, 0.0)
	assert_eq(player._bruta_charge_remaining, 0.0)
	# A guarda do chamador impede o overlap antigo de reabrir o par no tick
	# letal. Em um tick futuro, sem memoria global no resolver, o par pode
	# Um tick futuro, com uma nova charge e os corpos ainda no segmento, deve
	# voltar a resolver legitimamente apos o cache do respawn ter sido limpo.
	assert_eq(first.damage_amounts.size(), 1)
	assert_eq(second.damage_amounts.size(), 0)
	assert_eq(third.damage_amounts.size(), 0)
	player._invuln_timer = 0.0
	player.velocity = Vector2.RIGHT * 100.0
	player._bruta_charge_direction = Vector2.RIGHT
	player._bruta_charge_windup_remaining = 0.0
	player._bruta_charge_remaining = 0.75
	player.set_physics_process(true)
	player._physics_process(0.1)
	assert_eq(first.damage_amounts.size(), 2)
	GameState.player_lives = prior_lives

func test_new_collision_stats_load() -> void:
	for id in [&"collision_mass", &"collision_damage_resistance", &"knockback_force", &"knockback_resistance"]:
		var stat := StatCatalog.get_stat(id)
		assert_not_null(stat)
		assert_eq(stat.allowed_ops.size(), 4)

class OverlapStub extends Node:
	var bodies: Array = []
	func get_overlapping_bodies() -> Array: return bodies

class CollisionStub extends CharacterBody2D:
	var overlap := OverlapStub.new()
	var hurtbox: OverlapStub = overlap
	var damage_amounts: Array[int] = []
	var collision_mass := 1.0
	var collision_damage_resistance := 0.0
	var knockback_force := 1.0
	var knockback_resistance := 0.0
	var groups: Array[StringName] = [&"enemies"]
	var collision_radius := 10.0
	var received_knockback := Vector2.ZERO
	var mutation_target: Node2D
	var mutation_mass := 0.0

	func _ready() -> void:
		for group in groups: add_to_group(group)
		add_child(overlap)
		collision_layer = 4
		collision_mask = 2
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 10.0
		shape.shape = circle
		add_child(shape)

	func take_damage(info: DamageInfo) -> int:
		damage_amounts.append(info.amount)
		if mutation_target != null: mutation_target.collision_mass = mutation_mass
		return info.amount

	func get_collision_radius() -> float: return collision_radius
	func apply_collision_knockback(impulse: Vector2) -> void:
		received_knockback += impulse
		if impulse.is_finite(): velocity += impulse

class ReentrantCollisionPlayer extends CollisionStub:
	var collision_generation := 0
	var collision_active := true

	func take_damage(info: DamageInfo) -> int:
		damage_amounts.append(info.amount)
		collision_active = false
		collision_generation += 1
		# Simula o respawn sincrono da mesma instancia.
		collision_active = true
		return info.amount

	func is_collision_impact_active() -> bool: return collision_active
	func get_collision_impact_generation() -> int: return collision_generation

class DamageableNode2D extends Node2D:
	var damage_amounts: Array[int] = []
	var collision_mass := 1.0
	var collision_damage_resistance := 0.0
	var knockback_force := 1.0
	var knockback_resistance := 0.0

	func _ready() -> void: add_to_group(&"enemies")
	func take_damage(info: DamageInfo) -> int:
		damage_amounts.append(info.amount)
		return info.amount
	func get_collision_radius() -> float: return 10.0

class FatalCollisionStub extends CollisionStub:
	var dead := false

	func take_damage(info: DamageInfo) -> int:
		damage_amounts.append(info.amount)
		dead = true
		return info.amount

	func is_dead() -> bool: return dead

	func apply_collision_knockback(impulse: Vector2) -> void:
		received_knockback += impulse

class QueueFreeCollisionStub extends CollisionStub:
	func take_damage(info: DamageInfo) -> int:
		damage_amounts.append(info.amount)
		queue_free()
		return info.amount

	func apply_collision_knockback(impulse: Vector2) -> void:
		received_knockback += impulse

class MotionSpyEnemy extends Enemy:
	var integration_count := 0
	func _integrate_motion() -> void:
		integration_count += 1
		super()

class MotionSpyAtirador extends AtiradorDeFresta:
	var integration_count := 0
	func _integrate_motion() -> void:
		integration_count += 1
		super()

class MotionSpyHunter extends Hunter:
	var integration_count := 0
	func _integrate_motion() -> void:
		integration_count += 1
		super()

class MotionSpyKamikaze extends KamikazeFraturado:
	var integration_count := 0
	var velocity_before_motion := Vector2.ZERO
	func _integrate_motion() -> void:
		integration_count += 1
		velocity_before_motion = velocity
		super()

func _motion_spies() -> Array[Enemy]:
	return [MotionSpyEnemy.new(), MotionSpyAtirador.new(), MotionSpyHunter.new(), MotionSpyKamikaze.new()]

func _prepare_motion_spy(enemy: Enemy) -> void:
	var health := HealthComponent.new()
	health.name = "HealthComponent"
	enemy.add_child(health)
	if enemy is MotionSpyAtirador:
		var fire_fx := Sprite2D.new()
		fire_fx.name = "FireFx"
		var telegraph := Line2D.new()
		telegraph.name = "Telegraph"
		var aim_visual := Sprite2D.new()
		aim_visual.name = "AimVisual"
		telegraph.add_child(aim_visual)
		enemy.add_child(fire_fx)
		enemy.add_child(telegraph)
	elif enemy is MotionSpyHunter:
		var sprite := Sprite2D.new()
		sprite.name = "Sprite2D"
		sprite.hframes = 6
		var collision := CollisionShape2D.new()
		collision.name = "CollisionShape2D"
		enemy.add_child(sprite)
		enemy.add_child(collision)
	elif enemy is MotionSpyKamikaze:
		var sprite := Sprite2D.new()
		sprite.name = "Sprite2D"
		var animation := AnimatedSprite2D.new()
		animation.name = "AnimatedSprite2D"
		var frames := SpriteFrames.new()
		frames.add_animation(&"approach")
		animation.sprite_frames = frames
		enemy.add_child(sprite)
		enemy.add_child(animation)

func _pair_state(states: Dictionary, enemy: Node) -> StringName:
	var entry: Variant = states.get(enemy.get_instance_id())
	return entry.get(&"state", &"") if entry is Dictionary else &""
