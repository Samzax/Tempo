extends GutTest

class DamageTarget extends Node2D:
	var calls: Array[DamageInfo] = []

	func take_damage(info: DamageInfo) -> void:
		calls.append(info)

var _root: Node2D
var _manager: EngineTrailManager
var _source: Node
var _target: DamageTarget
var _player: Player
var _character: CharacterDef

func before_each() -> void:
	_root = Node2D.new()
	add_child(_root)
	_source = Node.new()
	_root.add_child(_source)
	_manager = EngineTrailManager.new()
	_root.add_child(_manager)
	_manager.configure(_source, 1.0, 16.0, 0.8, 0.5, 32.0, Color(0.2, 0.7, 1.0))
	_target = DamageTarget.new()
	_target.add_to_group(&"enemies")
	_target.position = Vector2(16.0, 0.0)
	_root.add_child(_target)

func after_each() -> void:
	if is_instance_valid(_root):
		_root.free()

func _emit_one_segment() -> void:
	_manager.emit_from_anchors(Vector2(-4.0, 0.0), Vector2(4.0, 0.0))
	_manager.emit_from_anchors(Vector2(36.0, 0.0), Vector2(44.0, 0.0))

func test_manager_is_persistent_single_node_and_emits_only_after_spacing() -> void:
	assert_eq(_root.get_child_count(), 3)
	_manager.emit_from_anchors(Vector2(-4.0, 0.0), Vector2(4.0, 0.0))
	_manager.emit_from_anchors(Vector2(12.0, 0.0), Vector2(20.0, 0.0))
	assert_eq(_manager.active_segment_count(), 0)
	_manager.emit_from_anchors(Vector2(28.0, 0.0), Vector2(36.0, 0.0))
	assert_eq(_manager.active_segment_count(), 2)

func test_large_displacement_emits_seven_pixel_logical_segments_and_carries_remainder() -> void:
	_manager._spacing = 7.0
	_manager.emit_from_anchors(Vector2(-4.0, 0.0), Vector2(4.0, 0.0))
	_manager.emit_from_anchors(Vector2(36.0, 0.0), Vector2(44.0, 0.0))
	assert_eq(_manager.active_segment_count(), 10)
	for segment in _manager.segments:
		assert_almost_eq((segment["end"] as Vector2).distance_to(segment["origin"] as Vector2), 7.0, 0.0001)

	_manager.emit_from_anchors(Vector2(48.0, 0.0), Vector2(56.0, 0.0))
	assert_eq(_manager.active_segment_count(), 14)
	assert_eq(_manager.segments[10]["origin"], Vector2(31.0, 0.0))
	assert_eq(_manager.segments[11]["origin"], Vector2(39.0, 0.0))
	assert_eq(_manager.segments[12]["origin"], Vector2(38.0, 0.0))
	assert_eq(_manager.segments[13]["origin"], Vector2(46.0, 0.0))
	assert_eq(_manager.segments[10]["end"], Vector2(38.0, 0.0))
	assert_eq(_manager.segments[11]["end"], Vector2(46.0, 0.0))
	assert_eq(_manager.segments[12]["end"], Vector2(45.0, 0.0))
	assert_eq(_manager.segments[13]["end"], Vector2(53.0, 0.0))
	for segment in _manager.segments:
		assert_almost_eq((segment["end"] as Vector2).distance_to(segment["origin"] as Vector2), 7.0, 0.0001)

func test_first_ignition_call_only_initializes_anchors_and_first_real_pair_is_ignition() -> void:
	_manager.configure(_source, 1.0, 16.0, 0.8, 0.5, 7.0, Color(0.2, 0.7, 1.0))
	_manager.emit_from_anchors(Vector2(-4.0, 0.0), Vector2(4.0, 0.0), &"IGNITION")
	assert_eq(_manager.active_segment_count(), 0)
	assert_true(_manager._has_last_anchors)

	_manager.emit_from_anchors(Vector2(4.0, 0.0), Vector2(12.0, 0.0), &"CRUISE")
	assert_eq(_manager.active_segment_count(), 2)
	assert_eq(_manager.segments[0]["state"], &"IGNITION")
	assert_eq(_manager.segments[1]["state"], &"IGNITION")

