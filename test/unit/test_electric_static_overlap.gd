extends GutTest

const AREA_SCRIPT := preload("res://scripts/enemies/bosses/electric_subnet_area.gd")

func _area(radius: float = 18.0) -> ElectricSubnetArea:
	var area := AREA_SCRIPT.new() as ElectricSubnetArea
	area.aura_radius = radius
	add_child_autofree(area)
	return area

func _body(at: Vector2, id: String) -> CharacterBody2D:
	var body := CharacterBody2D.new()
	body.position = at
	body.collision_layer = 2
	body.collision_mask = 0
	body.add_to_group(&"player")
	body.set_meta(&"network_id", id)
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 2.0
	collision.shape = shape
	body.add_child(collision)
	add_child_autofree(body)
	return body

func test_horizontal_and_diagonal_links_use_thick_capsule_geometry() -> void:
	var area := _area()
	var start := Vector2(100.0, 100.0)
	var end := Vector2(160.0, 140.0)
	area.sync_edges([{"a": 1, "b": 2}], {1: start, 2: end})

	var collision := area._shapes["1:2"] as CollisionShape2D
	var capsule := collision.shape as CapsuleShape2D
	var link := end - start
	assert_not_null(collision)
	assert_true(collision.shape is CapsuleShape2D)
	assert_almost_eq(capsule.radius, 18.0, 0.0001)
	assert_almost_eq(capsule.height, link.length() + 36.0, 0.0001)
	assert_eq(collision.global_position, start.lerp(end, 0.5))
	assert_almost_eq(collision.global_rotation, link.angle() + PI * 0.5, 0.0001)
	assert_eq(area.collision_layer, 0)
	assert_eq(area.collision_mask, 2)

func test_real_physics_overlap_detects_inside_body_and_excludes_outside_body() -> void:
	var area := _area()
	var start := Vector2(100.0, 100.0)
	var end := Vector2(200.0, 100.0)
	area.sync_edges([{"a": 1, "b": 2}], {1: start, 2: end})
	var inside := _body(Vector2(150.0, 100.0), "inside")
	var outside := _body(Vector2(150.0, 140.0), "outside")
	await get_tree().physics_frame
	await get_tree().physics_frame

	var overlapping := area.get_overlapping_bodies()
	var query_parameters := PhysicsShapeQueryParameters2D.new()
	query_parameters.shape = area._shapes["1:2"].shape
	query_parameters.transform = area._shapes["1:2"].global_transform
	query_parameters.collision_mask = 2
	var query: Array[Dictionary] = area.get_world_2d().direct_space_state.intersect_shape(query_parameters)
	assert_true(overlapping.has(inside))
	assert_false(overlapping.has(outside))
	assert_true(query.any(func(hit: Dictionary) -> bool: return hit.get("collider") == inside))
	assert_true(inside in overlapping)

func test_real_physics_overlap_detects_diagonal_capsule_and_excludes_outside_body() -> void:
	var area := _area()
	var start := Vector2(100.0, 100.0)
	var end := Vector2(180.0, 160.0)
	area.sync_edges([{"a": 1, "b": 2}], {1: start, 2: end})
	var inside := _body(start.lerp(end, 0.5), "diagonal-inside")
	var link := end - start
	var outside := _body(start.lerp(end, 0.5) + Vector2(-link.y, link.x).normalized() * 30.0, "diagonal-outside")
	await get_tree().physics_frame
	await get_tree().physics_frame

	var overlapping := area.get_overlapping_bodies()
	assert_true(overlapping.has(inside))
	assert_false(overlapping.has(outside))

func test_invalid_aura_radius_falls_back_without_invalid_shape() -> void:
	for invalid_radius in [0.0, -1.0, NAN, INF]:
		var area := _area(invalid_radius)
		area.sync_edges([{"a": 1, "b": 2}], {1: Vector2.ZERO, 2: Vector2(20.0, 0.0)})
		var capsule := (area._shapes["1:2"] as CollisionShape2D).shape as CapsuleShape2D
		assert_almost_eq(capsule.radius, 18.0, 0.0001)
		assert_true(is_finite(capsule.radius))
		assert_true(is_finite(capsule.height))
		assert_gt(capsule.radius, 0.0)
		assert_gt(capsule.height, 0.0)

