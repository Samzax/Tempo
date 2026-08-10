extends GutTest

const DEBRIS := preload("res://scenes/world/debris.tscn")
const PROJECTILE := preload("res://scenes/projectiles/enemy_projectile.tscn")
const DEBRIS_SCRIPT := preload("res://scripts/world/debris.gd")

func test_debris_has_world_collision_and_is_not_an_enemy() -> void:
	var debris := DEBRIS.instantiate()
	add_child_autofree(debris)
	await get_tree().process_frame
	assert_eq(debris.collision_layer, 1)
	assert_eq(debris.collision_mask, 2)
	assert_true(debris.is_in_group("debris"))
	assert_false(debris.is_in_group("enemies"))

func test_debris_health_scales_by_size_and_fragments_large_to_medium() -> void:
	var debris := DEBRIS.instantiate()
	add_child_autofree(debris)
	await get_tree().process_frame
	assert_eq(debris.health.max_health, 6.0)
	debris._on_died(DamageInfo.new())
	await get_tree().process_frame
	assert_eq(get_tree().get_nodes_in_group("debris").size(), 2)
	for fragment in get_tree().get_nodes_in_group("debris"):
		assert_eq(fragment.size_class, DEBRIS_SCRIPT.SizeClass.MEDIUM)
	var medium := DEBRIS.instantiate()
	medium.size_class = DEBRIS_SCRIPT.SizeClass.MEDIUM
	add_child_autofree(medium)
	await get_tree().process_frame
	assert_eq(medium.health.max_health, 3.0)
	var small := DEBRIS.instantiate()
	small.size_class = DEBRIS_SCRIPT.SizeClass.SMALL
	add_child_autofree(small)
	await get_tree().process_frame
	assert_eq(small.health.max_health, 1.0)
	for remaining in get_tree().get_nodes_in_group("debris"):
		remaining.queue_free()
	await get_tree().process_frame

func test_small_debris_does_not_fragment() -> void:
	var debris := DEBRIS.instantiate()
	debris.size_class = DEBRIS_SCRIPT.SizeClass.SMALL
	add_child_autofree(debris)
	await get_tree().process_frame
	var debris_count_before := get_tree().get_nodes_in_group("debris").size()
	debris._on_died(DamageInfo.new())
	assert_true(debris.is_queued_for_deletion())
	await get_tree().process_frame
	assert_eq(get_tree().get_nodes_in_group("debris").size(), debris_count_before - 1)

func test_debris_culls_after_lifetime_without_fragmenting() -> void:
	var debris := DEBRIS.instantiate()
	debris.lifetime = 0.1
	add_child_autofree(debris)
	await get_tree().process_frame
	debris._physics_process(0.1)
	assert_true(debris.is_queued_for_deletion())

func test_enemy_projectile_uses_hostile_layer_and_world_player_mask() -> void:
	var projectile := PROJECTILE.instantiate()
	add_child_autofree(projectile)
	assert_eq(projectile.collision_layer, 16)
	assert_eq(projectile.collision_mask, 3)
