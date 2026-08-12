extends GutTest

const CHAIN := preload("res://scripts/components/procedural_chain_2d.gd")
const BOSS_SCENE := preload("res://scenes/enemies/bosses/regente_dos_ecos.tscn")

class MotionProbe extends RegenteDosEcos:
	var integration_calls := 0
	var integrated_active_delta := -1.0
	var integrated_frame_delta := -1.0
	var motion_calls := 0
	var velocity_seen_by_motion := Vector2.ZERO
	var pivot_deltas: Array[float] = []
	var chain_deltas: Array[float] = []

	func _ready() -> void:
		pass

	func _integrate_physics_motion(active_delta: float, frame_delta: float) -> void:
		integration_calls += 1
		integrated_active_delta = active_delta
		integrated_frame_delta = frame_delta
		super._integrate_physics_motion(active_delta, frame_delta)

	func _integrate_motion() -> void:
		motion_calls += 1
		velocity_seen_by_motion = velocity
		super._integrate_motion()

	func _update_pivots(delta: float) -> void:
		pivot_deltas.append(delta)
		super._update_pivots(delta)

	func _step_chains(delta: float) -> void:
		chain_deltas.append(delta)
		super._step_chains(delta)

func _chain() -> ProceduralChain2D:
	var chain := CHAIN.new() as ProceduralChain2D
	add_child_autofree(chain)
	return chain

func _finite_vector(value: Vector2) -> bool:
	return is_finite(value.x) and is_finite(value.y)

func _finite_chain(chain: ProceduralChain2D) -> bool:
	for position in chain.joint_positions:
		if not _finite_vector(position):
			return false
	return true

func _assert_configured_link_lengths(chain: ProceduralChain2D, anchor: Vector2, tolerance: float = 0.001) -> void:
	var previous := anchor
	for position in chain.joint_positions:
		assert_almost_eq(position.distance_to(previous), chain.link_length, tolerance)
		previous = position

func _assert_mirrored_chain_pair(left: ProceduralChain2D, right: ProceduralChain2D, boss_position: Vector2, tolerance: float = 0.001) -> void:
	assert_eq(right.link_regions, left.link_regions)
	assert_almost_eq(absf(right.visual_scale.x), absf(left.visual_scale.x), tolerance)
	assert_almost_eq(right.visual_scale.y, left.visual_scale.y, tolerance)
	assert_almost_eq(right.visual_scale.x, -left.visual_scale.x, tolerance)
	for index in left.link_count:
		var left_joint := left.joint_positions[index]
		var right_joint := right.joint_positions[index]
		assert_almost_eq(left_joint.x + right_joint.x, 2.0 * boss_position.x, tolerance)
		assert_almost_eq(left_joint.y, right_joint.y, tolerance)
		var left_marker := left.get_child(index) as Sprite2D
		var right_marker := right.get_child(index) as Sprite2D
		if left.visual_elbow_flex <= 0.0:
			assert_eq(left_marker.scale, left.visual_scale)
			assert_eq(right_marker.scale, right.visual_scale)
		assert_almost_eq(left_marker.global_position.x + right_marker.global_position.x, 2.0 * boss_position.x, tolerance)
		assert_almost_eq(left_marker.global_position.y, right_marker.global_position.y, tolerance)
		var mirrored_left_transform_x := Vector2(-left_marker.global_transform.x.x, left_marker.global_transform.x.y)
		var mirrored_left_transform_y := Vector2(-left_marker.global_transform.y.x, left_marker.global_transform.y.y)
		assert_almost_eq(right_marker.global_transform.x.distance_to(mirrored_left_transform_x), 0.0, tolerance)
		assert_almost_eq(right_marker.global_transform.y.distance_to(mirrored_left_transform_y), 0.0, tolerance)
		var left_start: Vector2
		var left_end: Vector2
		var right_start: Vector2
		var right_end: Vector2
		if left.visual_marker_spans.size() == left.link_count and left.visual_marker_roles.size() == left.link_count:
			var span := left.visual_marker_spans[index]
			left_start = left.global_position if int(span.x) == -1 else left.joint_positions[clampi(int(span.x), 0, left.link_count - 1)]
			left_end = left.global_position if int(span.y) == -1 else left.joint_positions[clampi(int(span.y), 0, left.link_count - 1)]
			right_start = right.global_position if int(span.x) == -1 else right.joint_positions[clampi(int(span.x), 0, right.link_count - 1)]
			right_end = right.global_position if int(span.y) == -1 else right.joint_positions[clampi(int(span.y), 0, right.link_count - 1)]
		elif index == 0:
			left_start = left.global_position
			left_end = left.joint_positions[0]
			right_start = right.global_position
			right_end = right.joint_positions[0]
		elif index == left.link_count - 1:
			left_start = left.joint_positions[index - 1]
			left_end = left.joint_positions[index]
			right_start = right.joint_positions[index - 1]
			right_end = right.joint_positions[index]
		else:
			left_start = left.joint_positions[index - 1]
			left_end = left.joint_positions[index]
			right_start = right.joint_positions[index - 1]
			right_end = right.joint_positions[index]
		var left_direction := (left_end - left_start).angle()
		var right_direction := (right_end - right_start).angle()
		if left.visual_elbow_flex <= 0.0:
			if index == left.link_count - 1:
				left_direction += left.visual_terminal_rotation_offset
				right_direction += right.visual_terminal_rotation_offset
			assert_lt(absf(angle_difference(left_marker.rotation, left_direction + left.visual_rotation_offset)), tolerance)
			assert_lt(absf(angle_difference(right_marker.rotation, right_direction + right.visual_rotation_offset)), tolerance)
			assert_lt(absf(angle_difference(right_marker.rotation, PI - left_direction + right.visual_rotation_offset)), tolerance)

func _simulate_chain_at_hz(hz: float) -> ProceduralChain2D:
	var chain := _chain()
	chain.link_count = 4
	chain.link_length = 11.0
	chain.stiffness = 18.0
	chain.damping = 5.0
	chain.reset_chain(Vector2.ZERO, Vector2.DOWN)
	var frame_count := int(hz)
	for frame in frame_count:
		var elapsed := float(frame + 1) / hz
		chain.step(Vector2(22.0 * sin(elapsed * 4.2), 16.0 * cos(elapsed * 4.2)), 1.0 / hz)
	return chain

