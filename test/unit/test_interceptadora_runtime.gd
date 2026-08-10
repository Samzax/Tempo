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

const HULL_ANIMATIONS := [&"hard_left", &"soft_left", &"neutral", &"soft_right", &"hard_right"]

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

func test_interceptor_trail_is_deterministic_fixed_duration_and_cleans_up() -> void:
	var trail_scene := load("res://scenes/effects/interceptor_blink_trail.tscn") as PackedScene
	var first := trail_scene.instantiate()
	var second := trail_scene.instantiate()
	_effects.add_child(first)
	_effects.add_child(second)
	first.configure(Vector2(12, 18), Vector2(172, 62), _character.thrust_color, 12.0, 0.05)
	second.configure(Vector2(12, 18), Vector2(172, 62), _character.thrust_color, 12.0, 8.0)
	assert_eq(first._duration, 0.4)
	assert_eq(first.outer_line.points, second.outer_line.points)
	assert_eq(first.outer_line.default_color, second.outer_line.default_color)
	assert_null(first.get("random_number_generator"))
	assert_eq(first.outer_line.default_color, Color(0.12, 0.9, 1.0, 0.9).lerp(_character.thrust_color, 0.12))
	assert_eq(first.core_line.default_color, Color.WHITE)
	first._process(0.39)
	assert_false(first.is_queued_for_deletion())
	first._process(0.01)
	assert_true(first.is_queued_for_deletion())

func test_interceptor_blink_uses_specialized_fx_without_generic_rings() -> void:
	_player._blink_cd = 0.0
	assert_true(_player.try_blink(Vector2.RIGHT))
	assert_eq(_effects.get_child_count(), 1)
	assert_eq(_effects.get_child(0).scene_file_path, "res://scenes/effects/interceptor_blink_trail.tscn")

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

func test_real_interceptadora_scales_every_scene_atlas_region_to_64_frames() -> void:
	var interceptor := load("res://resources/ships/interceptadora.tres") as ShipDef
	assert_not_null(interceptor)
	if interceptor == null:
		return
	var player := _instantiate_player_with_real_ship(interceptor)
	await get_tree().process_frame
	_assert_hull_atlas_regions(player, Vector2i(64, 64))

func test_real_base_ship_preserves_every_scene_atlas_region_at_legacy_size() -> void:
	var base := load("res://resources/ships/base.tres") as ShipDef
	assert_not_null(base)
	if base == null:
		return
	var player := _instantiate_player_with_real_ship(base)
	await get_tree().process_frame
	_assert_hull_atlas_regions(player, Vector2i(16, 24))

func test_interceptadora_scales_only_its_animated_sprite_and_resets_on_ship_swap() -> void:
	assert_eq(_player.sprite.scale, Vector2(0.7, 0.7))
	assert_eq(_player.visual_root.scale, Vector2.ONE)
	assert_eq(_player.muzzle.scale, Vector2.ONE)
	assert_eq(_player.body_collision.scale, Vector2.ONE)
	assert_eq(_player.hurtbox.scale, Vector2.ONE)
	assert_eq(_player.thruster.scale, Vector2.ONE)
	var base := load("res://resources/ships/base.tres") as ShipDef
	assert_not_null(base)
	if base != null:
		var secondary := _instantiate_player_with_real_ship(base)
		await get_tree().process_frame
		assert_eq(_player.sprite.scale, Vector2(0.7, 0.7))
		assert_eq(secondary.sprite.scale, Vector2.ONE)
		assert_true(_player.configure_ship(base))
		assert_eq(_player.sprite.scale, Vector2.ONE)

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

func _instantiate_player_with_real_ship(ship: ShipDef) -> Player:
	var player := load("res://scenes/player/player.tscn").instantiate() as Player
	player.ship = ship
	player.character = load("res://resources/characters/base.tres") as CharacterDef
	_root.add_child(player)
	return player

func _assert_hull_atlas_regions(player: Player, frame_size: Vector2i) -> void:
	var frames := player.sprite.sprite_frames
	var scale := Vector2(frame_size) / Vector2(16, 24)
	for animation_index in HULL_ANIMATIONS.size():
		var animation_name: StringName = HULL_ANIMATIONS[animation_index]
		assert_eq(frames.get_frame_count(animation_name), 2)
		for frame_index in 2:
			var atlas := frames.get_frame_texture(animation_name, frame_index) as AtlasTexture
			assert_not_null(atlas)
			if atlas != null:
				var original_position := Vector2(animation_index * 16, frame_index * 24)
				assert_eq(atlas.region.size, Vector2(frame_size))
				assert_eq(atlas.region.position, original_position * scale)
