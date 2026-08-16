extends GutTest

const DEBRIS := preload("res://scenes/world/debris.tscn")
const PROJECTILE := preload("res://scenes/projectiles/enemy_projectile.tscn")
const DEBRIS_SCRIPT := preload("res://scripts/world/debris.gd")
const HEALTH_UNITS := preload("res://scripts/components/health_units.gd")
const METEOR_ASSETS := {
	"upper_meteorite_large.png": [Vector2i(40, 40), "BF2851C2BEB7A80128D8F48C3A0082DDA65982307CCAACF22202A8DC5A6A78B5"],
	"upper_meteorite_medium.png": [Vector2i(24, 24), "D86D7CE03EF662299C17FD8B739706A667BED372E5013D5FC97914EA67700B7C"],
	"upper_meteorite_small.png": [Vector2i(14, 14), "7E5F594546B7BC7497CB47E9BCAACC26A07DADFEED587D764833090152FDFEDA"],
	"upper_meteorite_hit_strip.png": [Vector2i(64, 32), "C3E7289D9AB16A7806BE2F4AFB5FF35F1AC62057B4F5FBE2CA8CAC4A0A3667D7"],
	"upper_meteorite_break_strip.png": [Vector2i(240, 48), "9EBCF076A8109C6C40AC95F9A475C9BD985893E683E27930CB2459B8DD09F9AD"],
}

func test_meteorite_assets_have_contract_dimensions_and_hashes() -> void:
	for filename in METEOR_ASSETS:
		var path: String = "res://assets/sprites/world/meteorites/" + filename
		var image := Image.load_from_file(ProjectSettings.globalize_path(path))
		assert_eq(image.get_size(), METEOR_ASSETS[filename][0], filename)
		assert_eq(FileAccess.get_sha256(ProjectSettings.globalize_path(path)).to_upper(), METEOR_ASSETS[filename][1], filename)

func test_debris_has_world_collision_and_is_not_an_enemy() -> void:
	var debris := DEBRIS.instantiate()
	add_child_autofree(debris)
	await get_tree().process_frame
	assert_eq(debris.collision_layer, 1)
	assert_eq(debris.collision_mask, 2)
	assert_true(debris.is_in_group("debris"))
	assert_false(debris.is_in_group("enemies"))

func test_debris_uses_independent_exact_convex_hulls_and_native_scale() -> void:
	var expected := [
		PackedVector2Array([Vector2(-17,-4),Vector2(-12,-10),Vector2(-3,-14),Vector2(9,-16),Vector2(11,-13),Vector2(16,0),Vector2(9,11),Vector2(1,15),Vector2(-5,14),Vector2(-12,8)]),
		PackedVector2Array([Vector2(-10,1),Vector2(-7,-4),Vector2(-3,-9),Vector2(2,-9),Vector2(10,-1),Vector2(10,6),Vector2(5,9),Vector2(-3,9),Vector2(-7,6)]),
		PackedVector2Array([Vector2(-6,-4),Vector2(-1,-5),Vector2(4,-3),Vector2(6,1),Vector2(4,4),Vector2(-3,4),Vector2(-6,1)])
	]
	var instances: Array[Debris] = []
	for kind in 3:
		var debris := DEBRIS.instantiate() as Debris
		debris.size_class = kind
		add_child_autofree(debris)
		await get_tree().process_frame
		assert_true(debris.collision_shape.shape is ConvexPolygonShape2D)
		assert_eq((debris.collision_shape.shape as ConvexPolygonShape2D).points, expected[kind])
		assert_eq(debris.scale, Vector2.ONE)
		instances.append(debris)
	assert_ne(instances[0].collision_shape.shape, instances[1].collision_shape.shape)
	assert_ne(instances[1].collision_shape.shape, instances[2].collision_shape.shape)

func test_debris_health_scales_by_size_and_fragments_large_to_medium() -> void:
	var debris := DEBRIS.instantiate()
	add_child_autofree(debris)
	await get_tree().process_frame
	assert_eq(debris.health.max_health, HEALTH_UNITS.from_hp(6.0))
	debris._on_died(DamageInfo.new())
	await get_tree().process_frame
	assert_eq(get_tree().get_nodes_in_group("debris").size(), 2)
	for fragment in get_tree().get_nodes_in_group("debris"):
		assert_eq(fragment.size_class, DEBRIS_SCRIPT.SizeClass.MEDIUM)
	var medium := DEBRIS.instantiate()
	medium.size_class = DEBRIS_SCRIPT.SizeClass.MEDIUM
	add_child_autofree(medium)
	await get_tree().process_frame
	assert_eq(medium.health.max_health, HEALTH_UNITS.from_hp(3.0))
	var small := DEBRIS.instantiate()
	small.size_class = DEBRIS_SCRIPT.SizeClass.SMALL
	add_child_autofree(small)
	await get_tree().process_frame
	assert_eq(small.health.max_health, HEALTH_UNITS.from_hp(1.0))
	for remaining in get_tree().get_nodes_in_group("debris"):
		remaining.queue_free()
	await get_tree().process_frame

