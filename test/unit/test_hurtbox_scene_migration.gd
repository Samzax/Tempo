extends GutTest

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const DEPLOYABLE_SCENE := preload("res://scenes/deployables/engineer_deployable.tscn")
const BULLET_SCENE := preload("res://scenes/projectiles/bullet.tscn")
const ENEMY_PROJECTILE_SCENE := preload("res://scenes/projectiles/enemy_projectile.tscn")
const DEBRIS_SCENE := preload("res://scenes/world/debris.tscn")
const RESOLVER := preload("res://scripts/combat/collision_impact_resolver.gd")
const CORE := preload("res://scripts/rooms/sector3_core_presentation.gd")
const CHEST := preload("res://scripts/loot/reward_chest.gd")
const HURTBOX_SCRIPT := preload("res://scripts/components/hurtbox.gd")
const HITBOX_SCRIPT := preload("res://scripts/components/hitbox.gd")
const HURTBOX_COMPONENT_PATH := "res://scripts/components/hurtbox.gd"
const MIGRATED_SCENES: Array[String] = [
	"res://scenes/deployables/engineer_deployable.tscn",
	"res://scenes/player/player.tscn",
]

const ENEMY_SCENES: Array[String] = [
	"res://scenes/enemies/enemy.tscn",
	"res://scenes/enemies/hunter.tscn",
	"res://scenes/enemies/kamikaze_fraturado.tscn",
	"res://scenes/enemies/atirador_de_fresta.tscn",
	"res://scenes/enemies/bosses/regente_dos_ecos.tscn",
]

class ImpactEnemyStub extends CharacterBody2D:
	var damage_amounts: Array[int] = []

	func _ready() -> void:
		add_to_group(&"enemies")

	func take_damage(info: DamageInfo) -> int:
		damage_amounts.append(info.amount)
		return info.amount

func _circle_shape(radius: float) -> CollisionShape2D:
	var collision := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	collision.shape = circle
	return collision

func test_player_scene_hurtbox_is_migrated_component_with_authored_collision() -> void:
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	await get_tree().physics_frame

	var hurtbox := player.get_node("Hurtbox") as Hurtbox
	assert_not_null(hurtbox)
	assert_true(hurtbox.get_script() == HURTBOX_SCRIPT)
	assert_eq(hurtbox.get_class(), "Area2D")
	# Paridade numerica estrita da cena migrada: 2 (PLAYER) e 4 (ENEMY).
	assert_eq(hurtbox.collision_layer, 2)
	assert_eq(hurtbox.collision_mask, 4)
	assert_eq(hurtbox.collision_layer, CollisionLayers.PLAYER)
	assert_eq(hurtbox.collision_mask, CollisionLayers.ENEMY)
	assert_true(hurtbox.monitoring)
	assert_true(hurtbox.monitorable)
	assert_true(player.get("hurtbox") == hurtbox)
	assert_eq(hurtbox.get_entity(), player)

	var collision := hurtbox.get_node("CollisionShape2D") as CollisionShape2D
	assert_not_null(collision)
	assert_true(collision.shape is CircleShape2D)
	assert_eq(collision.shape.radius, 8.0)
	assert_eq(hurtbox.get_shape_radius(), 8.0)

func test_deployable_scene_migrates_hurtbox_and_keeps_influence_plain() -> void:
	var deployable := DEPLOYABLE_SCENE.instantiate() as EngineerDeployable
	add_child_autofree(deployable)
	await get_tree().physics_frame

	var hurtbox := deployable.get_node("Hurtbox") as Hurtbox
	assert_not_null(hurtbox)
	assert_true(hurtbox.get_script() == HURTBOX_SCRIPT)
	assert_eq(hurtbox.collision_layer, CollisionLayers.PICKUP)
	assert_eq(hurtbox.collision_mask, CollisionLayers.ENEMY | CollisionLayers.ENEMY_BULLET)
	assert_false(hurtbox.monitoring)
	assert_false(hurtbox.monitorable)
	assert_eq(hurtbox.get_entity(), deployable)

	var influence := deployable.get_node("Influence") as Area2D
	assert_not_null(influence)
	assert_null(influence.get_script())
	assert_false(influence is Hurtbox)
	assert_false(influence is Hitbox)
	assert_eq(influence.collision_layer, 0)
	assert_eq(influence.collision_mask, CollisionLayers.ENEMY)
	assert_true(influence.monitoring)

	var deploy_owner: Node2D = autofree(Node2D.new())
	deployable.configure(EngineerDeployable.Kind.OVERCLOCK_STATION, deploy_owner, Vector2.ZERO)

	assert_eq(influence.collision_mask, CollisionLayers.PLAYER)
	assert_true(hurtbox.monitoring)
	assert_true(hurtbox.monitorable)
	assert_eq(hurtbox.collision_layer, CollisionLayers.PICKUP)
	assert_eq(hurtbox.collision_mask, CollisionLayers.ENEMY | CollisionLayers.ENEMY_BULLET)

