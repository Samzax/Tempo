extends GutTest

const ENGINEER_DEPLOYABLE_SCENE := preload("res://scenes/deployables/engineer_deployable.tscn")

func _damage(amount: float, depth: int = 0) -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = amount
	info.trigger_depth = depth
	return info

func test_engineer_deployable_propagates_partial_and_lethal_damage() -> void:
	var deployable := ENGINEER_DEPLOYABLE_SCENE.instantiate()
	deployable.kind = EngineerDeployable.Kind.OVERCLOCK_STATION
	add_child_autofree(deployable)
	await get_tree().process_frame

	assert_almost_eq(deployable.take_damage(_damage(1.25)), 1.25, 0.001)
	assert_almost_eq(deployable.health.health, 4.75, 0.001)
	assert_almost_eq(deployable.take_damage(_damage(20.0)), 4.75, 0.001)
	assert_eq(deployable.take_damage(_damage(1.0)), 0.0)

func test_engineer_deployable_blocks_invalid_damage_without_mutation() -> void:
	var deployable := ENGINEER_DEPLOYABLE_SCENE.instantiate()
	deployable.kind = EngineerDeployable.Kind.OVERCLOCK_STATION
	add_child_autofree(deployable)
	await get_tree().process_frame
	var before: float = deployable.health.health

	for info in [null, _damage(0.0), _damage(-1.0), _damage(NAN), _damage(INF)]:
		assert_eq(deployable.take_damage(info), 0.0)
	assert_eq(deployable.health.health, before)

func test_engineer_deployable_blocks_player_source_without_mutation() -> void:
	var deployable := ENGINEER_DEPLOYABLE_SCENE.instantiate()
	deployable.kind = EngineerDeployable.Kind.OVERCLOCK_STATION
	add_child_autofree(deployable)
	await get_tree().process_frame
	var player_source := Node2D.new()
	player_source.add_to_group(&"player")
	add_child_autofree(player_source)
	var before: float = deployable.health.health
	var info := _damage(1.0)
	info.source = player_source

	assert_eq(deployable.take_damage(info), 0.0)
	assert_eq(deployable.health.health, before)

func test_trap_burst_and_aoe_detonate_and_return_zero() -> void:
	for tag in [&"burst", &"aoe"]:
		var trap := ENGINEER_DEPLOYABLE_SCENE.instantiate()
		trap.kind = EngineerDeployable.Kind.TRAP
		add_child_autofree(trap)
		await get_tree().process_frame
		var info := _damage(1.0)
		info.tags = [tag]

		assert_eq(trap.take_damage(info), 0.0)
		assert_true(trap.is_queued_for_deletion())