func test_debris_take_damage_null_returns_zero() -> void:
	var debris := DEBRIS.instantiate()
	add_child_autofree(debris)
	await get_tree().process_frame
	var before: int = debris.health.health

	assert_eq(debris.take_damage(null), 0)
	assert_eq(debris.health.health, before)

func test_debris_take_damage_ignores_deep_trigger() -> void:
	var debris := DEBRIS.instantiate()
	add_child_autofree(debris)
	await get_tree().process_frame
	var before: int = debris.health.health
	var info := DamageInfo.new()
	info.trigger_depth = 4

	assert_eq(debris.take_damage(info), 0)
	assert_eq(debris.health.health, before)

func test_debris_take_damage_returns_partial_and_lethal_units() -> void:
	var debris := DEBRIS.instantiate()
	add_child_autofree(debris)
	await get_tree().process_frame

	assert_eq(debris.take_damage(_damage(150)), 150)
	assert_eq(debris.health.health, HEALTH_UNITS.from_hp(4.5))
	assert_eq(debris.take_damage(_damage(1000)), 450)
	await get_tree().process_frame
	for remaining in get_tree().get_nodes_in_group("debris"):
		remaining.queue_free()
	await get_tree().process_frame

func _damage(amount: int) -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = amount
	return info

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

func test_debris_applies_drift_lifetime_and_room_bounds_cull_only_after_entry() -> void:
	var debris := DEBRIS.instantiate() as Debris
	debris.global_position = Vector2(-50.0, 20.0)
	debris.drift_velocity = Vector2(12.0, 5.0)
	debris.lifetime = 9.0
	debris.set_room_bounds(Rect2(Vector2.ZERO, Vector2(100.0, 100.0)))
	add_child_autofree(debris)
	await get_tree().process_frame
	assert_eq(debris.linear_velocity, Vector2(12.0, 5.0))
	debris._physics_process(0.1)
	assert_false(debris.is_queued_for_deletion())
	debris.global_position = Vector2(50.0, 50.0)
	debris._physics_process(0.1)
	debris.global_position = Vector2(250.0, 50.0)
	debris._physics_process(0.1)
	assert_true(debris.is_queued_for_deletion())

func test_debris_hit_and_fatal_fx_have_expected_frames_scales_and_autofree() -> void:
	var debris := DEBRIS.instantiate() as Debris
	add_child_autofree(debris)
	await get_tree().process_frame
	debris._on_damaged(_damage(1.0), 1.0)
	var hit := debris.get_parent().get_child(-1) as AnimatedSprite2D
	assert_eq(debris.sprite.z_index, 2)
	assert_eq(hit.sprite_frames.get_frame_count(&"play"), 2)
	assert_eq(hit.sprite_frames.get_animation_speed(&"play"), 20.0)
	assert_eq(hit.scale, Vector2.ONE * 1.25)
	debris._on_died(_damage(10.0))
	var fatal := debris.get_parent().get_child(-1) as AnimatedSprite2D
	assert_eq(fatal.z_index, 1)
	assert_eq(fatal.sprite_frames.get_frame_count(&"play"), 5)
	assert_eq(fatal.sprite_frames.get_animation_speed(&"play"), 25.0)
	assert_eq(fatal.scale, Vector2.ONE)
	await get_tree().create_timer(0.25).timeout
	assert_false(is_instance_valid(hit))
	assert_false(is_instance_valid(fatal))

func test_debris_collision_does_not_damage_non_player_or_create_damage_without_body_entered() -> void:
	var debris := DEBRIS.instantiate() as Debris
	add_child_autofree(debris)
	await get_tree().process_frame
	var body := Node2D.new()
	add_child_autofree(body)
	debris._on_body_entered(body)
	assert_eq(debris.health.health, HEALTH_UNITS.from_hp(6.0))

func test_enemy_projectile_uses_hostile_layer_and_world_player_mask() -> void:
	var projectile := PROJECTILE.instantiate()
	add_child_autofree(projectile)
	assert_eq(projectile.collision_layer, 16)
	assert_eq(projectile.collision_mask, 3)
