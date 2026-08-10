extends GutTest

const CHAIN := preload("res://scripts/components/procedural_chain_2d.gd")
const BOSS_SCENE := preload("res://scenes/enemies/bosses/regente_dos_ecos.tscn")

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

func test_regente_scene_preserves_root_pivots_and_texture_free_chain_structure() -> void:
	var boss := BOSS_SCENE.instantiate() as RegenteDosEcos
	add_child_autofree(boss)
	await get_tree().process_frame

	assert_true(boss is CharacterBody2D)
	assert_true(boss is Enemy)
	assert_not_null(boss.get_node_or_null("MaskPivot"))
	assert_not_null(boss.get_node_or_null("CrownPivot"))
	assert_null(boss.get_node("Sprite2D").texture)
	assert_eq(boss.max_health, 3.0)
	assert_eq(boss.score_value, 10)
	assert_false(_scene_property_names(NodePath(".")).has(&"max_health"))
	assert_false(_scene_property_names(NodePath(".")).has(&"score_value"))
	assert_eq(boss.get_node("CollisionShape2D").get_parent(), boss)
	assert_eq(boss.get_node("Arms/LeftArmChain").get_child_count(), 0)
	assert_eq(boss.get_node("Conduits/RightConduitChain").get_child_count(), 0)
	for chain in boss.arm_chains + boss.conduit_chains:
		assert_eq(chain.get_child_count(), 0)
		assert_null(chain.get_node_or_null("Sprite2D"))
		assert_null(chain.get_node_or_null("CollisionShape2D"))

func test_regente_updates_pivots_and_all_chains_without_physics_links() -> void:
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
		assert_true(chain is ProceduralChain2D)
		assert_true(_finite_chain(chain))
		assert_eq(chain.get_child_count(), 0)
		assert_eq(chain.get_node_or_null("CollisionShape2D"), null)
		assert_eq(chain.get_node_or_null("RigidBody2D"), null)

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