func _scene_property_names(node_path: NodePath) -> Array[StringName]:
	var names: Array[StringName] = []
	var state := BOSS_SCENE.get_state()
	for node_index in state.get_node_count():
		if state.get_node_path(node_index) == node_path:
			for property_index in state.get_node_property_count(node_index):
				names.append(state.get_node_property_name(node_index, property_index))
	return names

func test_regente_integrates_once_during_full_stun_and_keeps_knockback_in_pipeline() -> void:
	var boss := BOSS_SCENE.instantiate()
	boss.set_script(MotionProbe)
	var probe := boss as MotionProbe
	add_child_autofree(boss)
	probe.set_room_cull_policy(RoomDef.CullPolicy.NONE)
	probe.apply_stun(1.0)
	probe.apply_collision_knockback(Vector2(12.0, 0.0))

	probe._physics_process(0.1)

	assert_eq(probe.integration_calls, 1)
	assert_eq(probe.motion_calls, 1)
	assert_eq(probe.integrated_active_delta, 0.0)
	assert_eq(probe.integrated_frame_delta, 0.1)
	assert_eq(probe.velocity_seen_by_motion, Vector2(12.0, 0.0))
	assert_eq(probe.stun_remaining, 0.9)

func test_regente_visual_followers_use_frame_delta_after_stunned_knockback() -> void:
	var boss := BOSS_SCENE.instantiate()
	boss.set_script(MotionProbe)
	var probe := boss as MotionProbe
	add_child_autofree(boss)
	probe.set_room_cull_policy(RoomDef.CullPolicy.NONE)
	var body_before := probe.global_position
	var mask := probe.get_node("MaskPivot") as Node2D
	var mask_before := mask.global_position
	assert_true(mask.top_level)

	probe.apply_stun(1.0)
	probe.apply_collision_knockback(Vector2(12.0, 0.0))
	probe._physics_process(0.1)

	assert_eq(probe.integration_calls, 1)
	assert_eq(probe.motion_calls, 1)
	assert_eq(probe.integrated_active_delta, 0.0)
	assert_eq(probe.integrated_frame_delta, 0.1)
	assert_gt(probe.global_position.distance_to(body_before), 0.0)
	assert_gt(mask.global_position.distance_to(mask_before), 0.0)
	var mask_target := probe.global_position + probe._facing * probe.mask_axial_offset
	assert_lt(mask.global_position.distance_to(mask_target), mask_before.distance_to(mask_target))
	assert_eq(probe.pivot_deltas, [0.1])
	assert_eq(probe.chain_deltas, [0.1])

func test_chain_exposes_configuration_reset_and_step_contract() -> void:
	var chain := _chain()
	chain.link_count = 3
	chain.link_length = 9.0
	chain.stiffness = 20.0
	chain.damping = 6.0
	chain.residual_inertia = 0.8
	chain.max_turn_per_step = 0.7

	assert_eq(chain.link_count, 3)
	assert_eq(chain.link_length, 9.0)
	assert_eq(chain.joint_positions.size(), 0)
	chain.reset_chain(Vector2(10.0, 20.0), Vector2.RIGHT)
	var result := chain.step(Vector2(10.0, 20.0), 0.016)
	assert_eq(result.size(), 3)
	assert_eq(chain.get_joint_position(0), result[0])

func test_reset_initializes_finite_even_for_degenerate_direction() -> void:
	var chain := _chain()
	chain.link_count = 4
	chain.link_length = 12.0
	chain.reset_chain(Vector2.ZERO, Vector2.ZERO)

	assert_true(_finite_chain(chain))
	assert_eq(chain.joint_positions[0], Vector2(0.0, 12.0))
	for index in chain.link_count:
		assert_almost_eq(chain.joint_positions[index].distance_to(Vector2.ZERO), 12.0 * (index + 1), 0.001)

func test_link_count_one_marker_is_safe_at_anchor_and_oriented_to_joint() -> void:
	var chain := _chain()
	chain.link_count = 1
	chain.link_length = 12.0
	chain.visual_texture = ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))
	chain.reset_chain(Vector2(7.0, -3.0), Vector2.RIGHT)
	var marker := chain.get_child(0) as Sprite2D

	assert_not_null(marker)
	assert_eq(marker.global_position, chain.global_position)
	assert_true(_finite_vector(marker.global_position))
	assert_true(is_finite(marker.rotation))
	assert_almost_eq(marker.rotation, (chain.joint_positions[0] - chain.global_position).angle(), 0.001)

func test_empty_rest_directions_preserve_linear_reset() -> void:
	var chain := _chain()
	chain.link_count = 3
	chain.link_length = 10.0
	chain.rest_directions = PackedVector2Array()
	chain.reset_chain(Vector2(4.0, 5.0), Vector2.RIGHT)

	assert_eq(chain.joint_positions, PackedVector2Array([Vector2(14, 5), Vector2(24, 5), Vector2(34, 5)]))

func test_rest_directions_are_cumulative_and_invalid_entries_stay_finite() -> void:
	var chain := _chain()
	chain.link_count = 4
	chain.link_length = 10.0
	chain.rest_directions = PackedVector2Array([Vector2.RIGHT, Vector2.DOWN, Vector2(NAN, INF), Vector2.LEFT])
	chain.reset_chain(Vector2.ZERO, Vector2.UP)

	assert_eq(chain.joint_positions[0], Vector2(10, 0))
	assert_eq(chain.joint_positions[1], Vector2(10, 10))
	assert_eq(chain.joint_positions[2], Vector2(10, 20))
	assert_eq(chain.joint_positions[3], Vector2(0, 20))
	assert_almost_eq(chain.global_position.distance_to(chain.joint_positions[0]), chain.link_length, 0.001)
	for index in range(1, chain.link_count):
		assert_almost_eq(chain.joint_positions[index - 1].distance_to(chain.joint_positions[index]), chain.link_length, 0.001)
	assert_true(_finite_chain(chain))