func test_stop_emission_keeps_existing_segments_fading_and_clear_removes_them() -> void:
	_emit_one_segment()
	assert_eq(_manager.active_segment_count(), 2)
	_manager.stop_emission()
	_manager.emit_from_anchors(Vector2(80.0, 0.0), Vector2(80.0, 0.0))
	assert_eq(_manager.active_segment_count(), 2)
	_manager._physics_process(0.81)
	assert_eq(_manager.active_segment_count(), 0)

func test_damage_is_once_per_target_until_cooldown_even_with_multiple_segments() -> void:
	_emit_one_segment()
	_manager._physics_process(0.01)
	assert_eq(_target.calls.size(), 1)
	assert_eq(_target.calls[0].amount, 100)
	assert_true(_target.calls[0].tags.has(&"engine_trail"))
	assert_eq(_target.calls[0].source, _source)
	_manager.emit_from_anchors(Vector2(80.0, 0.0), Vector2(80.0, 0.0))
	_manager._physics_process(0.1)
	assert_eq(_manager.active_segment_count(), 4)
	assert_eq(_target.calls.size(), 1)
	_manager._physics_process(0.4)
	assert_eq(_target.calls.size(), 2)

func test_dead_targets_are_pruned_and_segment_color_is_inherited() -> void:
	_emit_one_segment()
	_manager._physics_process(0.01)
	assert_eq(_manager._color, Color(0.2, 0.7, 1.0))
	assert_true(_manager.target_next_damage.has(_target.get_instance_id()))
	_target.free()
	_manager._physics_process(0.01)
	assert_eq(_manager.target_next_damage.size(), 0)

func test_clear_segments_resets_anchor_state_without_allocating_nodes() -> void:
	_emit_one_segment()
	_manager.clear_segments()
	assert_eq(_manager.active_segment_count(), 0)
	assert_eq(_manager.target_next_damage.size(), 0)
	_manager.emit_from_anchors(Vector2.ZERO, Vector2.ZERO)
	assert_eq(_manager.active_segment_count(), 0)

func test_trail_caps_each_strand_independently_at_twenty_two_samples() -> void:
	_manager.configure(_source, 1.0, 16.0, 0.7, 0.5, 7.0, Color(0.2, 0.7, 1.0))
	_manager.emit_from_anchors(Vector2(-4.0, 0.0), Vector2(4.0, 0.0))
	_manager.emit_from_anchors(Vector2(-4.0, 0.0), Vector2(400.0, 0.0))
	var oldest_right_origin: Vector2 = _manager.segments[0]["origin"]
	var left_count := 0
	var right_count := 0
	for segment in _manager.segments:
		if segment["strand"] == &"left":
			left_count += 1
		else:
			right_count += 1
	assert_eq(left_count, 0)
	assert_eq(right_count, EngineTrailManager.MAX_SAMPLES_PER_STRAND)
	assert_eq(_manager.active_segment_count(), EngineTrailManager.MAX_SAMPLES_PER_STRAND)

	_manager.emit_from_anchors(Vector2(-4.0, 0.0), Vector2(600.0, 0.0))
	left_count = 0
	right_count = 0
	for segment in _manager.segments:
		if segment["strand"] == &"left":
			left_count += 1
		else:
			right_count += 1
	assert_eq(left_count, 0)
	assert_eq(right_count, EngineTrailManager.MAX_SAMPLES_PER_STRAND)
	assert_eq(_manager.active_segment_count(), EngineTrailManager.MAX_SAMPLES_PER_STRAND)
	assert_ne(_manager.segments[0]["origin"], oldest_right_origin)