## Cada Kind recalcula as mascaras da cena a partir de CollisionLayers.
func test_deployable_kinds_keep_masks_bound_to_collision_layers() -> void:
	var deployable := DEPLOYABLE_SCENE.instantiate() as EngineerDeployable
	add_child_autofree(deployable)
	deployable.set_physics_process(false)
	await get_tree().physics_frame

	var hurtbox := deployable.get_node("Hurtbox") as Hurtbox
	var influence := deployable.get_node("Influence") as Area2D
	assert_not_null(hurtbox)
	assert_not_null(influence)
	var deploy_owner: Node2D = autofree(Node2D.new())

	# Kind.TRAP: contato corpo a corpo com inimigos; hurtbox inerte.
	deployable.configure(EngineerDeployable.Kind.TRAP, deploy_owner, Vector2.ZERO)
	assert_eq(hurtbox.collision_layer, 32)
	assert_eq(hurtbox.collision_mask, 20)
	assert_eq(hurtbox.collision_mask, CollisionLayers.ENEMY | CollisionLayers.ENEMY_BULLET)
	assert_false(hurtbox.monitoring)
	assert_false(hurtbox.monitorable)
	assert_eq(influence.collision_layer, 0)
	assert_eq(influence.collision_mask, 4)
	assert_eq(influence.collision_mask, CollisionLayers.ENEMY)
	assert_eq(hurtbox.get_shape_radius(), 10.0)

	# Kind.DRONE: a hurtbox passa a monitorar projeteis inimigos.
	deployable.configure(EngineerDeployable.Kind.DRONE, deploy_owner, Vector2.ZERO)
	assert_eq(hurtbox.collision_layer, 32)
	assert_eq(hurtbox.collision_mask, 20)
	assert_true(hurtbox.monitoring)
	assert_true(hurtbox.monitorable)
	assert_eq(influence.collision_mask, 4)

	# Kind.OVERCLOCK_STATION: a influence passa a ler o jogador (camada 2).
	deployable.configure(EngineerDeployable.Kind.OVERCLOCK_STATION, deploy_owner, Vector2.ZERO)
	assert_eq(hurtbox.collision_layer, 32)
	assert_eq(hurtbox.collision_mask, 20)
	assert_true(hurtbox.monitoring)
	assert_true(hurtbox.monitorable)
	assert_eq(influence.collision_mask, 2)
	assert_eq(influence.collision_mask, CollisionLayers.PLAYER)


## Coleta recursiva de cenas .tscn sob um diretorio res://.
func _collect_scene_paths(dir_path: String, found: PackedStringArray) -> PackedStringArray:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var full := dir_path.path_join(entry)
			if dir.current_is_dir():
				_collect_scene_paths(full, found)
			elif entry.ends_with(".tscn"):
				found.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return found


## Somente player e engineer_deployable usam o componente e declaram o no Hurtbox.
func test_only_migrated_scenes_reference_hurtbox_component() -> void:
	var referenced: Array[String] = []
	var declared: Array[String] = []
	for scene_path in _collect_scene_paths("res://", PackedStringArray()):
		var text := FileAccess.get_file_as_string(scene_path)
		if text.contains(HURTBOX_COMPONENT_PATH):
			referenced.append(scene_path)
		if text.contains('[node name="Hurtbox"'):
			declared.append(scene_path)
	referenced.sort()
	declared.sort()
	assert_eq(referenced, MIGRATED_SCENES, str(referenced))
	assert_eq(declared, MIGRATED_SCENES, str(declared))


