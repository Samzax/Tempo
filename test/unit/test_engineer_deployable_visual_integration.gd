extends GutTest

const SCENE := preload("res://scenes/deployables/engineer_deployable.tscn")
const TRAP_TEXTURE := "res://assets/sprites/deployables/engineer_trap_a_body.png"
const STATION_TEXTURE := "res://assets/sprites/deployables/engineer_overclock_station_c_body.png"
const AURA_TEXTURE := "res://assets/sprites/deployables/engineer_station_aura_fx.png"

class GrantRecipient extends Node2D:
	var grants := 0
	var revokes := 0
	func grant_shield_charge(_source: StringName) -> void:
		grants += 1
	func apply_temporary_modifier(_source: StringName, _stat: StringName, _op: int, _value: float, _duration: float) -> void:
		pass
	func revoke_shield_charge(_source: StringName) -> void:
		revokes += 1
	func remove_temporary_modifier(_source: StringName) -> void:
		pass

class TrapEnemy extends CharacterBody2D:
	var damages := 0
	func take_damage(_info: DamageInfo) -> float:
		damages += 1
		return 0.0

func _deployable() -> EngineerDeployable:
	var value := SCENE.instantiate() as EngineerDeployable
	add_child_autofree(value)
	await get_tree().process_frame
	return value

func _effect_count(parent: Node) -> int:
	var count := 0
	for child in parent.get_children():
		if child is Sprite2D and child != parent:
			count += 1
	return count

func _effect_with_frames(parent: Node, frame_count: int) -> Sprite2D:
	for child in parent.get_children():
		if child is Sprite2D and child.hframes == frame_count:
			return child
	return null

