extends GutTest

const ENGINEER_DEPLOYABLE_SCENE := preload("res://scenes/deployables/engineer_deployable.tscn")

func test_engineer_deployable_scene_has_textured_drone_sprite() -> void:
	var deployable := ENGINEER_DEPLOYABLE_SCENE.instantiate() as EngineerDeployable
	add_child_autofree(deployable)

	var drone_sprite := deployable.get_node_or_null(^"DroneSprite") as Sprite2D
	assert_not_null(drone_sprite)
	if drone_sprite != null:
		assert_almost_eq(drone_sprite.scale.x, 0.333333, 0.00001)
		assert_almost_eq(drone_sprite.scale.y, 0.333333, 0.00001)
		assert_not_null(drone_sprite.texture)
		if drone_sprite.texture != null:
			assert_eq(drone_sprite.texture.get_size(), Vector2(32, 32))
			assert_eq(drone_sprite.texture.resource_path, "res://assets/sprites/engenheira_drone.png")
		assert_eq(drone_sprite.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
		assert_true(drone_sprite.centered)
		assert_eq(drone_sprite.hframes, 1)
		assert_eq(drone_sprite.vframes, 1)

func test_engineer_deployable_scene_exposes_muzzle_offset() -> void:
	var deployable := ENGINEER_DEPLOYABLE_SCENE.instantiate() as EngineerDeployable
	add_child_autofree(deployable)

	var muzzle := deployable.get_node(^"Muzzle") as Marker2D
	assert_eq(muzzle.position, Vector2(0, -4))


func test_drone_sprite_visibility_matches_deployable_kind() -> void:
	var deployable := ENGINEER_DEPLOYABLE_SCENE.instantiate() as EngineerDeployable
	var deploying_player := Node2D.new()
	add_child_autofree(deployable)
	add_child_autofree(deploying_player)

	deployable.configure(EngineerDeployable.Kind.TRAP, deploying_player, Vector2.ZERO)
	assert_false(deployable.drone_sprite.visible)

	deployable.configure(EngineerDeployable.Kind.DRONE, deploying_player, Vector2.ZERO)
	assert_true(deployable.drone_sprite.visible)

	deployable.configure(EngineerDeployable.Kind.OVERCLOCK_STATION, deploying_player, Vector2.ZERO)
	assert_false(deployable.drone_sprite.visible)