func test_scenes_outside_migration_keep_their_own_scripts() -> void:
	var bullet := BULLET_SCENE.instantiate()
	autofree(bullet)
	assert_true(bullet is Area2D)
	assert_false(bullet is Hurtbox)
	assert_false(bullet is Hitbox)
	assert_not_null(bullet.get_script())
	assert_false(bullet.get_script() == HURTBOX_SCRIPT)
	assert_false(bullet.get_script() == HITBOX_SCRIPT)

	var projectile := ENEMY_PROJECTILE_SCENE.instantiate()
	autofree(projectile)
	assert_true(projectile is Area2D)
	assert_false(projectile is Hurtbox)
	assert_false(projectile is Hitbox)
	assert_not_null(projectile.get_script())
	assert_false(projectile.get_script() == HURTBOX_SCRIPT)
	assert_false(projectile.get_script() == HITBOX_SCRIPT)

	var debris := DEBRIS_SCENE.instantiate()
	autofree(debris)
	assert_false(debris is Area2D)
	assert_false(debris is Hurtbox)
	assert_false(debris is Hitbox)
	assert_not_null(debris.get_script())
	assert_false(debris.get_script() == HURTBOX_SCRIPT)

func test_enemy_scenes_contain_no_hurtbox_areas() -> void:
	for scene_path in ENEMY_SCENES:
		var scene := load(scene_path) as PackedScene
		assert_not_null(scene, scene_path)
		var root := scene.instantiate()
		autofree(root)
		assert_false(root is Area2D, scene_path)
		assert_false(root is Hurtbox, scene_path)
		assert_false(root is Hitbox, scene_path)
		assert_false(root.get_script() == HURTBOX_SCRIPT, scene_path)
		assert_eq(root.find_children("*", "Area2D", true, false).size(), 0, scene_path)

func test_real_player_hurtbox_feeds_collision_impact_resolver() -> void:
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	player.set_physics_process(false)
	player.global_position = Vector2.ZERO
	player.velocity = Vector2.RIGHT * 100.0

	var enemy := ImpactEnemyStub.new()
	enemy.collision_layer = CollisionLayers.ENEMY
	enemy.collision_mask = 0
	enemy.position = Vector2(10.0, 0.0)
	enemy.add_child(_circle_shape(5.0))
	add_child_autofree(enemy)

	await get_tree().physics_frame
	await get_tree().physics_frame

	assert_true(player.hurtbox is Hurtbox)
	assert_eq(player.hurtbox.get_overlapping_bodies().size(), 1)

	var states := {}
	RESOLVER.resolve_overlaps(player, states)

	assert_eq(enemy.damage_amounts.size(), 1)
	assert_gt(enemy.damage_amounts[0], 0)

func test_sector3_ejection_restores_migrated_player_hurtbox() -> void:
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	await get_tree().process_frame

	var hurtbox := player.get_node("Hurtbox") as Hurtbox
	assert_not_null(hurtbox)
	assert_eq(hurtbox.collision_layer, CollisionLayers.PLAYER)
	assert_eq(hurtbox.collision_mask, CollisionLayers.ENEMY)
	assert_true(player.is_physics_processing())

	var core := CORE.new()
	var chest: RewardChest = autofree(CHEST.new())
	core.configure(chest, player)
	add_child_autofree(core)
	await get_tree().process_frame

	core._state = CORE.State.RELEASING
	core._generation = 1
	core._run_ejection(1)

	assert_eq(hurtbox.collision_layer, 0)
	assert_eq(hurtbox.collision_mask, 0)
	assert_eq(player.collision_layer, 0)
	assert_eq(player.collision_mask, 0)
	assert_false(player.is_physics_processing())

	await wait_seconds(0.70)

	assert_eq(hurtbox.collision_layer, CollisionLayers.PLAYER)
	assert_eq(hurtbox.collision_mask, CollisionLayers.ENEMY)
	assert_eq(player.collision_layer, CollisionLayers.PLAYER)
	assert_eq(player.collision_mask, CollisionLayers.WORLD)
	assert_true(player.is_physics_processing())
