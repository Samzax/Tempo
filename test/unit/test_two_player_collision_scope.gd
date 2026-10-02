extends GutTest

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const RESOLVER := preload("res://scripts/combat/collision_impact_resolver.gd")
const HEALTH_UNITS := preload("res://scripts/components/health_units.gd")
const PROJECTILE_SCENE := preload("res://scenes/projectiles/enemy_projectile.tscn")
const DEBRIS_SCENE := preload("res://scenes/world/debris.tscn")

const FIRST_PLAYER_LOOKUP := "get_first_node_in_group(\"player\")"
const SINGLE_PLAYER_TOKEN := "&\"player\""
const PER_BODY_GROUP_TEST_STRINGNAME := "is_in_group(&\"player\")"
const PER_BODY_GROUP_TEST_STRING := "is_in_group(\"player\")"

const GUARDED_SOURCES: Array[String] = [
	"res://scripts/combat/collision_impact_resolver.gd",
	"res://scripts/world/debris.gd",
	"res://scripts/projectiles/enemy_projectile.gd",
	"res://scripts/projectiles/bullet.gd",
	"res://scripts/components/hitbox.gd",
	"res://scripts/components/hurtbox.gd",
	"res://scripts/deployables/engineer_deployable.gd",
	"res://scripts/effects/engine_trail_manager.gd",
	"res://scripts/player/player.gd",
	"res://scripts/enemies/bosses/wings/laser_beam_2d.gd",
	"res://scripts/enemies/bosses/wings/casulo_explosivo.gd",
	"res://scripts/components/health_component.gd",
	"res://scripts/combat/damage_info.gd",
]

const EXEMPT_SOURCES: Array[String] = [
	"res://scripts/enemies/enemy.gd",
	"res://scripts/ui/hud.gd",
]

class ContactEnemy extends CharacterBody2D:
	var damage_amounts: Array[int] = []
	var damage_sources: Array = []

	func _ready() -> void:
		add_to_group(&"enemies")

	func take_damage(info: DamageInfo) -> int:
		damage_amounts.append(info.amount)
		damage_sources.append(info.source)
		return info.amount

var _saved_lives := 3
var _hit_players: Array = []
var _hit_infos: Array = []

func before_each() -> void:
	_saved_lives = GameState.player_lives
	GameState.player_lives = 9
	clear_signal_watcher()
	_hit_players.clear()
	_hit_infos.clear()
	if not EventBus.player_hit.is_connected(_on_player_hit):
		EventBus.player_hit.connect(_on_player_hit)

func after_each() -> void:
	if EventBus.player_hit.is_connected(_on_player_hit):
		EventBus.player_hit.disconnect(_on_player_hit)
	GameState.player_lives = _saved_lives

func _on_player_hit(player: Node, info: DamageInfo) -> void:
	_hit_players.append(player)
	_hit_infos.append(info)

func _record_damage(info: DamageInfo, _actual_drop: int, sink: Array) -> void:
	sink.append(info)

func _units(amount: int) -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = amount
	return info

func _player() -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	await get_tree().process_frame
	return player

func _contact_player() -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	player.set_physics_process(false)
	return player

func _circle_shape(radius: float) -> CollisionShape2D:
	var collision := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	collision.shape = circle
	return collision

func _contact_setup(a: Player, b: Player) -> ContactEnemy:
	var enemy := ContactEnemy.new()
	enemy.collision_layer = CollisionLayers.ENEMY
	enemy.collision_mask = 0
	enemy.add_child(_circle_shape(10.0))
	add_child_autofree(enemy)
	enemy.global_position = Vector2.ZERO
	a.global_position = Vector2.ZERO
	b.global_position = Vector2.ZERO
	a.velocity = Vector2.RIGHT * 100.0
	b.velocity = Vector2.RIGHT * 100.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_gt(a.hurtbox.get_overlapping_bodies().size(), 0, "player a overlaps the contact enemy")
	assert_gt(b.hurtbox.get_overlapping_bodies().size(), 0, "player b overlaps the contact enemy")
	return enemy

