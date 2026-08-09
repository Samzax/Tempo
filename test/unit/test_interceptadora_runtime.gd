extends GutTest

class DamageTarget extends Node2D:
	var calls: Array[DamageInfo] = []

	func take_damage(info: DamageInfo) -> void:
		calls.append(info)

var _root: Node2D
var _effects: Node2D
var _projectiles: Node2D
var _player: Player
var _target: DamageTarget
var _ship: ShipDef
var _character: CharacterDef

func before_each() -> void:
	_root = Node2D.new()
	add_child(_root)
	_effects = Node2D.new()
	_effects.add_to_group("effects")
	_projectiles = Node2D.new()
	_projectiles.add_to_group("projectiles")
	_root.add_child(_effects)
	_root.add_child(_projectiles)
	_ship = (load("res://resources/ships/interceptadora.tres") as ShipDef).duplicate(true)
	_ship.blink_trail_enabled = true
	_ship.blink_trail_damage = 4.5
	_ship.blink_trail_width = 10.0
	_ship.blink_trail_duration = 0.2
	_ship.detail_lines_enabled = true
	_ship.detail_lines_pulse_frequency = 2.0
	_ship.detail_lines_alpha_min = 0.2
	_ship.detail_lines_alpha_max = 0.8
	_ship.detail_lines_width = 2.0
	_ship.frame_size = Vector2i(64, 64)
	_character = CharacterDef.new()
	_character.id = &"test_pilot"
	_character.thrust_color = Color(0.2, 0.7, 1.0)
	_player = load("res://scenes/player/player.tscn").instantiate()
	_player.ship = _ship
	_player.character = _character
	_player.position = Vector2(100, 100)
	_root.add_child(_player)
	_target = DamageTarget.new()
	_target.add_to_group("enemies")
	_target.position = Vector2(150, 100)
	_root.add_child(_target)
	await get_tree().process_frame
	_player.set_room_bounds(Rect2(Vector2.ZERO, Vector2(240, 180)))

func after_each() -> void:
	if is_instance_valid(_root):
		_root.free()

func test_aligned_target_is_damaged_once_with_real_damage_info() -> void:
	_player._resolve_blink_trail_damage(Vector2(100, 100), Vector2(200, 100))
	assert_eq(_target.calls.size(), 1)
	var info := _target.calls[0]
	assert_eq(info.source, _player)
	assert_true(info.tags.has(&"blink"))
	assert_true(info.tags.has(&"interceptor_blink_trail"))
	assert_eq(info.amount, 4.5)

func test_target_outside_trail_width_is_not_hit() -> void:
	_target.position = Vector2(150, 106)
	_player._resolve_blink_trail_damage(Vector2(100, 100), Vector2(200, 100))
	assert_eq(_target.calls.size(), 0)

func test_clamped_endpoint_and_zero_length_trail_are_safe() -> void:
	_target.position = Vector2(110, 100)
	_player._resolve_blink_trail_damage(Vector2(100, 100), Vector2(100, 100))
	assert_eq(_target.calls.size(), 0)
	_player._resolve_blink_trail_damage(Vector2(200, 100), Vector2(100, 100))
	assert_eq(_target.calls.size(), 1)

func test_public_try_blink_uses_real_player_and_clamps_to_room() -> void:
	_player.position = Vector2(120, 90)
	_player._blink_cd = 0.0
	assert_true(_player.try_blink(Vector2.RIGHT))
	assert_eq(_player.position, Vector2(230, 90))
	assert_eq(_player.velocity, Vector2.ZERO)
	assert_true(_player.is_invulnerable())

func test_public_try_blink_zero_length_direction_uses_aim_without_input() -> void:
	_player.position = Vector2(120, 90)
	_player._aim_vector = Vector2.LEFT
	_player._blink_cd = 0.0
	assert_true(_player.try_blink(Vector2.ZERO))
	assert_eq(_player.position, Vector2(10, 90))

