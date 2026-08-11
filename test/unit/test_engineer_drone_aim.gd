extends GutTest

const SCENE := preload("res://scenes/deployables/engineer_deployable.tscn")
const EPS := 0.0001

func _fixture(use_legacy_owner := false) -> Array:
	var projectiles := Node2D.new()
	projectiles.add_to_group(&"projectiles")
	add_child_autofree(projectiles)
	var owner: Node2D = AimOwnerLegacyStub.new() if use_legacy_owner else AimOwnerStub.new()
	add_child_autofree(owner)
	var drone := SCENE.instantiate() as EngineerDeployable
	add_child_autofree(drone)
	drone.configure(EngineerDeployable.Kind.DRONE, owner, Vector2.ZERO)
	drone.global_position = Vector2(120.0, 90.0)
	await get_tree().process_frame
	return [drone, owner, projectiles]

func test_visual_aim_advances_by_shortest_arc_and_does_not_snap() -> void:
	var fixture := await _fixture()
	var drone: EngineerDeployable = fixture[0]
	var owner: AimOwnerStub = fixture[1]
	owner.fire_direction = Vector2(-1.0, 0.05).normalized()
	drone._update_drone_visual_aim(0.1)
	var first_angle := drone.drone_sprite.rotation
	assert_gt(absf(first_angle), EPS)
	assert_lt(absf(first_angle), PI)
	var before := first_angle
	owner.fire_direction = Vector2(-1.0, -0.05).normalized()
	drone._update_drone_visual_aim(0.1)
	assert_lt(absf(angle_difference(drone.drone_sprite.rotation, before)), PI * 0.5)
	assert_lt(absf(drone.drone_sprite.rotation - (owner.fire_direction.angle() + PI / 2.0)), PI)

func test_visual_smoothing_uses_full_16_response() -> void:
	var fixture := await _fixture()
	var drone: EngineerDeployable = fixture[0]
	var owner: AimOwnerStub = fixture[1]
	owner.fire_direction = Vector2.RIGHT
	drone._update_drone_visual_aim(0.1)
	var expected := (PI / 2.0) * (1.0 - exp(-16.0 * 0.1))
	assert_almost_eq(drone.drone_sprite.rotation, expected, 0.02)

func test_visual_aim_only_changes_drone_sprite_and_fire_uses_muzzle_origin() -> void:
	var fixture := await _fixture()
	var drone: EngineerDeployable = fixture[0]
	var owner: AimOwnerStub = fixture[1]
	var projectiles: Node2D = fixture[2]
	drone.rotation = 0.37
	drone.muzzle.position = Vector2(11.0, -4.0)
	drone.muzzle.rotation = 0.21
	var deployable_transform := drone.global_transform
	var muzzle_transform := drone.muzzle.global_transform
	var collision_transform := drone.influence.global_transform
	owner.fire_direction = Vector2(0.2, 1.0).normalized()
	drone._update_drone_visual_aim(0.1)
	assert_eq(drone.global_transform, deployable_transform)
	assert_eq(drone.muzzle.global_transform, muzzle_transform)
	assert_eq(drone.influence.global_transform, collision_transform)
	drone._fire_drone(0.0)
	assert_eq(owner.last_origin, drone.muzzle.global_position)
	var bullet := projectiles.get_child(0) as Area2D
	assert_eq(bullet._velocity.normalized(), owner.fire_direction)

func test_drone_fire_activates_bullet_at_real_muzzle_global_position() -> void:
	var fixture := await _fixture()
	var drone: EngineerDeployable = fixture[0]
	var projectiles: Node2D = fixture[2]
	var expected_position := drone.muzzle.global_position

	drone._fire_drone(0.0)

	assert_eq(projectiles.get_child_count(), 1)
	var bullet := projectiles.get_child(0) as Area2D
	assert_almost_eq(bullet.global_position, expected_position, Vector2(0.01, 0.01))

func test_configure_modes_reset_drone_visibility_and_rotation() -> void:
	var fixture := await _fixture()
	var drone: EngineerDeployable = fixture[0]
	var owner: AimOwnerStub = fixture[1]
	owner.fire_direction = Vector2.UP
	drone._update_drone_visual_aim(0.2)
	assert_ne(drone.drone_sprite.rotation, 0.0)
	drone.configure(EngineerDeployable.Kind.TRAP, owner, Vector2.ZERO)
	assert_false(drone.drone_sprite.visible)
	assert_eq(drone.drone_sprite.rotation, 0.0)
	drone.configure(EngineerDeployable.Kind.OVERCLOCK_STATION, owner, Vector2.ZERO)
	assert_false(drone.drone_sprite.visible)
	assert_eq(drone.drone_sprite.rotation, 0.0)
	drone.configure(EngineerDeployable.Kind.DRONE, owner, Vector2.ZERO)
	assert_true(drone.drone_sprite.visible)
	assert_eq(drone.drone_sprite.rotation, 0.0)

func test_legacy_aim_fallback_and_queued_owner_stop_fire_and_update() -> void:
	var fixture := await _fixture(true)
	var drone: EngineerDeployable = fixture[0]
	var owner: AimOwnerLegacyStub = fixture[1]
	var projectiles: Node2D = fixture[2]
	owner.aim_direction = Vector2.DOWN
	drone._fire_drone(0.0)
	assert_eq((projectiles.get_child(0) as Area2D)._velocity.normalized(), Vector2.DOWN)
	var rotation_before := drone.drone_sprite.rotation
	owner.queue_free()
	drone._physics_process(1.0)
	assert_eq(projectiles.get_child_count(), 1)
	assert_eq(drone.drone_sprite.rotation, rotation_before)

class AimOwnerStub extends Node2D:
	var fire_direction := Vector2.RIGHT
	var last_origin := Vector2.INF

	func get_fire_direction_from(origin: Vector2) -> Vector2:
		last_origin = origin
		return fire_direction

	func get_projectile_stat(_id: StringName, fallback: float) -> float:
		return fallback

class AimOwnerLegacyStub extends Node2D:
	var aim_direction := Vector2.RIGHT

	func get_aim_direction() -> Vector2:
		return aim_direction