func test_iframes_de_um_jogador_nao_protegem_o_outro() -> void:
	var a := await _player()
	var b := await _player()
	var a_full: int = a.health.health
	var b_full: int = b.health.health

	a.grant_invuln(10.0)

	assert_eq(a.take_damage(_units(100)), 0)
	assert_eq(a.health.health, a_full)
	assert_true(a.is_invulnerable())

	assert_eq(b.take_damage(_units(100)), 100)
	assert_eq(b.health.health, b_full - 100)
	assert_false(b.is_invulnerable())

func test_escudo_de_um_jogador_nao_absorve_o_dano_do_outro() -> void:
	var a := await _player()
	var b := await _player()
	var a_full: int = a.health.health
	var b_full: int = b.health.health

	a.grant_shield_charge(&"estacao")

	assert_eq(b.take_damage(_units(100)), 100)
	assert_eq(b.health.health, b_full - 100)
	assert_eq(a._shield_charges.size(), 1)

	assert_eq(a.take_damage(_units(100)), 0)
	assert_eq(a.health.health, a_full)
	assert_eq(a._shield_charges.size(), 0)

	assert_eq(a.take_damage(_units(100)), 100)
	assert_eq(a.health.health, a_full - 100)

func test_pares_de_impacto_independentes_por_instancia_e_credito_por_par() -> void:
	var a := _contact_player()
	var b := _contact_player()
	var enemy := await _contact_setup(a, b)
	var a_full: int = a.health.health
	var b_full: int = b.health.health
	var a_infos: Array = []
	var b_infos: Array = []
	a.health.damaged.connect(_record_damage.bind(a_infos))
	b.health.damaged.connect(_record_damage.bind(b_infos))

	RESOLVER.resolve_overlaps(a, a._collision_impact_pairs)
	RESOLVER.resolve_overlaps(b, b._collision_impact_pairs)

	assert_eq(enemy.damage_sources, [a, b], "each player resolves its own pair")
	assert_gt(enemy.damage_amounts[0], 0)
	assert_gt(enemy.damage_amounts[1], 0)
	assert_eq(a._collision_impact_pairs.size(), 1)
	assert_eq(b._collision_impact_pairs.size(), 1)
	assert_eq(a_infos.size(), 1)
	assert_eq(b_infos.size(), 1)
	assert_eq(a_infos[0].source, enemy)
	assert_eq(b_infos[0].source, enemy)
	assert_lt(a.health.health, a_full)
	assert_lt(b.health.health, b_full)

	var b_health_after: int = b.health.health
	a._collision_impact_pairs.clear()
	RESOLVER.resolve_overlaps(a, a._collision_impact_pairs)

	assert_eq(enemy.damage_sources.size(), 3)
	assert_eq(enemy.damage_sources[2], a)
	assert_eq(a._collision_impact_pairs.size(), 1)
	assert_eq(b._collision_impact_pairs.size(), 1)
	assert_eq(a_infos.size(), 2)
	assert_eq(b_infos.size(), 1)
	assert_eq(b.health.health, b_health_after)

	RESOLVER.resolve_overlaps(b, b._collision_impact_pairs)

	assert_eq(enemy.damage_sources.size(), 3)
	assert_eq(b._collision_impact_pairs.size(), 1)
	assert_eq(b_infos.size(), 1)
	assert_eq(b.health.health, b_health_after)

func test_morte_de_um_jogador_nao_desarma_nem_oculta_o_outro() -> void:
	var a := _contact_player()
	var b := _contact_player()
	var enemy := await _contact_setup(a, b)
	RESOLVER.resolve_overlaps(b, b._collision_impact_pairs)
	assert_eq(enemy.damage_sources, [b], "only the pair of b was spent")
	assert_eq(b._collision_impact_pairs.size(), 1)
	b.health.reset()

	a.set_physics_process(true)
	b.set_physics_process(true)
	GameState.player_lives = 1

	a.take_damage(_units(a.health.health))

	assert_false(a.visible)
	assert_false(a.is_physics_processing())
	assert_true(b.visible)
	assert_true(b.is_physics_processing())
	assert_true(b.is_collision_impact_active())
	assert_eq(b._collision_impact_pairs.size(), 1)
	assert_false(b.is_invulnerable())
	assert_eq(b.health.health, b.health.max_health)
	assert_eq(b.take_damage(_units(100)), 100)
	assert_eq(b.health.health, b.health.max_health - 100)