func test_non_finite_endpoints_are_rejected_without_creating_a_shape() -> void:
	var area := _area()
	for invalid_endpoint in [Vector2(INF, 0.0), Vector2(0.0, NAN)]:
		area.sync_edges([{"a": 1, "b": 2}], {1: Vector2.ZERO, 2: invalid_endpoint})
		assert_false(area._shapes.has("1:2"))
		assert_eq(area.get_child_count(), 0)
	area.sync_edges([{"a": 1, "b": 2}], {1: Vector2.ZERO, 2: Vector2(20.0, 0.0)})
	var capsule := (area._shapes["1:2"] as CollisionShape2D).shape as CapsuleShape2D
	assert_true(is_finite(capsule.radius))
	assert_true(is_finite(capsule.height))
	assert_gt(capsule.radius, 0.0)
	assert_gt(capsule.height, 0.0)

func test_local_center_and_corner_presets_keep_midpoint_rotation_and_overlap() -> void:
	var presets := {
		&"center": Vector2(0.0, 0.0),
		&"top_left": Vector2(-300.0, -300.0),
		&"top_right": Vector2(300.0, -300.0),
		&"bottom_left": Vector2(-300.0, 300.0),
		&"bottom_right": Vector2(300.0, 300.0),
	}
	var areas: Dictionary = {}
	var inside_bodies: Dictionary = {}
	var outside_bodies: Dictionary = {}
	for preset in presets:
		var start: Vector2 = presets[preset]
		var end := start + Vector2(60.0, 40.0)
		var area := _area()
		area.sync_edges([{"a": 1, "b": 2}], {1: start, 2: end})
		var link := end - start
		var midpoint := start.lerp(end, 0.5)
		areas[preset] = area
		inside_bodies[preset] = _body(midpoint, "%s-inside" % preset)
		outside_bodies[preset] = _body(midpoint + Vector2(-link.y, link.x).normalized() * 30.0, "%s-outside" % preset)
		var collision := area._shapes["1:2"] as CollisionShape2D
		assert_eq(collision.global_position, midpoint, "%s midpoint" % preset)
		assert_almost_eq(collision.global_rotation, link.angle() + PI * 0.5, 0.0001, "%s rotation" % preset)
	await get_tree().physics_frame
	await get_tree().physics_frame
	for preset in presets:
		var overlapping := (areas[preset] as ElectricSubnetArea).get_overlapping_bodies()
		assert_true(overlapping.has(inside_bodies[preset]), "%s inside overlap" % preset)
		assert_false(overlapping.has(outside_bodies[preset]), "%s outside overlap" % preset)

func test_body_entered_and_exited_are_emitted_by_real_physics_movement() -> void:
	var area := _area()
	area.sync_edges([{"a": 1, "b": 2}], {1: Vector2.ZERO, 2: Vector2(100.0, 0.0)})
	var seen: Array[String] = []
	var left: Array[String] = []
	area.target_seen.connect(func(target_id: String, _body: Node2D) -> void: seen.append(target_id))
	area.target_left.connect(func(target_id: String) -> void: left.append(target_id))
	var body := _body(Vector2(50.0, 80.0), "moving-player")
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(seen, [])
	body.global_position = Vector2(50.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(seen, ["moving-player"])
	assert_eq(area.target_ids(), ["moving-player"])
	body.global_position = Vector2(50.0, 80.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(left, ["moving-player"])
	assert_eq(area.target_ids(), [])

func test_removed_edge_frees_shape_and_recreating_key_has_no_stale_or_orphan_shape() -> void:
	var area := _area()
	var edge := [{"a": 1, "b": 2}]
	var positions := {1: Vector2.ZERO, 2: Vector2(100.0, 0.0)}
	area.sync_edges(edge, positions)
	var old_shape := area._shapes["1:2"] as CollisionShape2D
	area.sync_edges([], positions)
	assert_false(area._shapes.has("1:2"))
	assert_true(is_instance_valid(old_shape))
	assert_true(old_shape.is_queued_for_deletion())
	assert_eq(area.get_child_count(), 1)
	await get_tree().physics_frame
	assert_false(is_instance_valid(old_shape))
	assert_eq(area.get_child_count(), 0)
	area.sync_edges(edge, positions)
	var replacement := area._shapes["1:2"] as CollisionShape2D
	assert_not_null(replacement)
	assert_true(is_instance_valid(replacement))
	assert_ne(replacement, old_shape)
	assert_true(replacement.shape is CapsuleShape2D)
	assert_eq(area._shapes.keys(), ["1:2"])
	assert_eq(area.get_child_count(), 1)