func test_movement_states_preserve_trail_geometry_count_and_damage() -> void:
	var expected_geometry: Array[Dictionary] = []
	var cruise_response := _manager._state_response(&"CRUISE")
	_manager.configure(_source, 1.0, 16.0, 0.7, 0.5, 7.0, Color(0.2, 0.7, 1.0))
	for state in [&"CRUISE", &"IGNITION", &"TURN", &"BRAKE"]:
		_manager.clear_segments()
		_target.calls.clear()
		_manager.emit_from_anchors(Vector2(-4.0, 0.0), Vector2(4.0, 0.0), state)
		_manager.emit_from_anchors(Vector2(3.0, 0.0), Vector2(11.0, 0.0), state)
		assert_eq(_manager.active_segment_count(), 2)
		assert_eq(_manager.segments[0]["state"], state)
		assert_eq(_manager.segments[1]["state"], state)
		if state != &"CRUISE":
			assert_ne(_manager._state_response(state), cruise_response)
		var geometry: Array[Dictionary] = [
			{"origin": _manager.segments[0]["origin"], "end": _manager.segments[0]["end"]},
			{"origin": _manager.segments[1]["origin"], "end": _manager.segments[1]["end"]},
		]
		if expected_geometry.is_empty():
			expected_geometry = geometry
		else:
			assert_eq(geometry, expected_geometry)
		_manager._physics_process(0.01)
		assert_eq(_target.calls.size(), 1)
		assert_eq(_target.calls[0].amount, 100)

func test_curved_trail_keeps_continuous_distinct_samples_on_both_strands() -> void:
	_manager.configure(_source, 1.0, 16.0, 0.7, 0.5, 7.0, Color(0.2, 0.7, 1.0))
	_manager.emit_from_anchors(Vector2(-4.0, 0.0), Vector2(4.0, 0.0))
	_manager.emit_from_anchors(Vector2(2.0, 8.0), Vector2(10.0, 8.0))
	_manager.emit_from_anchors(Vector2(8.0, 16.0), Vector2(16.0, 16.0))
	_manager.emit_from_anchors(Vector2(16.0, 22.0), Vector2(24.0, 22.0))
	assert_gte(_manager.active_segment_count(), 6)
	for segment_index in range(2, _manager.segments.size(), 2):
		assert_eq(_manager.segments[segment_index - 2]["end"], _manager.segments[segment_index]["origin"])
		assert_eq(_manager.segments[segment_index - 1]["end"], _manager.segments[segment_index + 1]["origin"])
		assert_ne(_manager.segments[segment_index]["end"], _manager.segments[segment_index + 1]["end"])
	var first_direction: Vector2 = _manager.segments[0]["end"] - _manager.segments[0]["origin"]
	var last_left_index := _manager.segments.size() - 2
	var last_direction: Vector2 = _manager.segments[last_left_index]["end"] - _manager.segments[last_left_index]["origin"]
	assert_ne(first_direction.normalized(), last_direction.normalized())

