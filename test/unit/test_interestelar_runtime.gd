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
	assert_eq(_target.calls[0].amount, 1.0)
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
	assert_eq(manager.active_segment_count(), 2)
	var first_origin: Vector2 = manager.segments[0]["origin"]
	var second_origin: Vector2 = manager.segments[1]["origin"]
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
	assert_eq(manager.active_segment_count(), 2)
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
