extends GutTest

const LASER := preload("res://scripts/enemies/bosses/wings/laser_beam_2d.gd")

class DamageTarget extends StaticBody2D:
	var health: HealthComponent
	var hits := 0
	func _ready() -> void:
		health = HealthComponent.new()
		health.max_health = 1000
		health.health = 1000
		add_child(health)
	func take_damage(info: DamageInfo) -> int:
		hits += 1
		return health.apply_damage(info)

func _target(group: StringName, layer := 2) -> DamageTarget:
	var target := DamageTarget.new()
	target.add_to_group(group)
	target.collision_layer = layer
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 8.0
	shape.shape = circle
	target.add_child(shape)
	add_child_autofree(target)
	return target

func _beam(origin := Vector2.ZERO) -> LaserBeam2D:
	var beam := LASER.new()
	add_child_autofree(beam)
	beam.configure(origin, 25, self, [&"laser"], 6)
	return beam

func test_telegraph_does_not_damage() -> void:
	var target := _target(&"player")
	var beam := _beam()
	beam.set_tracking_target(target)
	assert_true(beam.start_telegraph())
	await get_tree().physics_frame
	assert_eq(target.hits, 0)

func test_firing_tracks_current_player_while_origin_stays_fixed() -> void:
	var target := _target(&"player")
	var beam := _beam(Vector2(-100, 0))
	target.global_position = Vector2(100, 0)
	beam.set_tracking_target(target)
	beam.start_telegraph(); beam.start_firing()
	await get_tree().physics_frame
	var origin := beam.global_position
	target.global_position = Vector2(100, 100)
	await get_tree().physics_frame
	assert_eq(beam.fixed_origin, origin)
	assert_eq(beam.global_position, origin)
	assert_ne(beam.global_rotation, 0.0)

func test_query_contract_is_16px_mask_6_and_filters_damage_targets() -> void:
	var beam := _beam()
	assert_eq(beam.beam_width_px, 16.0)
	assert_eq(beam.collision_mask, 6)
	var valid := _target(&"player")
	var enemy := _target(&"enemies")
	var invalid := _target(&"player")
	invalid.health = null
	assert_true(beam._is_damage_target(valid))
	assert_true(beam._is_damage_target(enemy))
	assert_false(beam._is_damage_target(invalid))

func test_one_beam_dedupes_for_local_tick_but_two_beams_stack_damage() -> void:
	var target := _target(&"player")
	var a := _beam(); var b := _beam()
	for beam in [a, b]:
		beam.set_tracking_target(target)
		beam.start_telegraph(); beam.start_firing()
	await get_tree().physics_frame
	assert_eq(target.hits, 2)
	a._apply_firing_hits()
	assert_eq(target.hits, 2)

func test_firing_never_damages_damage_source_but_damages_external_target() -> void:
	var source := _target(&"enemies", 4)
	var external := _target(&"enemies", 4)
	source.global_position = Vector2.ZERO
	external.global_position = Vector2(100, 0)
	var beam := LASER.new()
	add_child_autofree(beam)
	beam.configure(Vector2.ZERO, 25, source, [&"laser", &"halo"], 6)
	assert_false(beam._is_damage_target(source))
	assert_true(beam._is_damage_target(external))
	beam.start_telegraph(); beam.start_firing()
	await get_tree().physics_frame
	assert_eq(source.hits, 0)
	assert_eq(external.hits, 1)

func test_stop_and_cleanup_clear_state() -> void:
	var beam := _beam()
	beam.start_telegraph(); beam.start_firing(); beam.stop()
	assert_eq(beam.state, LASER.State.INACTIVE)
	beam.cleanup()
	assert_eq(beam.state, LASER.State.INACTIVE)
	assert_null(beam.tracking_target)
	assert_null(beam.damage_source)
	assert_true(beam.damage_tags.is_empty())
	assert_eq(beam.runtime_snapshot(), {"state": LASER.State.INACTIVE, "origin": Vector2.ZERO, "rotation": 0.0, "hit_targets": 0})