func test_scene_loads_deployable_assets_and_visual_contract() -> void:
	var deployable := await _deployable()
	var trap := deployable.trap_sprite
	var station := deployable.station_sprite
	var aura := deployable.station_aura

	assert_not_null(trap.texture)
	assert_not_null(station.texture)
	assert_not_null(aura.texture)
	assert_eq(trap.texture.resource_path, TRAP_TEXTURE)
	assert_eq(station.texture.resource_path, STATION_TEXTURE)
	assert_eq(aura.texture.resource_path, AURA_TEXTURE)
	assert_eq(trap.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_eq(station.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_eq(aura.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_eq(trap.scale, Vector2(0.5, 0.5))
	assert_eq(station.scale, Vector2(0.5, 0.5))
	assert_eq(aura.scale, Vector2.ONE)
	assert_eq(aura.hframes, 6)

func test_configure_shows_only_current_visual_and_clears_aura() -> void:
	var deployable := await _deployable()
	for selected in [EngineerDeployable.Kind.TRAP, EngineerDeployable.Kind.DRONE, EngineerDeployable.Kind.OVERCLOCK_STATION, EngineerDeployable.Kind.TRAP]:
		var owner := Node2D.new()
		add_child_autofree(owner)
		deployable.configure(selected, owner, Vector2.ZERO)
		assert_eq(deployable.trap_sprite.visible, selected == EngineerDeployable.Kind.TRAP)
		assert_eq(deployable.drone_sprite.visible, selected == EngineerDeployable.Kind.DRONE)
		assert_eq(deployable.station_sprite.visible, selected == EngineerDeployable.Kind.OVERCLOCK_STATION)
		assert_eq(deployable.station_aura.visible, selected == EngineerDeployable.Kind.OVERCLOCK_STATION)

func test_station_aura_starts_at_frame_zero_and_advances_six_frame_cycle() -> void:
	var deployable := await _deployable()
	var owner := Node2D.new()
	add_child_autofree(owner)
	deployable.configure(EngineerDeployable.Kind.OVERCLOCK_STATION, owner, Vector2.ZERO)
	assert_eq(deployable.station_aura.frame, 0)
	await get_tree().create_timer(EngineerDeployable.STATION_AURA_FRAME_TIME * 1.5).timeout
	assert_eq(deployable.station_aura.frame, 1)
	await get_tree().create_timer(EngineerDeployable.STATION_AURA_FRAME_TIME * 5.0).timeout
	assert_eq(deployable.station_aura.frame, 0)

func test_trap_detonation_removes_trap_but_one_shot_belongs_to_parent() -> void:
	var parent := Node2D.new()
	add_child_autofree(parent)
	var trap := SCENE.instantiate() as EngineerDeployable
	parent.add_child(trap)
	await get_tree().process_frame
	var owner := Node2D.new()
	add_child_autofree(owner)
	trap.configure(EngineerDeployable.Kind.TRAP, owner, Vector2.ZERO)
	trap.global_position = Vector2.ZERO
	trap.influence.monitoring = true
	trap.influence.collision_mask = 4
	var influence_handler := Callable(trap, "_on_influence_body_entered")
	if trap.influence.body_entered.is_connected(influence_handler):
		trap.influence.body_entered.disconnect(influence_handler)
	var enemy := TrapEnemy.new()
	enemy.add_to_group(&"enemies")
	enemy.global_position = Vector2.ZERO
	var enemy_shape := CollisionShape2D.new()
	var enemy_circle := CircleShape2D.new()
	enemy_circle.radius = 4.0
	enemy_shape.shape = enemy_circle
	enemy.add_child(enemy_shape)
	enemy.collision_layer = 4
	parent.add_child(enemy)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_true(trap.influence.get_overlapping_bodies().has(enemy))
	trap._detonate()
	trap._detonate()
	assert_true(trap.is_queued_for_deletion())
	assert_eq(_effect_count(parent), 1)
	assert_eq(enemy.damages, 1)
	await get_tree().process_frame
	await get_tree().create_timer(0.075).timeout
	var effect := _effect_with_frames(parent, 4)
	assert_not_null(effect)
	assert_eq(effect.frame, 1)
	await get_tree().create_timer(0.075).timeout
	assert_eq(_effect_count(parent), 1)
	await get_tree().create_timer(0.025).timeout
	await get_tree().process_frame
	assert_eq(_effect_count(parent), 0)

func test_station_grant_fx_is_first_concession_only_while_refreshing_buff() -> void:
	var deployable := await _deployable()
	var owner := Node2D.new()
	add_child_autofree(owner)
	deployable.configure(EngineerDeployable.Kind.OVERCLOCK_STATION, owner, Vector2.ZERO)
	var recipient := GrantRecipient.new()
	recipient.add_to_group(&"player")
	add_child_autofree(recipient)
	var parent := deployable.get_parent()
	deployable._buff_ally(recipient)
	deployable._buff_ally(recipient)
	assert_eq(_effect_count(parent), 1)
	assert_eq(recipient.grants, 1)
	# Repeated contact refreshes the modifier but does not grant another charge.
	deployable._remove_station_aura(recipient)
	assert_eq(recipient.revokes, 1)
	deployable._buff_ally(recipient)
	assert_eq(recipient.grants, 2)
	assert_eq(_effect_count(parent), 2)

func test_station_nonfatal_hit_and_fatal_death_use_distinct_one_shots() -> void:
	var parent := Node2D.new()
	add_child_autofree(parent)
	var station := SCENE.instantiate() as EngineerDeployable
	parent.add_child(station)
	await get_tree().process_frame
	var owner := Node2D.new()
	add_child_autofree(owner)
	station.configure(EngineerDeployable.Kind.OVERCLOCK_STATION, owner, Vector2.ZERO)
	var partial := DamageInfo.new()
	partial.amount = 100
	station.take_damage(partial)
	assert_eq(_effect_count(parent), 1)
	var hit := _effect_with_frames(parent, 2)
	assert_not_null(hit)
	# Allow a full render tick while still checking before the 100 ms one-shot ends.
	await get_tree().create_timer(EngineerDeployable.STATION_HIT_FRAME_TIME + 0.030).timeout
	assert_eq(hit.frame, 1)
	await get_tree().create_timer(EngineerDeployable.STATION_HIT_FRAME_TIME).timeout
	await get_tree().process_frame
	assert_eq(_effect_count(parent), 0)
	var fatal := DamageInfo.new()
	fatal.amount = 10000
	station.take_damage(fatal)
	assert_true(station.is_queued_for_deletion())
	assert_eq(_effect_count(parent), 1)
	await get_tree().process_frame
	await get_tree().create_timer(EngineerDeployable.STATION_DEATH_FRAME_TIME + 0.005).timeout
	var death := _effect_with_frames(parent, 5)
	assert_not_null(death)
	assert_eq(death.frame, 1)
	# Five 40 ms frames require more than 200 ms total before cleanup.
	await get_tree().create_timer(EngineerDeployable.STATION_DEATH_FRAME_TIME * 4.0).timeout
	await get_tree().process_frame
	assert_eq(_effect_count(parent), 0)

func test_one_shots_self_free_after_all_frames() -> void:
	var parent := Node2D.new()
	add_child_autofree(parent)
	var deployable := SCENE.instantiate() as EngineerDeployable
	parent.add_child(deployable)
	await get_tree().process_frame
	deployable._spawn_one_shot(deployable.STATION_GRANT_FX, 3, 0.040, Vector2.ZERO)
	assert_eq(_effect_count(parent), 1)
	await get_tree().create_timer(0.13).timeout
	await get_tree().process_frame
	assert_eq(_effect_count(parent), 0)