func test_non_positive_duration_does_not_damage_or_spawn_trail() -> void:
	for duration in [0.0, -0.1]:
		_ship.blink_trail_duration = duration
		_player._resolve_blink_trail_damage(Vector2(100, 100), Vector2(200, 100))
		_player._spawn_interceptor_blink_trail(Vector2(100, 100), Vector2(200, 100))
	assert_eq(_target.calls.size(), 0)
	assert_eq(_effects.get_child_count(), 0)

func test_neutral_ship_defaults_keep_bruta_and_base_inert() -> void:
	var defaults := ShipDef.new()
	assert_false(defaults.blink_trail_enabled)
	assert_eq(defaults.blink_trail_damage, 0.0)
	assert_eq(defaults.blink_trail_width, 0.0)
	assert_gt(defaults.blink_trail_duration, 0.0)
	var base: ShipDef = load("res://resources/ships/base.tres")
	var bruta: ShipDef = load("res://resources/ships/bruta.tres")
	assert_false(base.blink_trail_enabled)
	assert_false(bruta.blink_trail_enabled)
	assert_eq(_damage_for(base), 1.0)
	assert_eq(_damage_for(bruta), 1.5)

func test_detail_lines_configure_base_frame_preserves_points_and_width() -> void:
	var lines := _player.get_node("VisualRoot/InterceptorDetailLines")
	lines.configure(Color.WHITE, 1.0, 0.2, 0.8, 2.0, Vector2(16, 24))
	assert_eq(lines.lines[0].points, PackedVector2Array([Vector2(-5, -8), Vector2(-2, -2), Vector2(-5, 5)]))
	assert_eq(lines.lines[1].points, PackedVector2Array([Vector2(0, -9), Vector2(0, 7)]))
	assert_eq(lines.lines[2].points, PackedVector2Array([Vector2(5, -8), Vector2(2, -2), Vector2(5, 5)]))
	assert_eq(lines._base_width, 2.0)

func test_detail_lines_configure_64_frame_scales_geometry_and_width_from_x() -> void:
	var lines := _player.get_node("VisualRoot/InterceptorDetailLines")
	lines.configure(Color.WHITE, 1.0, 0.2, 0.8, 2.0, Vector2(64, 64))
	assert_eq(lines.lines[0].points, PackedVector2Array([Vector2(-20, -64.0 / 3.0), Vector2(-8, -16.0 / 3.0), Vector2(-20, 40.0 / 3.0)]))
	assert_eq(lines.lines[1].points, PackedVector2Array([Vector2(0, -24), Vector2(0, 56.0 / 3.0)]))
	assert_eq(lines.lines[2].points, PackedVector2Array([Vector2(20, -64.0 / 3.0), Vector2(8, -16.0 / 3.0), Vector2(20, 40.0 / 3.0)]))
	assert_eq(lines._base_width, 8.0)
	lines.boost_for_blink()
	lines._process(0.01)
	assert_almost_eq(lines.lines[0].width, 8.0 * (1.0 + sin(0.01 / lines.BLINK_BOOST_DURATION * PI) * 0.16), 0.0001)

func test_detail_lines_reconfigure_does_not_accumulate_scale() -> void:
	var lines := _player.get_node("VisualRoot/InterceptorDetailLines")
	lines.configure(Color.WHITE, 1.0, 0.2, 0.8, 2.0, Vector2(64, 64))
	lines.configure(Color.WHITE, 1.0, 0.2, 0.8, 2.0, Vector2(16, 24))
	assert_eq(lines.lines[0].points, PackedVector2Array([Vector2(-5, -8), Vector2(-2, -2), Vector2(-5, 5)]))
	assert_eq(lines.lines[1].points, PackedVector2Array([Vector2(0, -9), Vector2(0, 7)]))
	assert_eq(lines.lines[2].points, PackedVector2Array([Vector2(5, -8), Vector2(2, -2), Vector2(5, 5)]))
	assert_eq(lines._base_width, 2.0)