func test_notificacao_de_dano_identifica_a_vitima() -> void:
	var a := await _player()
	var b := await _player()
	var first := _units(10)
	var second := _units(20)

	a.take_damage(first)
	b.take_damage(second)

	assert_eq(_hit_players.size(), 2)
	assert_eq(_hit_players[0], a)
	assert_eq(_hit_players[1], b)
	assert_eq(_hit_infos.size(), 2)
	assert_eq(_hit_infos[0], first)
	assert_eq(_hit_infos[1], second)
	assert_eq(_hit_infos[0].amount, 10)
	assert_eq(_hit_infos[1].amount, 20)

func test_guardas_coop_sem_premissa_de_jogador_unico() -> void:
	_assert_sources_have_no_single_player_lookup()
	var a := _contact_player()
	var b := _contact_player()
	a.global_position = Vector2(40.0, 40.0)
	b.global_position = Vector2(600.0, 340.0)
	_assert_projectile_dies_on_first_contact(a, b)
	_assert_debris_damages_only_the_entered_body(a, b)

func _assert_sources_have_no_single_player_lookup() -> void:
	for path in GUARDED_SOURCES:
		var source := FileAccess.get_file_as_string(path)
		assert_gt(source.length(), 0, path)
		var scan := source.replace(PER_BODY_GROUP_TEST_STRINGNAME, "").replace(PER_BODY_GROUP_TEST_STRING, "")
		assert_false(scan.contains(FIRST_PLAYER_LOOKUP), path)
		assert_false(scan.contains(SINGLE_PLAYER_TOKEN), path)
	for path in EXEMPT_SOURCES:
		var source := FileAccess.get_file_as_string(path)
		assert_gt(source.length(), 0, path)
		assert_true(source.contains(FIRST_PLAYER_LOOKUP), path)

func _assert_projectile_dies_on_first_contact(a: Player, b: Player) -> void:
	var projectile := PROJECTILE_SCENE.instantiate() as EnemyProjectile
	add_child_autofree(projectile)
	var shooter := Node2D.new()
	add_child_autofree(shooter)
	projectile.launch(Vector2(660.0, 40.0), Vector2.LEFT, shooter, 1.0)
	var a_before: int = a.health.health
	var b_before: int = b.health.health

	projectile._on_body_entered(a)

	assert_true(projectile.is_queued_for_deletion())
	assert_eq(a.health.health, a_before - HEALTH_UNITS.from_hp(1.0))
	assert_eq(b.health.health, b_before)
	assert_eq(b.health.health, b.health.max_health)
	assert_eq(_hit_players.size(), 1)
	assert_eq(_hit_players[0], a)
	assert_eq(_hit_infos[0].source, shooter)

func _assert_debris_damages_only_the_entered_body(a: Player, b: Player) -> void:
	_hit_players.clear()
	_hit_infos.clear()
	var debris := DEBRIS_SCENE.instantiate() as Debris
	debris.freeze = true
	debris.global_position = Vector2(300.0, 200.0)
	add_child_autofree(debris)
	await get_tree().process_frame
	var a_before: int = a.health.health
	var b_before: int = b.health.health

	debris._on_body_entered(a)

	assert_eq(a.health.health, a_before - HEALTH_UNITS.from_hp(debris.contact_damage))
	assert_eq(b.health.health, b_before)
	assert_eq(b.health.health, b.health.max_health)
	assert_eq(_hit_players.size(), 1)
	assert_eq(_hit_players[0], a)
	assert_eq(_hit_infos.size(), 1)
	assert_eq(_hit_infos[0].source, debris)
	assert_eq(_hit_infos[0].amount, HEALTH_UNITS.from_hp(debris.contact_damage))