func test_step_with_moving_anchor_preserves_lengths_and_non_axial_pose() -> void:
	var chain := _chain()
	chain.link_count = 4
	chain.link_length = 18.0
	chain.rest_directions = PackedVector2Array([Vector2(-0.7, 0.7), Vector2(-0.5, 0.86), Vector2(-0.25, 0.97), Vector2(0, 1)])
	chain.reset_chain(Vector2.ZERO, Vector2.DOWN)
	for frame in 60:
		var anchor := Vector2(40.0 * sin(frame * 0.08), 20.0 * cos(frame * 0.06))
		chain.step(anchor, 1.0 / 60.0)
	_assert_configured_link_lengths(chain, Vector2(40.0 * sin(59 * 0.08), 20.0 * cos(59 * 0.06)), 0.01)
	assert_gt(absf(chain.joint_positions[-1].x - chain.joint_positions[0].x), 0.1)
	assert_true(_finite_chain(chain))

func test_step_keeps_each_link_at_configured_length_after_simulation() -> void:
	var chain := _chain()
	chain.link_count = 5
	chain.link_length = 10.0
	chain.reset_chain(Vector2.ZERO, Vector2.RIGHT)
	for frame in 120:
		chain.step(Vector2(30.0 * sin(frame * 0.04), 15.0 * cos(frame * 0.03)), 1.0 / 60.0)

	_assert_configured_link_lengths(chain, Vector2(30.0 * sin(119 * 0.04), 15.0 * cos(119 * 0.03)), 0.1)

func test_step_uses_fallback_direction_when_anchor_and_link_coincide() -> void:
	var chain := _chain()
	chain.link_count = 4
	chain.link_length = 13.0
	chain.reset_chain(Vector2.ZERO, Vector2.RIGHT)
	for index in chain.link_count:
		chain.joint_positions[index] = Vector2.ZERO

	chain.step(Vector2.ZERO, 1.0 / 60.0)

	assert_eq(chain.joint_positions[0], Vector2.RIGHT * chain.link_length)
	_assert_configured_link_lengths(chain, Vector2.ZERO)

func test_reset_chain_rejects_non_finite_anchor_without_changing_safe_state() -> void:
	var chain := _chain()
	chain.link_count = 3
	chain.link_length = 9.0
	chain.reset_chain(Vector2(4.0, -6.0), Vector2.LEFT)
	var safe_positions := chain.joint_positions.duplicate()

	chain.reset_chain(Vector2(NAN, 2.0), Vector2.RIGHT)
	assert_eq(chain.joint_positions, safe_positions)
	chain.reset_chain(Vector2(2.0, INF), Vector2.RIGHT)
	assert_eq(chain.joint_positions, safe_positions)
	assert_true(_finite_chain(chain))

func test_step_sanitizes_degenerate_and_non_finite_inputs() -> void:
	var chain := _chain()
	chain.link_count = 3
	chain.reset_chain(Vector2.ZERO, Vector2.ZERO)
	chain.joint_positions[1] = Vector2(NAN, INF)

	chain.step(Vector2.ZERO, 0.05)
	chain.step(Vector2(INF, NAN), 0.05)
	assert_true(_finite_chain(chain))
	assert_true(_finite_vector(chain.get_joint_position(-1)))

func test_delta_point_two_is_subdivided_and_response_is_comparable_at_30_60_and_120_hz() -> void:
	var large_delta := _chain()
	var subdivided := _chain()
	for chain in [large_delta, subdivided]:
		chain.link_count = 4
		chain.link_length = 11.0
		chain.stiffness = 18.0
		chain.damping = 5.0
		chain.reset_chain(Vector2.ZERO, Vector2.DOWN)
	large_delta.step(Vector2(20.0, -12.0), 0.2)
	for _substep in 24:
		subdivided.step(Vector2(20.0, -12.0), 1.0 / 120.0)
	_assert_configured_link_lengths(large_delta, Vector2(20.0, -12.0))
	assert_lt(large_delta.joint_positions[0].distance_to(subdivided.joint_positions[0]), 0.2)
	assert_lt(large_delta.joint_positions[3].distance_to(subdivided.joint_positions[3]), 0.5)

	var at_30 := _simulate_chain_at_hz(30.0)
	var at_60 := _simulate_chain_at_hz(60.0)
	var at_120 := _simulate_chain_at_hz(120.0)
	for joint_index in at_30.joint_positions.size():
		assert_lt(at_30.joint_positions[joint_index].distance_to(at_60.joint_positions[joint_index]), 2.5)
		assert_lt(at_60.joint_positions[joint_index].distance_to(at_120.joint_positions[joint_index]), 1.5)

