extends GutTest

const LASER_SCRIPT := preload("res://scripts/enemies/bosses/wings/laser_beam_2d.gd")
const LASER_SCENE_PATH := "res://scenes/enemies/bosses/wings/laser_beam_2d.tscn"

func test_visual_laser_scene_and_runtime_contract() -> void:
	var scene := load(LASER_SCENE_PATH) as PackedScene
	assert_not_null(scene, "laser_beam_2d.tscn must exist at the canonical res:// path")
	if scene == null:
		return

	var beam := scene.instantiate()
	add_child_autofree(beam)
	assert_true(beam is LaserBeam2D)
	assert_not_null(beam.get_node_or_null("Telegraph"))
	assert_not_null(beam.get_node_or_null("ActiveBeam"))
	assert_not_null(beam.get_node_or_null("Emitter"))
	assert_not_null(beam.get_node_or_null("Impact"))
	assert_true(beam.has_method("visual_runtime_snapshot"))
	var telegraph := beam.get_node("Telegraph") as Sprite2D
	var active := beam.get_node("ActiveBeam") as Sprite2D
	var emitter := beam.get_node("Emitter") as Sprite2D
	var impact := beam.get_node("Impact") as Sprite2D
	for visual in [telegraph, active, emitter, impact]:
		assert_eq(visual.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_eq(telegraph.texture_repeat, 0)
	assert_eq(active.texture_repeat, 1)
	assert_eq(emitter.texture_repeat, 0)
	assert_eq(impact.texture_repeat, 0)
	assert_false(telegraph.visible)
	assert_false(active.visible)
	assert_false(emitter.visible)
	assert_false(impact.visible)
	var visual_tags: Array[StringName] = [&"visual"]
	assert_true(beam.configure(Vector2(10, 15), 33, self, visual_tags))
	assert_eq(beam.global_position, Vector2(10, 15))
	assert_eq(beam.visual_runtime_snapshot(), {"has_visuals": true, "telegraph_visible": false, "active_beam_visible": false, "emitter_visible": false, "impact_visible": false, "beam_length_px": 900.0})

	assert_true(beam.configure_segment(Vector2(20, 30), Vector2(220, 130)))
	var length := Vector2(20, 30).distance_to(Vector2(220, 130))
	assert_eq(active.region_rect.size.x, length)
	assert_eq(active.region_rect.position, Vector2.ZERO)
	assert_eq(impact.position, Vector2(length, 0.0))
	assert_false(telegraph.visible)
	assert_false(active.visible)
	assert_false(emitter.visible)
	assert_false(impact.visible)
	assert_eq(beam.visual_runtime_snapshot(), {"has_visuals": true, "telegraph_visible": false, "active_beam_visible": false, "emitter_visible": false, "impact_visible": false, "beam_length_px": length})

	assert_true(beam.start_telegraph())
	assert_true(telegraph.visible)
	assert_false(active.visible)
	assert_true(emitter.visible)
	assert_false(impact.visible)

	assert_true(beam.start_firing())
	assert_false(telegraph.visible)
	assert_true(active.visible)
	assert_true(emitter.visible)
	assert_true(impact.visible)
	assert_eq(active.region_rect.size.x, length)
	assert_eq(impact.position, Vector2(length, 0.0))

	beam.stop()
	assert_false(telegraph.visible)
	assert_false(active.visible)
	assert_false(emitter.visible)
	assert_false(impact.visible)
	beam.cleanup()
	assert_eq(beam.state, LASER_SCRIPT.State.INACTIVE)
	assert_null(beam.damage_source)
	assert_true(beam.damage_tags.is_empty())
	assert_eq(beam.runtime_snapshot(), {"state": LASER_SCRIPT.State.INACTIVE, "origin": Vector2(20, 30), "rotation": Vector2(200, 100).angle(), "hit_targets": 0})
	assert_false(telegraph.visible)
	assert_false(active.visible)
	assert_false(emitter.visible)
	assert_false(impact.visible)

func test_visual_state_contract_and_geometry() -> void:
	var beam := LASER_SCRIPT.new() as LaserBeam2D
	add_child_autofree(beam)
	assert_true(beam.configure(Vector2(20, 30), 25, self, [&"laser"]))
	assert_true(beam.has_method("configure_segment"))
	assert_true(beam.configure_segment(Vector2(20, 30), Vector2(220, 130)))
	assert_eq(beam.global_position, Vector2(20, 30))
	assert_almost_eq(beam.beam_length_px, Vector2(20, 30).distance_to(Vector2(220, 130)), 0.001)
	assert_true(beam.has_method("visual_runtime_snapshot"))

func test_scene_free_instance_preserves_logical_snapshot_semantics() -> void:
	var beam := LASER_SCRIPT.new() as LaserBeam2D
	add_child_autofree(beam)
	assert_true(beam.configure(Vector2(4, 5), 7, self, [&"laser"]))
	var before: Dictionary = beam.runtime_snapshot()
	assert_true(beam.start_telegraph())
	assert_true(beam.start_firing())
	beam.stop()
	var after: Dictionary = beam.runtime_snapshot()
	assert_eq(before, {"state": LASER_SCRIPT.State.INACTIVE, "origin": Vector2(4, 5), "rotation": 0.0, "hit_targets": 0})
	assert_eq(after, {"state": LASER_SCRIPT.State.INACTIVE, "origin": Vector2(4, 5), "rotation": 0.0, "hit_targets": 0})

func test_childless_new_is_safe_and_has_no_visual_effect() -> void:
	var beam := LASER_SCRIPT.new() as LaserBeam2D
	add_child_autofree(beam)
	assert_eq(beam.get_child_count(), 0, "LaserBeam2D.new() must be explicitly childless")
	assert_true(beam.configure(Vector2(2, 3), 9, self, [&"childless"]))
	assert_true(beam.configure_segment(Vector2(2, 3), Vector2(12, 3)))
	assert_true(beam.start_telegraph())
	assert_true(beam.start_firing())
	beam.stop()
	beam.cleanup()
	assert_eq(beam.get_child_count(), 0)
	assert_eq(beam.state, LASER_SCRIPT.State.INACTIVE)
	assert_null(beam.damage_source)
	assert_true(beam.damage_tags.is_empty())
	assert_eq(beam.runtime_snapshot(), {"state": LASER_SCRIPT.State.INACTIVE, "origin": Vector2(2, 3), "rotation": 0.0, "hit_targets": 0})
	assert_eq(beam.visual_runtime_snapshot(), {"has_visuals": false, "telegraph_visible": false, "active_beam_visible": false, "emitter_visible": false, "impact_visible": false, "beam_length_px": 10.0})
