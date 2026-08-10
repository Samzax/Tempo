extends GutTest

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const BASE_SHIP := preload("res://resources/ships/base.tres")


func _player_fixture() -> Dictionary:
	var player := PLAYER_SCENE.instantiate() as Player
	var base_muzzle_position := (player.get_node("Muzzle") as Marker2D).position
	add_child_autofree(player)
	await get_tree().process_frame
	return {
		"player": player,
		"base_muzzle_position": base_muzzle_position,
	}


func _ship_with_offset(offset: Vector2) -> ShipDef:
	var ship := BASE_SHIP.duplicate(true) as ShipDef
	ship.muzzle_offset = offset
	return ship


func test_default_ship_def_keeps_the_scene_muzzle_position() -> void:
	var fixture := await _player_fixture()
	var player := fixture["player"] as Player
	var base_position: Vector2 = fixture["base_muzzle_position"]
	var ship := ShipDef.new()

	assert_eq(ship.muzzle_offset, Vector2.ZERO)
	assert_true(player.configure_ship(ship))
	assert_eq(player.muzzle.position, base_position)


func test_default_base_ship_resource_keeps_the_scene_muzzle_position() -> void:
	var fixture := await _player_fixture()
	var player := fixture["player"] as Player
	var base_position: Vector2 = fixture["base_muzzle_position"]

	assert_true(player.configure_ship(BASE_SHIP))
	assert_eq(player.muzzle.position, base_position + BASE_SHIP.muzzle_offset)


func test_ship_offset_is_additive_to_the_base_muzzle_position() -> void:
	var fixture := await _player_fixture()
	var player := fixture["player"] as Player
	var base_position: Vector2 = fixture["base_muzzle_position"]
	var offset := Vector2(4.0, -3.0)

	assert_true(player.configure_ship(_ship_with_offset(offset)))
	assert_eq(player.muzzle.position, base_position + offset)


func test_swapping_ships_uses_the_new_offset_without_accumulating_the_previous_one() -> void:
	var fixture := await _player_fixture()
	var player := fixture["player"] as Player
	var base_position: Vector2 = fixture["base_muzzle_position"]
	var offset_a := Vector2(5.0, 2.0)
	var offset_b := Vector2(-3.0, 6.0)

	assert_true(player.configure_ship(_ship_with_offset(offset_a)))
	assert_eq(player.muzzle.position, base_position + offset_a)
	assert_true(player.configure_ship(_ship_with_offset(offset_b)))
	assert_eq(player.muzzle.position, base_position + offset_b)


func test_zero_offset_restores_the_base_muzzle_position() -> void:
	var fixture := await _player_fixture()
	var player := fixture["player"] as Player
	var base_position: Vector2 = fixture["base_muzzle_position"]

	assert_true(player.configure_ship(_ship_with_offset(Vector2(7.0, -4.0))))
	assert_true(player.configure_ship(_ship_with_offset(Vector2.ZERO)))
	assert_eq(player.muzzle.position, base_position)


func test_omni_ship_with_non_zero_muzzle_offset_fails_content_validation() -> void:
	var ship := _ship_with_offset(Vector2(1.0, 0.0))
	ship.movement_style = "omni"

	var errors := ship.validate_content()

	assert_string_contains("\n".join(errors), "muzzle_offset diferente de zero so e suportado com movement_style aim_forward.")


# _fire is intentionally not exercised here: it depends on Pools and EffectDispatcher,
# while these tests cover the Muzzle position contract without fragile runtime doubles.