func test_regente_scene_uses_modular_visuals_with_root_pivots() -> void:
	var boss := BOSS_SCENE.instantiate() as RegenteDosEcos
	add_child_autofree(boss)
	await get_tree().process_frame

	assert_true(boss is CharacterBody2D)
	assert_true(boss is Enemy)
	assert_not_null(boss.get_node_or_null("MaskPivot"))
	assert_not_null(boss.get_node_or_null("CrownPivot"))
	assert_null(boss.get_node_or_null("MaskPivot/MaskCrown"))
	assert_null(boss.get_node_or_null("Sprite2D"))
	var core := boss.get_node("CoreReactor") as Sprite2D
	var mask := boss.get_node("CrownPivot/MaskCrown") as Sprite2D
	assert_not_null(core.texture)
	assert_eq(core.texture.resource_path, "res://assets/sprites/enemies/regente-dos-ecos/core-reactor.png")
	assert_eq(mask.texture.resource_path, "res://assets/sprites/enemies/regente-dos-ecos/mask-crown.png")
	assert_eq(mask.position, Vector2(-3, 0))
	assert_eq(mask.rotation, 0.0)
	assert_eq(core.position, Vector2(3.5, 18))
	var corrected_local_centroid_x := core.position.x + (133.176350474688 - 142.5) * core.scale.x
	assert_lt(absf(corrected_local_centroid_x), 0.15)
	assert_eq(boss.mask_axial_offset, -97.0)
	assert_eq(boss.crown_axial_offset, -103.0)
	assert_eq(boss.mask_axial_offset - boss.crown_axial_offset, 6.0)
	var left_arm := boss.get_node("Arms/LeftArmChain") as ProceduralChain2D
	var right_arm := boss.get_node("Arms/RightArmChain") as ProceduralChain2D
	assert_eq(left_arm.position, Vector2(-25, -55))
	assert_eq(right_arm.position, Vector2(25, -55))
	assert_eq(left_arm.link_count, 6)
	assert_eq(right_arm.link_count, 6)
	assert_eq(left_arm.link_length, 13.0)
	assert_eq(right_arm.link_length, 13.0)
	assert_eq(left_arm.visual_scale, Vector2(0.26, 0.26))
	assert_eq(right_arm.visual_scale, Vector2(-0.26, 0.26))
	assert_lt(absf(angle_difference(left_arm.visual_rotation_offset, -PI / 2.0)), 0.001)
	assert_lt(absf(angle_difference(right_arm.visual_rotation_offset, -PI / 2.0)), 0.001)
	assert_eq(left_arm.rest_directions.size(), left_arm.link_count)
	assert_eq(right_arm.rest_directions.size(), right_arm.link_count)
	assert_eq(left_arm.rest_directions[0].x, -right_arm.rest_directions[0].x)
	assert_eq(left_arm.rest_directions[0].y, right_arm.rest_directions[0].y)
	assert_eq(boss.conduit_chains.size(), 3)
	for index in 3:
		var conduit := boss.conduit_chains[index] as ProceduralChain2D
		assert_eq(conduit.link_count, [7, 6, 7][index])
		assert_eq(conduit.position, [Vector2(-20, 40), Vector2(0, 70), Vector2(20, 40)][index])
		assert_eq(conduit.link_length, [19.0, 14.0, 19.0][index])
		assert_eq(conduit.rest_directions.size(), conduit.link_count)
		assert_eq(conduit.visual_scale, [Vector2(0.34, 0.34), Vector2(0.336, 0.336), Vector2(-0.34, 0.34)][index])
	assert_eq((boss.conduit_chains[0] as ProceduralChain2D).rest_directions, PackedVector2Array([Vector2(-0.28, 0.96), Vector2(-0.42, 0.91), Vector2(-0.48, 0.88), Vector2(-0.38, 0.93), Vector2(-0.2, 0.98), Vector2(-0.06, 1.0), Vector2(0.08, 1.0)]))
	assert_eq((boss.conduit_chains[1] as ProceduralChain2D).position, Vector2(0, 70))
	assert_eq((boss.conduit_chains[1] as ProceduralChain2D).link_count, 6)
	assert_eq((boss.conduit_chains[1] as ProceduralChain2D).link_length, 14.0)
	assert_eq((boss.conduit_chains[1] as ProceduralChain2D).visual_scale, Vector2(0.336, 0.336))
	assert_eq((boss.conduit_chains[2] as ProceduralChain2D).rest_directions, PackedVector2Array([Vector2(0.28, 0.96), Vector2(0.42, 0.91), Vector2(0.48, 0.88), Vector2(0.38, 0.93), Vector2(0.2, 0.98), Vector2(0.06, 1.0), Vector2(-0.08, 1.0)]))
	var center := boss.conduit_chains[1] as ProceduralChain2D
	assert_eq(center.visual_marker_offsets, PackedVector2Array([Vector2(-0.5, 0), Vector2(-1, 0), Vector2(-1, 0), Vector2(-1, 0), Vector2(-1, 0), Vector2(1.5, 0)]))
	assert_eq(center.visual_marker_scales[0], Vector2(0.32, 0.336))
	assert_eq(center.visual_marker_scales[center.link_count - 1], Vector2(0.32, 0.336))
	for index in range(1, center.link_count - 1):
		assert_eq(center.visual_marker_scales[index], Vector2(0.336, 0.336))
	assert_true(center.visual_terminal_midpoint)
	assert_lt(absf(angle_difference(center.visual_terminal_rotation_offset, PI)), 0.001)
	assert_eq((boss.conduit_chains[0] as ProceduralChain2D).visual_rotation_offset, 0.0)
	assert_lt(absf(angle_difference((boss.conduit_chains[2] as ProceduralChain2D).visual_rotation_offset, PI)), 0.001)
	assert_eq(core.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_eq(mask.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_eq(boss.max_health, 3.0)
	assert_eq(boss.score_value, 10)
	assert_false(_scene_property_names(NodePath(".")).has(&"max_health"))
	assert_false(_scene_property_names(NodePath(".")).has(&"score_value"))
	assert_eq(boss.collision_layer, 4)
	assert_eq(boss.collision_mask, 0)
	assert_eq(boss.get_node("CollisionShape2D").get_parent(), boss)
	assert_not_null(boss.get_node("CollisionShape2D").shape)
	for chain in boss.arm_chains + boss.conduit_chains:
		var procedural := chain as ProceduralChain2D
		assert_eq(chain.get_child_count(), procedural.link_count)
		assert_true(chain.get_child(0) is Sprite2D)
		assert_null(chain.get_node_or_null("CollisionShape2D"))

func test_chain_link_regions_assign_each_marker_exact_atlas_region() -> void:
	var chain := _chain()
	chain.link_count = 6
	chain.visual_texture = ImageTexture.create_from_image(Image.create(320, 120, false, Image.FORMAT_RGBA8))
	var expected: Array[Rect2] = [Rect2(1, 2, 10, 11), Rect2(12, 13, 14, 15), Rect2(27, 28, 16, 17), Rect2(44, 45, 18, 19), Rect2(63, 64, 20, 21), Rect2(84, 85, 22, 23)]
	chain.link_regions = expected
	chain._ensure_visual_markers()
	await get_tree().process_frame

	for index in 6:
		var marker := chain.get_child(index) as Sprite2D
		assert_eq((marker.texture as AtlasTexture).region, expected[index])
		assert_eq(chain._marker_texture_for(index).region, expected[index])

func test_chain_empty_link_regions_preserve_joint_link_end_fallback() -> void:
	var chain := _chain()
	chain.link_count = 4
	chain.visual_texture = ImageTexture.create_from_image(Image.create(64, 64, false, Image.FORMAT_RGBA8))
	chain.joint_region = Rect2(1, 2, 3, 4)
	chain.link_region = Rect2(5, 6, 7, 8)
	chain.end_region = Rect2(9, 10, 11, 12)
	chain.link_regions = []
	await get_tree().process_frame

	assert_eq(chain._marker_texture_for(0).region, chain.joint_region)
	assert_eq(chain._marker_texture_for(1).region, chain.link_region)
	assert_eq(chain._marker_texture_for(2).region, chain.link_region)
	assert_eq(chain._marker_texture_for(3).region, chain.end_region)

func test_bound_markers_use_anchor_midpoints_joints_and_end_positions() -> void:
	var chain := _chain()
	chain.link_count = 6
	chain.visual_texture = ImageTexture.create_from_image(Image.create(64, 64, false, Image.FORMAT_RGBA8))
	chain.visual_marker_roles = PackedInt32Array([0, 1, 2, 1, 2, 3])
	chain.visual_marker_spans = PackedVector2Array([Vector2(-1, 1), Vector2(-1, 1), Vector2(-1, 1), Vector2(1, 3), Vector2(1, 3), Vector2(3, 4)])
	chain.global_position = Vector2(10, 20)
	chain.reset_chain(Vector2(10, 20), Vector2.RIGHT)
	chain.joint_positions = PackedVector2Array([Vector2(20, 25), Vector2(30, 35), Vector2(35, 40), Vector2(45, 50), Vector2(50, 70), Vector2(70, 80)])
	chain._sync_visual_markers()
	var expected := PackedVector2Array([Vector2(10, 20), Vector2(20, 27.5), Vector2(30, 35), Vector2(37.5, 42.5), Vector2(45, 50), Vector2(50, 70)])
	for index in 6:
		assert_almost_eq((chain.get_child(index) as Sprite2D).global_position.distance_to(expected[index]), 0.0, 0.001)
	var expected_rotations := PackedFloat32Array([Vector2(20, 15).angle(), Vector2(20, 15).angle(), Vector2(20, 15).angle(), Vector2(15, 15).angle(), Vector2(15, 15).angle(), Vector2(5, 20).angle()])
	for index in 6:
		assert_lt(absf(angle_difference((chain.get_child(index) as Sprite2D).rotation, expected_rotations[index] + chain.visual_rotation_offset)), 0.001)

func test_bound_end_rotation_uses_span_direction_and_stays_finite_when_degenerate() -> void:
	var chain := _chain()
	chain.link_count = 6
	chain.visual_texture = ImageTexture.create_from_image(Image.create(64, 64, false, Image.FORMAT_RGBA8))
	chain.visual_rotation_offset = 0.35
	chain.visual_marker_roles = PackedInt32Array([0, 1, 2, 1, 2, 3])
	chain.visual_marker_spans = PackedVector2Array([Vector2(-1, 1), Vector2(-1, 1), Vector2(-1, 1), Vector2(1, 3), Vector2(1, 3), Vector2(3, 4)])
	chain.reset_chain(Vector2.ZERO, Vector2.RIGHT)
	chain.joint_positions = PackedVector2Array([Vector2(1, 0), Vector2(2, 0), Vector2(3, 0), Vector2(4, 0), Vector2(5, 0), Vector2(9, 0)])
	chain._sync_visual_markers()
	var expected_rotations := PackedFloat32Array([Vector2(2, 0).angle(), Vector2(2, 0).angle(), Vector2(2, 0).angle(), Vector2(2, 0).angle(), Vector2(2, 0).angle(), Vector2(1, 0).angle()])
	for index in 6:
		assert_lt(absf(angle_difference((chain.get_child(index) as Sprite2D).rotation, expected_rotations[index] + chain.visual_rotation_offset)), 0.001)
	chain.joint_positions[3] = chain.joint_positions[4]
	chain._sync_visual_markers()
	assert_true(is_finite((chain.get_child(5) as Sprite2D).rotation))
	assert_lt(absf(angle_difference((chain.get_child(5) as Sprite2D).rotation, Vector2.RIGHT.angle() + chain.visual_rotation_offset)), 0.001)

func test_bound_terminal_uses_final_span_midpoint_and_pi_rotation() -> void:
	var chain := _chain()
	chain.link_count = 3
	chain.visual_texture = ImageTexture.create_from_image(Image.create(8, 8, false, Image.FORMAT_RGBA8))
	chain.visual_marker_roles = PackedInt32Array([1, 1, 3])
	chain.visual_marker_spans = PackedVector2Array([Vector2(-1, 0), Vector2(0, 1), Vector2(1, 2)])
	chain.visual_terminal_midpoint = true
	chain.visual_terminal_rotation_offset = PI
	chain.reset_chain(Vector2.ZERO, Vector2.RIGHT)
	chain.joint_positions = PackedVector2Array([Vector2(10, 0), Vector2(20, 0), Vector2(30, 10)])
	chain._sync_visual_markers()
	var terminal := chain.get_child(2) as Sprite2D
	assert_almost_eq(terminal.global_position.distance_to(Vector2(25, 5)), 0.0, 0.001)
	assert_lt(absf(angle_difference(terminal.rotation, Vector2(10, 10).angle() + PI)), 0.001)

func test_incomplete_bindings_preserve_exact_legacy_marker_fallback() -> void:
	var chain := _chain()
	chain.link_count = 4
	chain.link_length = 10.0
	chain.visual_texture = ImageTexture.create_from_image(Image.create(64, 64, false, Image.FORMAT_RGBA8))
	chain.global_position = Vector2(10, 20)
	chain.reset_chain(Vector2(10, 20), Vector2.RIGHT)
	var expected := PackedVector2Array([Vector2(10, 20), Vector2(25, 20), Vector2(35, 20), Vector2(50, 20)])
	for bindings in [PackedInt32Array(), PackedInt32Array([0]), PackedInt32Array([0, 1, 2, 3, 0])]:
		chain.visual_marker_roles = bindings
		chain.visual_marker_spans = PackedVector2Array()
		chain._sync_visual_markers()
		for index in 4:
			assert_almost_eq((chain.get_child(index) as Sprite2D).global_position.distance_to(expected[index]), 0.0, 0.001)

func test_invalid_bound_role_falls_back_only_for_that_marker_and_stays_finite() -> void:
	var chain := _chain()
	chain.link_count = 3
	chain.link_length = 1.0
	chain.visual_texture = ImageTexture.create_from_image(Image.create(64, 64, false, Image.FORMAT_RGBA8))
	chain.visual_marker_roles = PackedInt32Array([0, 99, 3])
	chain.visual_marker_spans = PackedVector2Array([Vector2(-1, 1), Vector2(-1, 1), Vector2(1, 2)])
	chain.reset_chain(Vector2.ZERO, Vector2.RIGHT)
	chain._sync_visual_markers()
	assert_eq((chain.get_child(0) as Sprite2D).global_position, Vector2.ZERO)
	assert_eq((chain.get_child(1) as Sprite2D).global_position, Vector2(1.5, 0))
	assert_eq((chain.get_child(2) as Sprite2D).global_position, Vector2(3, 0))
	for index in 3:
		assert_true(_finite_vector((chain.get_child(index) as Sprite2D).global_position))

func test_bound_span_indices_are_clamped_safely() -> void:
	var chain := _chain()
	chain.link_count = 3
	chain.link_length = 1.0
	chain.visual_texture = ImageTexture.create_from_image(Image.create(64, 64, false, Image.FORMAT_RGBA8))
	chain.visual_marker_roles = PackedInt32Array([0, 1, 3])
	chain.visual_marker_spans = PackedVector2Array([Vector2(-99, 99), Vector2(-99, 99), Vector2(99, 999)])
	chain.reset_chain(Vector2.ZERO, Vector2.RIGHT)
	chain._sync_visual_markers()
	assert_eq((chain.get_child(0) as Sprite2D).global_position, Vector2.ZERO)
	assert_eq((chain.get_child(1) as Sprite2D).global_position, Vector2(1.5, 0))
	assert_eq((chain.get_child(2) as Sprite2D).global_position, Vector2(3, 0))
	assert_true(_finite_chain(chain))

func test_regente_arm_atlas_regions_follow_semantic_ombro_to_mao_order_on_both_sides() -> void:
	var boss := BOSS_SCENE.instantiate() as RegenteDosEcos
	add_child_autofree(boss)
	await get_tree().process_frame
	var expected_left := [Rect2(35, 6, 73, 59), Rect2(34, 65, 47, 113), Rect2(34, 195, 44, 53), Rect2(44, 264, 39, 91), Rect2(59, 372, 33, 39), Rect2(58, 417, 47, 72)]
	for pair in [[boss.arm_chains[0], expected_left], [boss.arm_chains[1], expected_left]]:
		var chain := pair[0] as ProceduralChain2D
		var expected: Array = pair[1]
		assert_eq(chain.link_regions, expected)
		for index in 6:
			assert_eq(((chain.get_child(index) as Sprite2D).texture as AtlasTexture).region, expected[index])

func test_regente_head_offsets_and_mask_crown_position_are_exact() -> void:
	var boss := BOSS_SCENE.instantiate() as RegenteDosEcos
	add_child_autofree(boss)
	var mask := boss.get_node("CrownPivot/MaskCrown") as Sprite2D
	assert_eq(boss.mask_axial_offset, -97.0)
	assert_eq(boss.crown_axial_offset, -103.0)
	assert_eq(boss.mask_axial_offset - boss.crown_axial_offset, 6.0)
	assert_eq(mask.position.x, -3.0)

func test_regente_conduits_keep_v13_configuration_and_mirror_visual_configuration() -> void:
	var boss := BOSS_SCENE.instantiate() as RegenteDosEcos
	add_child_autofree(boss)
	boss.global_position = Vector2(217.25, 143.75)
	await get_tree().process_frame
	boss._reset_chains()
	for index in 3:
		var conduit := boss.conduit_chains[index] as ProceduralChain2D
		assert_eq(conduit.link_count, [7, 6, 7][index])
		assert_eq(conduit.position, [Vector2(-20, 40), Vector2(0, 70), Vector2(20, 40)][index])
		assert_eq(conduit.link_length, [19.0, 14.0, 19.0][index])
		assert_eq(conduit.visual_scale, [Vector2(0.34, 0.34), Vector2(0.336, 0.336), Vector2(-0.34, 0.34)][index])
		assert_eq(conduit.rest_directions.size(), [7, 6, 7][index])
		assert_eq(conduit.visual_marker_roles, PackedInt32Array([1, 1, 1, 1, 1, 1, 1]) if index != 1 else PackedInt32Array([1, 1, 1, 1, 1, 1]))
		assert_eq(conduit.visual_marker_spans, PackedVector2Array([Vector2(-1, 0), Vector2(0, 1), Vector2(1, 2), Vector2(2, 3), Vector2(3, 4), Vector2(4, 5), Vector2(5, 6)]) if index != 1 else PackedVector2Array([Vector2(-1, 0), Vector2(0, 1), Vector2(1, 2), Vector2(2, 3), Vector2(3, 4), Vector2(4, 5)]))
	assert_eq((boss.conduit_chains[2] as ProceduralChain2D).position.x, -(boss.conduit_chains[0] as ProceduralChain2D).position.x)
	var left_conduit := boss.conduit_chains[0] as ProceduralChain2D
	var right_conduit := boss.conduit_chains[2] as ProceduralChain2D
	assert_eq(right_conduit.link_regions, left_conduit.link_regions)
	assert_almost_eq(right_conduit.visual_scale.x, -left_conduit.visual_scale.x, 0.001)
	assert_almost_eq(right_conduit.visual_scale.y, left_conduit.visual_scale.y, 0.001)
	assert_eq(left_conduit.visual_rotation_offset, 0.0)
	assert_lt(absf(angle_difference(right_conduit.visual_rotation_offset, PI)), 0.001)
	_assert_mirrored_chain_pair(left_conduit, right_conduit, boss.global_position)
	var left_arm := boss.arm_chains[0] as ProceduralChain2D
	var right_arm := boss.arm_chains[1] as ProceduralChain2D
	assert_eq(left_arm.visual_scale, Vector2(0.26, 0.26))
	assert_eq(right_arm.visual_scale, Vector2(-0.26, 0.26))
	assert_lt(absf(angle_difference(left_arm.visual_rotation_offset, -PI / 2.0)), 0.001)
	assert_lt(absf(angle_difference(right_arm.visual_rotation_offset, -PI / 2.0)), 0.001)
	_assert_mirrored_chain_pair(left_arm, right_arm, boss.global_position)
	for arm in boss.arm_chains:
		assert_eq((arm as ProceduralChain2D).visual_marker_roles, PackedInt32Array([1, 1, 1, 1, 1, 1]))
		assert_eq((arm as ProceduralChain2D).visual_marker_spans, PackedVector2Array([Vector2(-1, 0), Vector2(0, 1), Vector2(1, 2), Vector2(2, 3), Vector2(3, 4), Vector2(4, 5)]))
		assert_eq((arm as ProceduralChain2D).visual_elbow_flex, 0.2)

func test_regente_initial_pose_opens_arms_and_separates_conduit_endpoints() -> void:
	var boss := BOSS_SCENE.instantiate() as RegenteDosEcos
	add_child_autofree(boss)
	await get_tree().process_frame
	var left := boss.arm_chains[0] as ProceduralChain2D
	var right := boss.arm_chains[1] as ProceduralChain2D
	assert_lt(left.joint_positions[-1].x, left.global_position.x)
	assert_gt(right.joint_positions[-1].x, right.global_position.x)
	assert_gt(left.joint_positions[-1].y, left.global_position.y)
	assert_gt(right.joint_positions[-1].y, right.global_position.y)
	var conduits := boss.conduit_chains
	assert_lt((conduits[0] as ProceduralChain2D).joint_positions[-1].x, (conduits[1] as ProceduralChain2D).joint_positions[-1].x)
	assert_lt((conduits[1] as ProceduralChain2D).joint_positions[-1].x, (conduits[2] as ProceduralChain2D).joint_positions[-1].x)

func test_regente_modular_assets_load_headless() -> void:
	var expected := {
		"core-reactor.png": Vector2i(285, 610),
		"mask-crown.png": Vector2i(335, 295),
		"arm-kit.png": Vector2i(350, 550),
		"conduit-kit.png": Vector2i(565, 840),
	}
	for file_name in expected:
		var path := "res://assets/sprites/enemies/regente-dos-ecos/%s" % file_name
		var texture := load(path) as Texture2D
		assert_not_null(texture)
		assert_true(FileAccess.file_exists(path))
		assert_eq(Vector2i(texture.get_width(), texture.get_height()), expected[file_name])
		assert_eq(texture.get_image().get_format(), Image.FORMAT_RGBA8)

func test_regente_updates_pivots_and_all_chain_visual_markers() -> void:
	var boss := BOSS_SCENE.instantiate() as RegenteDosEcos
	add_child_autofree(boss)
	boss.global_position = Vector2(200.0, 180.0)
	await get_tree().process_frame
	var old_mask := boss.mask_pivot.global_position
	var old_crown := boss.crown_pivot.global_position
	boss._physics_process(0.05)

	assert_ne(boss.mask_pivot.global_position, old_mask)
	assert_ne(boss.crown_pivot.global_position, old_crown)
	for chain in boss.arm_chains + boss.conduit_chains:
		var procedural := chain as ProceduralChain2D
		assert_not_null(procedural)
		assert_true(_finite_chain(procedural))
		assert_eq(chain.get_child_count(), procedural.link_count)
		# Esta verificação cobre o binding base; o flex pós-simulação tem teste dedicado.
		procedural.visual_elbow_flex = 0.0
		procedural._sync_visual_markers()
		var uses_bindings := procedural.visual_marker_roles.size() == procedural.link_count and procedural.visual_marker_spans.size() == procedural.link_count
		for index in procedural.link_count:
			var marker := chain.get_child(index) as Sprite2D
			assert_not_null(marker)
			var expected_position: Vector2
			var expected_rotation: float
			if uses_bindings:
				var span := procedural.visual_marker_spans[index]
				var start := procedural.global_position if int(span.x) == -1 else procedural.joint_positions[clampi(int(span.x), 0, procedural.link_count - 1)]
				var end := procedural.global_position if int(span.y) == -1 else procedural.joint_positions[clampi(int(span.y), 0, procedural.link_count - 1)]
				var role := procedural.visual_marker_roles[index]
				expected_position = start if role == 0 else ((start + end) * 0.5 if role == 1 else end)
				expected_rotation = (end - start).angle() + procedural.visual_rotation_offset
			elif index == 0:
				expected_position = chain.global_position
			elif index == procedural.link_count - 1:
				expected_position = procedural.joint_positions[index]
			else:
				expected_position = (procedural.joint_positions[index - 1] + procedural.joint_positions[index]) * 0.5
			expected_position += chain.to_global(procedural._marker_visual_offset(index)) - chain.global_position
			assert_almost_eq(marker.global_position.distance_to(expected_position), 0.0, 0.001)
			if uses_bindings:
				if index == procedural.link_count - 1:
					expected_rotation += procedural.visual_terminal_rotation_offset
				assert_lt(absf(angle_difference(marker.rotation, expected_rotation)), 0.001)
		assert_eq(chain.get_node_or_null("CollisionShape2D"), null)
		assert_eq(chain.get_node_or_null("RigidBody2D"), null)

func test_elbow_flex_rotates_basis_and_origins_without_losing_negative_scale() -> void:
	var chain := _chain()
	chain.link_count = 6
	chain.visual_texture = ImageTexture.create_from_image(Image.create(64, 64, false, Image.FORMAT_RGBA8))
	chain.visual_scale = Vector2(-0.5, 0.5)
	chain.visual_marker_roles = PackedInt32Array([1, 1, 1, 1, 1, 1])
	chain.visual_marker_spans = PackedVector2Array([Vector2(-1, 0), Vector2(0, 1), Vector2(1, 2), Vector2(2, 3), Vector2(3, 4), Vector2(4, 5)])
	chain.global_position = Vector2(10, 20)
	chain.reset_chain(chain.global_position, Vector2.RIGHT)
	chain.joint_positions = PackedVector2Array([Vector2(20, 20), Vector2(30, 20), Vector2(40, 20), Vector2(40, 30), Vector2(40, 40), Vector2(40, 50)])
	chain._sync_visual_markers()
	var base_elbow := (chain.get_child(2) as Sprite2D).transform
	var base_distal := (chain.get_child(3) as Sprite2D).transform
	var base_distal_origins := PackedVector2Array()
	for index in range(3, 6):
		base_distal_origins.append((chain.get_child(index) as Sprite2D).global_position)
	chain.visual_elbow_flex = 0.2
	chain._sync_visual_markers()
	var elbow := chain.get_child(2) as Sprite2D
	var distal := chain.get_child(3) as Sprite2D
	var extra := angle_difference(Vector2.RIGHT.angle(), Vector2.DOWN.angle()) * 0.2
	assert_almost_eq(elbow.transform.x.distance_to(base_elbow.x.rotated(extra * 0.5)), 0.0, 0.001)
	assert_almost_eq(distal.transform.x.distance_to(base_distal.x.rotated(extra)), 0.0, 0.001)
	assert_lt(elbow.transform.determinant(), 0.0)
	assert_lt(distal.transform.determinant(), 0.0)
	for index in range(3, 6):
		var marker := chain.get_child(index) as Sprite2D
		assert_gt(marker.global_position.distance_to(base_distal_origins[index - 3]), 0.001)
		assert_lt(marker.transform.determinant(), 0.0)

func test_regente_pivots_have_global_translation_lag_as_well_as_rotation_lag() -> void:
	var boss := BOSS_SCENE.instantiate() as RegenteDosEcos
	add_child_autofree(boss)
	await get_tree().process_frame
	var old_mask_position := boss.mask_pivot.global_position
	var old_crown_position := boss.crown_pivot.global_position
	var old_mask_rotation := boss.mask_pivot.global_rotation
	var old_crown_rotation := boss.crown_pivot.global_rotation
	boss.global_position += Vector2(80.0, -40.0)
	boss._facing = Vector2.RIGHT
	boss._update_pivots(0.05)

	var mask_target := boss.global_position + Vector2.RIGHT * boss.mask_axial_offset
	var crown_target := boss.global_position + Vector2.RIGHT * boss.crown_axial_offset
	assert_ne(boss.mask_pivot.global_position, old_mask_position)
	assert_ne(boss.crown_pivot.global_position, old_crown_position)
	assert_gt(boss.mask_pivot.global_position.distance_to(mask_target), 0.01)
	assert_gt(boss.crown_pivot.global_position.distance_to(crown_target), 0.01)
	assert_ne(boss.mask_pivot.global_rotation, old_mask_rotation)
	assert_ne(boss.crown_pivot.global_rotation, old_crown_rotation)
	assert_gt(absf(boss.mask_pivot.global_rotation - Vector2.RIGHT.angle()), 0.01)
	assert_gt(absf(boss.crown_pivot.global_rotation - Vector2.RIGHT.angle()), 0.01)

func test_regente_initializes_pivots_for_each_facing_direction() -> void:
	var boss := BOSS_SCENE.instantiate() as RegenteDosEcos
	add_child_autofree(boss)
	boss.global_position = Vector2(200.0, 180.0)
	await get_tree().process_frame

	for facing in [Vector2.DOWN, Vector2.RIGHT, Vector2.UP, Vector2.LEFT]:
		boss._facing = facing
		boss._initialize_pivots()
		var expected_rotation: float = facing.angle() - PI / 2.0
		assert_lt(boss.mask_pivot.global_position.distance_to(boss.global_position + facing * boss.mask_axial_offset), 0.001)
		assert_lt(boss.crown_pivot.global_position.distance_to(boss.global_position + facing * boss.crown_axial_offset), 0.001)
		assert_lt(absf(angle_difference(boss.mask_pivot.global_rotation, expected_rotation)), 0.001)
		assert_lt(absf(angle_difference(boss.crown_pivot.global_rotation, expected_rotation)), 0.001)

func test_regente_resets_chain_directions_from_radial_and_facing_vectors() -> void:
	var boss := BOSS_SCENE.instantiate() as RegenteDosEcos
	add_child_autofree(boss)
	await get_tree().process_frame
	boss._facing = Vector2.DOWN
	boss._reset_chains()

	var left := boss.get_node("Arms/LeftArmChain") as ProceduralChain2D
	var right := boss.get_node("Arms/RightArmChain") as ProceduralChain2D
	var conduit := boss.get_node("Conduits/LeftConduitChain") as ProceduralChain2D
	assert_lt((left.joint_positions[0] - left.global_position).normalized().distance_to(Vector2(-0.85, 0.53).normalized()), 0.001)
	assert_lt((right.joint_positions[0] - right.global_position).normalized().distance_to(Vector2(0.85, 0.53).normalized()), 0.001)
	assert_lt((conduit.joint_positions[0] - conduit.global_position).normalized().distance_to(Vector2(-0.28, 0.96).normalized()), 0.001)

func _culling_boss(bounds: Rect2, policy: RoomDef.CullPolicy) -> RegenteDosEcos:
	var boss := BOSS_SCENE.instantiate() as RegenteDosEcos
	add_child_autofree(boss)
	boss.set_room_bounds(bounds)
	boss.set_room_cull_policy(policy)
	boss._has_entered_room = true
	return boss

func test_regente_visual_cull_margins_preserve_base_margin_inside_bounds() -> void:
	var boss := _culling_boss(Rect2(0.0, 0.0, 320.0, 320.0), RoomDef.CullPolicy.DESPAWN_BOTTOM)

	assert_eq(boss.visual_cull_margin_x, 80.0)
	assert_eq(boss.visual_cull_margin_y, 190.0)
	var effective_margin_y := 40.0 + boss.visual_cull_margin_y
	boss.global_position = Vector2(160.0, 320.0 + effective_margin_y - 0.1)
	assert_false(boss._should_cull())

func test_regente_despawn_bottom_culls_after_vertical_visual_margin() -> void:
	var boss := _culling_boss(Rect2(0.0, 0.0, 320.0, 320.0), RoomDef.CullPolicy.DESPAWN_BOTTOM)

	boss.global_position = Vector2(160.0, 320.0 + 40.0 + boss.visual_cull_margin_y + 0.1)
	assert_true(boss._should_cull())

func test_regente_all_borders_preserves_vertical_sprite_footprint_at_top() -> void:
	var boss := _culling_boss(Rect2(0.0, 0.0, 320.0, 320.0), RoomDef.CullPolicy.DESPAWN_ALL_BORDERS)

	var effective_margin_y := 40.0 + boss.visual_cull_margin_y
	boss.global_position = Vector2(160.0, -effective_margin_y + 0.1)
	assert_false(boss._should_cull())
	boss.global_position = Vector2(160.0, -effective_margin_y - 0.1)
	assert_true(boss._should_cull())

func test_regente_all_borders_uses_lateral_visual_margin() -> void:
	var boss := _culling_boss(Rect2(0.0, 0.0, 320.0, 320.0), RoomDef.CullPolicy.DESPAWN_ALL_BORDERS)

	var effective_margin_x := 40.0 + boss.visual_cull_margin_x
	boss.global_position = Vector2(-effective_margin_x + 0.1, 160.0)
	assert_false(boss._should_cull())
	boss.global_position = Vector2(-effective_margin_x - 0.1, 160.0)
	assert_true(boss._should_cull())

func test_regente_none_never_culls() -> void:
	var boss := _culling_boss(Rect2(0.0, 0.0, 320.0, 320.0), RoomDef.CullPolicy.NONE)

	boss.global_position = Vector2(-10000.0, 10000.0)
	assert_false(boss._should_cull())
