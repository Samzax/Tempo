extends GutTest

var _root: Node2D
var _projectiles: Node2D
var _player: Player

func before_each() -> void:
	_root = Node2D.new()
	add_child_autofree(_root)
	_projectiles = Node2D.new()
	_projectiles.add_to_group("projectiles")
	_root.add_child(_projectiles)
	_player = load("res://scenes/player/player.tscn").instantiate() as Player
	_player.ship = load("res://resources/ships/rastreadora.tres") as ShipDef
	_player.character = load("res://resources/characters/base.tres") as CharacterDef
	_root.add_child(_player)
	await get_tree().process_frame

func after_each() -> void:
	Input.action_release(&"shoot")

func test_rastreadora_real_scene_builds_neutral_and_four_frame_fire_atlas() -> void:
	var frames := _player.sprite.sprite_frames
	assert_eq(frames.get_frame_count(&"neutral"), 1)
	assert_eq(frames.get_frame_count(&"fire"), 4)
	assert_eq(frames.get_animation_speed(&"fire"), 12.0)
	assert_false(frames.get_animation_loop(&"fire"))
	var expected := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 0)]
	var ship := _player.ship
	for index in expected.size():
		var atlas := frames.get_frame_texture(&"fire", index) as AtlasTexture
		assert_not_null(atlas)
		if atlas != null:
			assert_eq(atlas.atlas, ship.hull_texture)
			assert_eq(atlas.region, Rect2(Vector2(expected[index] * ship.frame_size), Vector2(ship.frame_size)))

func test_valid_fire_creates_bullet_and_starts_fire_with_current_bullet_contract() -> void:
	_player._aim_vector = Vector2.UP
	_player._fire()
	assert_eq(_projectiles.get_child_count(), 1)
	var bullet := _projectiles.get_child(0)
	assert_true(bullet._active)
	assert_eq(bullet.speed, 320.0)
	assert_eq(bullet.lifetime, 2.0)
	assert_eq(bullet.damage, 18.0)
	assert_eq(_player.sprite.animation, &"fire")

func test_invalid_fire_does_not_create_bullet_or_start_fire() -> void:
	_player._aim_vector = Vector2.UP
	_player.ship.has_muzzle = false
	_player._fire()
	assert_eq(_projectiles.get_child_count(), 0)
	assert_eq(_player.sprite.animation, &"neutral")

func test_handle_fire_respects_rastreadora_fire_rate_cadence() -> void:
	_player._aim_vector = Vector2.UP
	_player._stats.set_base(&"fire_rate", 0.8)
	Input.action_press(&"shoot")
	_player._handle_fire(0.0)
	assert_eq(_projectiles.get_child_count(), 1)
	assert_eq(_player.sprite.animation, &"fire")
	assert_almost_eq(_player._fire_cooldown, 1.25, 0.00001)
	_player._tick_timers(1.24)
	_player._handle_fire(0.0)
	assert_eq(_projectiles.get_child_count(), 1)
	_player._tick_timers(0.02)
	_player._handle_fire(0.0)
	assert_eq(_projectiles.get_child_count(), 2)

func test_fire_animation_ends_in_neutral() -> void:
	_player._fire()
	_player._on_hull_animation_finished()
	assert_eq(_player.sprite.animation, &"neutral")

func test_update_bank_does_not_cancel_fire_animation() -> void:
	_player._fire()
	_player._update_bank()
	assert_eq(_player.sprite.animation, &"fire")

func test_legacy_5x2_and_omni_ships_do_not_gain_fire_animation() -> void:
	for path in ["res://resources/ships/base.tres", "res://resources/ships/interestelar.tres"]:
		var ship := load(path) as ShipDef
		assert_not_null(ship)
		if ship == null:
			continue
		var player := load("res://scenes/player/player.tscn").instantiate() as Player
		player.ship = ship
		player.character = load("res://resources/characters/base.tres") as CharacterDef
		_root.add_child(player)
		await get_tree().process_frame
		assert_false(player._uses_two_by_two_fire_animation())
		assert_false(player.sprite.sprite_frames.has_animation(&"fire"))
		player.queue_free()

func test_custom_atlas_does_not_gain_fire_animation_or_regress_to_neutral() -> void:
	var player := load("res://scenes/player/player.tscn").instantiate() as Player
	player.ship = load("res://resources/ships/interestelar.tres") as ShipDef
	player.character = load("res://resources/characters/base.tres") as CharacterDef
	_root.add_child(player)
	await get_tree().process_frame
	assert_false(player._uses_two_by_two_fire_animation())
	assert_false(player.sprite.sprite_frames.has_animation(&"fire"))
	player.sprite.play(&"hard_left")
	player._update_bank()
	assert_eq(player.sprite.animation, &"neutral")
	player.queue_free()