func test_rotating_anchors_keep_independent_spacing_and_remainders_per_strand() -> void:
	_manager.configure(_source, 1.0, 16.0, 0.7, 0.5, 7.0, Color(0.2, 0.7, 1.0))
	_manager.emit_from_anchors(Vector2(-4.0, 0.0), Vector2(4.0, 0.0))
	_manager.emit_from_anchors(Vector2(10.0, 0.0), Vector2(4.0, 20.0))
	_manager.emit_from_anchors(Vector2(24.0, 9.0), Vector2(15.0, 29.0))

	assert_eq(_manager.active_segment_count(), 8)
	var left_segments: Array[Dictionary] = []
	var right_segments: Array[Dictionary] = []
	for segment in _manager.segments:
		if segment["strand"] == &"left":
			left_segments.append(segment)
		else:
			right_segments.append(segment)
	assert_eq(left_segments.size(), 4)
	assert_eq(right_segments.size(), 4)
	assert_eq(left_segments[0]["origin"], Vector2(-4.0, 0.0))
	assert_eq(left_segments[1]["origin"], Vector2(3.0, 0.0))
	assert_eq(right_segments[0]["origin"], Vector2(4.0, 0.0))
	assert_eq(right_segments[1]["origin"], Vector2(4.0, 7.0))
	assert_ne(left_segments[2]["origin"], Vector2(24.0, 9.0))
	assert_ne(right_segments[2]["origin"], Vector2(15.0, 29.0))
	assert_ne(left_segments[2]["origin"], right_segments[2]["origin"])
	assert_eq(left_segments[1]["end"], left_segments[2]["origin"])
	assert_eq(right_segments[1]["end"], right_segments[2]["origin"])
	for segment in _manager.segments:
		assert_almost_eq((segment["end"] as Vector2).distance_to(segment["origin"] as Vector2), 7.0, 0.0001)

	assert_eq(_manager.segments[2]["origin"], Vector2(3.0, 0.0))
	assert_eq(_manager.segments[3]["origin"], Vector2(4.0, 7.0))
	assert_eq(_manager.segments[4]["origin"], Vector2(10.0, 0.0))
	assert_eq(_manager.segments[5]["origin"], Vector2(4.0, 14.0))
	for strand in [&"left", &"right"]:
		var previous_end := Vector2.INF
		for segment in _manager.segments:
			if segment["strand"] == strand:
				if previous_end != Vector2.INF:
					assert_eq(segment["origin"], previous_end)
				previous_end = segment["end"]
	# O primeiro segmento do segundo par começa no cursor de cada trilha,
	# e não no último anchor recebido nem no cursor da outra trilha.

func test_damage_radius_remains_logical_when_visual_layers_are_drawn() -> void:
	_manager.configure(_source, 1.0, 16.0, 0.7, 0.5, 7.0, Color(0.2, 0.7, 1.0))
	_manager.emit_from_anchors(Vector2(-4.0, 0.0), Vector2(4.0, 0.0))
	_manager.emit_from_anchors(Vector2(3.0, 0.0), Vector2(11.0, 0.0))
	_target.position = Vector2(3.0, 8.01)
	_manager._physics_process(0.01)
	assert_eq(_target.calls.size(), 0)
	_target.position = Vector2(3.0, 8.0)
	_manager._physics_process(0.01)
	assert_eq(_target.calls.size(), 1)

func test_movement_state_visual_endpoints_do_not_mutate_logical_damage_segments() -> void:
	_manager.configure(_source, 1.0, 8.0, 0.7, 0.5, 7.0, Color(0.2, 0.7, 1.0))
	for state in [&"CRUISE", &"TURN", &"IGNITION", &"BRAKE"]:
		_manager.clear_segments()
		_target.calls.clear()
		_manager.emit_from_anchors(Vector2(-4.0, 0.0), Vector2(4.0, 0.0), state)
		_manager.emit_from_anchors(Vector2(3.0, 0.0), Vector2(11.0, 0.0), state)
		var logical_origin: Vector2 = _manager.segments[0]["origin"]
		var logical_end: Vector2 = _manager.segments[0]["end"]
		var logical_snapshot := _manager.segments.duplicate(true)
		var visual := _manager._visual_endpoints(logical_origin, logical_end, state)
		if state == &"CRUISE" or state == &"TURN":
			assert_eq(visual["origin"], logical_origin)
			assert_eq(visual["end"], logical_end)
		else:
			assert_eq(visual["end"], logical_end)
			assert_lt(visual["origin"].distance_to(logical_end), logical_origin.distance_to(logical_end))
		assert_eq(_manager.segments, logical_snapshot)
		_target.position = Vector2(-3.0, 0.0)
		_manager._physics_process(0.01)
		assert_eq(_target.calls.size(), 1)

func _make_interestelar_player() -> Player:
	var effects := Node2D.new()
	effects.add_to_group("effects")
	_root.add_child(effects)
	var projectiles := Node2D.new()
	projectiles.add_to_group("projectiles")
	_root.add_child(projectiles)
	_character = CharacterDef.new()
	_character.id = &"test_pilot"
	_character.thrust_color = Color(0.2, 0.7, 1.0)
	_player = load("res://scenes/player/player.tscn").instantiate()
	_player.ship = load("res://resources/ships/interestelar.tres")
	_player.character = _character
	_root.add_child(_player)
	await get_tree().process_frame
	return _player