func test_opt_in_detail_lines_use_character_color_pulse_and_blink_boost() -> void:
	var lines := _player.get_node("VisualRoot/InterceptorDetailLines")
	var body_shape := _player.body_collision.shape
	var hurtbox_shape := _player.hurtbox_collision.shape
	assert_true(_ship.detail_lines_enabled)
	assert_eq(lines.lines.size(), 3)
	assert_eq(lines.get_children().filter(func(child): return child is Line2D).size(), 3)
	var expected_points: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(-20, -64.0 / 3.0), Vector2(-8, -16.0 / 3.0), Vector2(-20, 40.0 / 3.0)]),
		PackedVector2Array([Vector2(0, -24), Vector2(0, 56.0 / 3.0)]),
		PackedVector2Array([Vector2(20, -64.0 / 3.0), Vector2(8, -16.0 / 3.0), Vector2(20, 40.0 / 3.0)]),
	]
	var before: float = 8.0
	var alpha_before: float = lines.lines[0].default_color.a
	for index in lines.lines.size():
		var line: Line2D = lines.lines[index]
		assert_eq(line.points, expected_points[index])
		assert_eq(line.width, before)
		assert_eq(line.default_color, Color(_character.thrust_color.r, _character.thrust_color.g, _character.thrust_color.b, alpha_before))
	lines._process(0.13)
	var expected_pulse_alpha: float = lerpf(_ship.detail_lines_alpha_min, _ship.detail_lines_alpha_max, 0.5 + 0.5 * sin(lines._elapsed * TAU * _ship.detail_lines_pulse_frequency))
	for line in lines.lines:
		assert_almost_eq(line.default_color.a, expected_pulse_alpha, 0.0001)
		assert_eq(line.default_color, Color(_character.thrust_color.r, _character.thrust_color.g, _character.thrust_color.b, line.default_color.a))
		assert_eq(line.width, before)
	_player._boost_detail_lines_for_blink()
	lines._process(0.01)
	var boost_amount: float = sin(0.01 / lines.BLINK_BOOST_DURATION * PI)
	var expected_boosted_width: float = before * (1.0 + boost_amount * (lines.BLINK_WIDTH_MULTIPLIER - 1.0))
	var expected_boosted_alpha: float = clampf(lerpf(_ship.detail_lines_alpha_min, _ship.detail_lines_alpha_max, 0.5 + 0.5 * sin(lines._elapsed * TAU * _ship.detail_lines_pulse_frequency)) + boost_amount * 0.2, 0.0, 1.0)
	for line in lines.lines:
		assert_gt(line.width, before)
		assert_almost_eq(line.width, expected_boosted_width, 0.0001)
		assert_almost_eq(line.default_color.a, expected_boosted_alpha, 0.0001)
		assert_eq(line.default_color, Color(_character.thrust_color.r, _character.thrust_color.g, _character.thrust_color.b, line.default_color.a))
	var boosted_width: float = lines.lines[0].width
	lines._process(0.5)
	for line in lines.lines:
		assert_eq(line.width, before)
	assert_gt(boosted_width, lines.lines[0].width)
	assert_eq(lines.find_children("*", "CollisionObject2D", true, false).size(), 0)
	assert_eq(_player.velocity, Vector2.ZERO)
	assert_eq(_player.collision_layer, 2)
	assert_eq(_player.collision_mask, 1)
	assert_eq(_player.body_collision.shape, body_shape)
	assert_eq(_player.hurtbox_collision.shape, hurtbox_shape)

func test_projectile_consumes_statblock_damage() -> void:
	_player._stats.set_base(&"damage", 7.25)
	_player._aim_vector = Vector2.UP
	_player._fire()
	assert_eq(_projectiles.get_child_count(), 1)
	var bullet: Area2D = _projectiles.get_child(0)
	bullet._active = false
	bullet._on_hit(_target)
	assert_eq(_target.calls.size(), 1)
	assert_eq(_target.calls[0].amount, 7.25)
	assert_eq(_target.calls[0].source, _player)
	assert_true(_target.calls[0].tags.has(&"projectile"))

func _damage_for(ship: ShipDef) -> float:
	var stats := StatBlock.new(StatCatalog.get_all())
	Loadout.apply(stats, ship, null)
	return stats.get_stat(&"damage")