func test_interestelar_is_quiet_without_input_even_when_velocity_is_nonzero() -> void:
	var interestelar := load("res://resources/ships/interestelar.tres") as ShipDef
	_player = await _make_interestelar_player()
	assert_true(_player.configure_ship(interestelar))
	assert_not_null(_player._engine_trail_manager)
	_player.velocity = Vector2(interestelar.base_stats[0].value, 0.0)
	_player._update_engine_trail(false)
	assert_eq(_player._engine_trail_manager.active_segment_count(), 0)
	assert_false(_player._engine_trail_manager._has_last_anchors)

func test_interestelar_trail_uses_character_color_and_distinct_global_anchors() -> void:
	var interestelar := load("res://resources/ships/interestelar.tres") as ShipDef
	_player = await _make_interestelar_player()
	assert_true(_player.configure_ship(interestelar))
	var manager: EngineTrailManager = _player._engine_trail_manager
	assert_eq(manager._color, _character.thrust_color)
	_player.visual_root.rotation = PI / 2.0
	_player.velocity = Vector2(0.0, -220.0)
	_player._update_engine_trail(true)
	_player.position += Vector2(40.0, 0.0)
	_player._update_engine_trail(true)
	assert_eq(manager.active_segment_count(), 10)
	assert_eq(manager.segments[0]["strand"], &"left")
	assert_eq(manager.segments[1]["strand"], &"right")
	var first_origin: Vector2 = manager.segments[0]["origin"]
	var second_origin: Vector2 = manager.segments[1]["origin"]
	assert_almost_eq(first_origin.x, -8.0, 0.0001)
	assert_almost_eq(first_origin.y, -4.0, 0.0001)
	assert_almost_eq(second_origin.x, -8.0, 0.0001)
	assert_almost_eq(second_origin.y, 4.0, 0.0001)
	assert_ne(first_origin, second_origin)
	assert_almost_eq(first_origin.distance_to(second_origin), 8.0, 0.0001)

func test_interestelar_trail_fades_after_input_is_released() -> void:
	var interestelar := load("res://resources/ships/interestelar.tres") as ShipDef
	_player = await _make_interestelar_player()
	assert_true(_player.configure_ship(interestelar))
	var manager: EngineTrailManager = _player._engine_trail_manager
	_player.velocity = Vector2(0.0, -220.0)
	_player._update_engine_trail(true)
	_player.position += Vector2(40.0, 0.0)
	_player._update_engine_trail(true)
	assert_eq(manager.active_segment_count(), 10)
	_player._update_engine_trail(false)
	assert_false(manager._has_last_anchors)
	manager._physics_process(0.81)
	assert_eq(manager.active_segment_count(), 0)

func test_interestelar_custom_atlas_assigns_all_five_animations_and_ten_frames() -> void:
	var interestelar := load("res://resources/ships/interestelar.tres") as ShipDef
	_player = await _make_interestelar_player()
	assert_true(_player.configure_ship(interestelar))
	var expected_regions: Array[Rect2] = interestelar.custom_frame_regions
	var animation_order := [&"hard_left", &"soft_left", &"neutral", &"soft_right", &"hard_right"]
	assert_eq(_player.sprite.sprite_frames.get_animation_names().size(), 5)
	for animation_index in animation_order.size():
		var animation_name: StringName = animation_order[animation_index]
		assert_true(_player.sprite.sprite_frames.has_animation(animation_name))
		assert_eq(_player.sprite.sprite_frames.get_frame_count(animation_name), 2)
		for frame_index in 2:
			var texture := _player.sprite.sprite_frames.get_frame_texture(animation_name, frame_index)
			assert_true(texture is AtlasTexture)
			var frame := texture as AtlasTexture
			assert_not_null(frame)
			if frame != null:
				assert_eq(frame.atlas, interestelar.hull_texture)
				assert_eq(frame.region, expected_regions[animation_index + frame_index * 5])
