extends GutTest

const HEALTH_COMPONENT := preload("res://scripts/components/health_component.gd")
const HEALTH_UNITS := preload("res://scripts/components/health_units.gd")

class TakeDamageStub extends Node:
	var calls: Array = []
	var result: int = 7

	func take_damage(info: DamageInfo) -> int:
		calls.append(info)
		return result

class HealthOwnerStub extends Node:
	var health: HealthComponent

class ProjectileAreaStub extends Area2D:
	var _source: Node
	var units: int = 0

	func get_damage_units() -> int:
		return units

class PlainAreaStub extends Area2D:
	var _source: Node

class EnemyBodyStub extends CharacterBody2D:
	var hits: int = 0

	func take_damage(info: DamageInfo) -> int:
		hits += 1
		return info.amount

class DamageableAreaStub extends Area2D:
	var hits: int = 0

	func take_damage(info: DamageInfo) -> int:
		hits += 1
		return info.amount

func _health_owner(maximum_hp: float = 5.0) -> HealthOwnerStub:
	var owner := HealthOwnerStub.new()
	var health := HEALTH_COMPONENT.new() as HealthComponent
	health.max_health = HEALTH_UNITS.from_hp(maximum_hp)
	owner.add_child(health)
	owner.health = health
	add_child_autofree(owner)
	await get_tree().process_frame
	return owner

func _circle_shape(radius: float) -> CollisionShape2D:
	var collision := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	collision.shape = circle
	return collision

func _damage(amount_units: int) -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = amount_units
	return info

func test_collision_layers_match_adr_008() -> void:
	assert_eq(CollisionLayers.WORLD, 1)
	assert_eq(CollisionLayers.PLAYER, 2)
	assert_eq(CollisionLayers.ENEMY, 4)
	assert_eq(CollisionLayers.PLAYER_BULLET, 8)
	assert_eq(CollisionLayers.ENEMY_BULLET, 16)
	assert_eq(CollisionLayers.PICKUP, 32)

func test_composite_masks_match_current_authoring() -> void:
	assert_eq(CollisionLayers.ENEMY | CollisionLayers.ENEMY_BULLET, 20)
	assert_eq(CollisionLayers.ENEMY, 4)
	assert_eq(CollisionLayers.PLAYER | CollisionLayers.ENEMY, 6)
	assert_eq(CollisionLayers.WORLD | CollisionLayers.ENEMY, 5)
	assert_eq(CollisionLayers.WORLD | CollisionLayers.PLAYER, 3)

func test_hurtbox_preserves_authored_layer_and_mask() -> void:
	var hurtbox := Hurtbox.new()
	hurtbox.collision_layer = 2
	hurtbox.collision_mask = 4
	add_child_autofree(hurtbox)
	await get_tree().process_frame
	assert_eq(hurtbox.collision_layer, 2)
	assert_eq(hurtbox.collision_mask, 4)

func test_entity_resolves_parent_and_explicit_path_wins() -> void:
	var holder := Node.new()
	add_child_autofree(holder)
	var receiver := Node.new()
	receiver.name = "Receiver"
	holder.add_child(receiver)
	var hurtbox := Hurtbox.new()
	holder.add_child(hurtbox)

	assert_eq(hurtbox.entity_path, NodePath(""))
	assert_eq(hurtbox.get_entity(), holder)
	assert_eq(hurtbox.entity, holder)

	hurtbox.entity_path = hurtbox.get_path_to(receiver)
	assert_eq(hurtbox.get_entity(), receiver)
	assert_eq(hurtbox.entity, receiver)

	hurtbox.entity_path = NodePath("")
	assert_eq(hurtbox.get_entity(), holder)

func test_take_damage_forwards_to_entity_take_damage() -> void:
	var stub := TakeDamageStub.new()
	add_child_autofree(stub)
	var hurtbox := Hurtbox.new()
	stub.add_child(hurtbox)
	var info := _damage(40)

	assert_eq(hurtbox.take_damage(info), 7)
	assert_eq(stub.calls.size(), 1)
	assert_eq(stub.calls[0], info)
	assert_eq(hurtbox.get_entity(), stub)

func test_take_damage_falls_back_to_health_component() -> void:
	var owner := await _health_owner(5.0)
	var hurtbox := Hurtbox.new()
	owner.add_child(hurtbox)
	var info := _damage(125)

	assert_false(owner.has_method(&"take_damage"))
	assert_eq(hurtbox.get_health(), owner.health)
	assert_eq(hurtbox.take_damage(info), 125)
	assert_eq(owner.health.health, HEALTH_UNITS.from_hp(5.0) - 125)

func test_take_damage_with_null_info_or_removed_entity_returns_zero() -> void:
	var holder := Node.new()
	add_child_autofree(holder)
	var receiver := TakeDamageStub.new()
	receiver.name = "Receiver"
	holder.add_child(receiver)
	var hurtbox := Hurtbox.new()
	holder.add_child(hurtbox)
	hurtbox.entity_path = hurtbox.get_path_to(receiver)

	assert_not_null(hurtbox.get_entity())
	assert_eq(hurtbox.take_damage(null), 0)
	assert_eq(receiver.calls.size(), 0)

	receiver.free()
	assert_null(hurtbox.get_entity())
	assert_eq(hurtbox.take_damage(_damage(10)), 0)

func test_configure_sets_layer_and_mask_without_touching_state() -> void:
	var hurtbox := Hurtbox.new()
	add_child_autofree(hurtbox)
	await get_tree().process_frame
	var monitoring_before := hurtbox.monitoring
	var monitorable_before := hurtbox.monitorable
	var shape_children := hurtbox.get_child_count()

	hurtbox.configure(32, 20)
	assert_eq(hurtbox.collision_layer, 32)
	assert_eq(hurtbox.collision_mask, 20)
	assert_eq(hurtbox.monitoring, monitoring_before)
	assert_eq(hurtbox.monitorable, monitorable_before)
	assert_eq(hurtbox.get_child_count(), shape_children)

func test_get_shape_radius_reads_circle_and_defaults() -> void:
	var hurtbox := Hurtbox.new()
	add_child_autofree(hurtbox)
	assert_eq(Hurtbox.DEFAULT_SHAPE_RADIUS, 10.0)
	assert_eq(hurtbox.get_shape_radius(), Hurtbox.DEFAULT_SHAPE_RADIUS)

	var circle_collision := _circle_shape(10.0)
	hurtbox.add_child(circle_collision)
	assert_eq(hurtbox.get_shape_radius(), 10.0)

	circle_collision.shape.radius = 0.5
	assert_eq(hurtbox.get_shape_radius(), 1.0)

	var rectangle_only := Hurtbox.new()
	add_child_autofree(rectangle_only)
	var rectangle := CollisionShape2D.new()
	rectangle.shape = RectangleShape2D.new()
	rectangle_only.add_child(rectangle)
	assert_eq(rectangle_only.get_shape_radius(), Hurtbox.DEFAULT_SHAPE_RADIUS)

func test_build_incoming_area_info_matches_deployable_contract() -> void:
	var source := Node.new()
	add_child_autofree(source)
	var projectile := ProjectileAreaStub.new()
	projectile._source = source
	projectile.units = 42
	add_child_autofree(projectile)
	var hurtbox := Hurtbox.new()
	hurtbox.position = Vector2(7.0, 9.0)
	add_child_autofree(hurtbox)
	await get_tree().process_frame

	var extra: Array[StringName] = [&"enemy_projectile", &"engineer_deployable"]
	var info := hurtbox.build_incoming_area_info(projectile, 5, extra)
	assert_eq(info.amount, 42)
	assert_eq(info.source, source)
	assert_eq(info.position, hurtbox.global_position)
	assert_eq(info.position, Vector2(7.0, 9.0))
	assert_eq(info.tags, extra)
	assert_eq(info.trigger_depth, 0)
	info.tags.append(&"only_here")
	assert_eq(extra.size(), 2)

	var silent := PlainAreaStub.new()
	silent._source = source
	add_child_autofree(silent)
	var fallback := hurtbox.build_incoming_area_info(silent, 5, extra)
	assert_eq(fallback.amount, 5)
	assert_eq(fallback.source, source)
	assert_eq(fallback.trigger_depth, 0)

func test_build_damage_info_defaults() -> void:
	var source := Node.new()
	add_child_autofree(source)
	var hitbox := Hitbox.new()
	source.add_child(hitbox)
	hitbox.position = Vector2(11.0, 13.0)
	var authored: Array[StringName] = [&"bullet", &"pierce"]
	hitbox.tags = authored
	hitbox.amount = 25
	hitbox.chain_depth = 3

	var info := hitbox.build_damage_info()
	assert_eq(info.amount, 25)
	assert_eq(info.tags, authored)
	assert_eq(info.source, source)
	assert_eq(info.position, hitbox.global_position)
	assert_eq(info.position, Vector2(11.0, 13.0))
	assert_eq(info.trigger_depth, 3)
	assert_false(info.is_crit)
	info.tags.append(&"only_here")
	assert_eq(hitbox.tags.size(), 2)

	var explicit := hitbox.build_damage_info(null, Vector2(3.0, 4.0))
	assert_eq(explicit.position, Vector2(3.0, 4.0))

func test_origin_depth_wins_over_chain_depth_and_clamps() -> void:
	var hitbox := Hitbox.new()
	add_child_autofree(hitbox)
	hitbox.chain_depth = 5
	var origin := DamageInfo.new()
	origin.trigger_depth = 1

	assert_eq(hitbox.build_damage_info(origin).trigger_depth, 2)
	assert_eq(hitbox.build_damage_info().trigger_depth, 5)

	hitbox.chain_depth = -3
	assert_eq(hitbox.chain_depth, 0)
	assert_eq(hitbox.build_damage_info().trigger_depth, 0)

func test_deliver_calls_target_and_emits_damage_delivered() -> void:
	var stub := TakeDamageStub.new()
	add_child_autofree(stub)
	var hitbox := Hitbox.new()
	add_child_autofree(hitbox)
	var info := _damage(9)
	watch_signals(hitbox)

	assert_eq(hitbox.deliver(stub, info), 7)
	assert_eq(stub.calls.size(), 1)
	assert_eq(stub.calls[0], info)
	assert_signal_emitted_with_parameters(hitbox, &"damage_delivered", [stub, info, 7])

	var owner := await _health_owner(5.0)
	var health_info := _damage(200)
	var applied := hitbox.deliver(owner, health_info)
	assert_eq(applied, 200)
	assert_eq(owner.health.health, HEALTH_UNITS.from_hp(5.0) - 200)
	assert_signal_emitted_with_parameters(hitbox, &"damage_delivered", [owner, health_info, 200])

	hitbox.amount = 6
	var strike_return := hitbox.strike(stub)
	assert_eq(strike_return, 7)
	assert_eq(stub.calls.size(), 2)
	var strike_info := stub.calls[1] as DamageInfo
	assert_signal_emitted_with_parameters(hitbox, &"damage_delivered", [stub, strike_info, 7])
	assert_eq(strike_info.amount, 6)
	assert_eq(strike_info.source, hitbox.get_source_entity())
	assert_eq(strike_info.trigger_depth, hitbox.chain_depth)

func test_deliver_without_capabilities_returns_zero() -> void:
	var hitbox := Hitbox.new()
	add_child_autofree(hitbox)
	var plain := Node.new()
	add_child_autofree(plain)
	var info := _damage(5)
	watch_signals(hitbox)

	assert_eq(hitbox.deliver(plain, info), 0)
	assert_eq(hitbox.deliver(null, info), 0)
	assert_eq(hitbox.deliver(plain, null), 0)
	assert_signal_not_emitted(hitbox, &"damage_delivered")

func test_strike_overlapping_bodies_filters_by_target_group() -> void:
	var hitbox := Hitbox.new()
	hitbox.collision_layer = CollisionLayers.PLAYER_BULLET
	hitbox.collision_mask = CollisionLayers.ENEMY
	hitbox.amount = 12
	hitbox.add_child(_circle_shape(40.0))
	add_child_autofree(hitbox)

	var grouped := EnemyBodyStub.new()
	grouped.collision_layer = CollisionLayers.ENEMY
	grouped.collision_mask = 0
	grouped.position = Vector2(10.0, 0.0)
	grouped.add_child(_circle_shape(5.0))
	grouped.add_to_group(&"enemies")
	add_child_autofree(grouped)

	var ungrouped := EnemyBodyStub.new()
	ungrouped.collision_layer = CollisionLayers.ENEMY
	ungrouped.collision_mask = 0
	ungrouped.position = Vector2(-10.0, 0.0)
	ungrouped.add_child(_circle_shape(5.0))
	add_child_autofree(ungrouped)

	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(hitbox.get_overlapping_bodies().size(), 2)

	hitbox.target_group = &"enemies"
	var grouped_total := hitbox.strike_overlapping_bodies()
	assert_eq(grouped.hits, 1)
	assert_eq(ungrouped.hits, 0)
	assert_eq(grouped_total, 12)

	hitbox.target_group = &""
	var all_total := hitbox.strike_overlapping_bodies()
	assert_eq(grouped.hits, 2)
	assert_eq(ungrouped.hits, 1)
	assert_eq(all_total, 24)

func test_loose_components_stay_inert_across_frames() -> void:
	var hitbox := Hitbox.new()
	var hurtbox := Hurtbox.new()
	add_child_autofree(hitbox)
	add_child_autofree(hurtbox)
	var authored := {
		"hit_layer": hitbox.collision_layer,
		"hit_mask": hitbox.collision_mask,
		"hurt_layer": hurtbox.collision_layer,
		"hurt_mask": hurtbox.collision_mask,
	}
	watch_signals(hitbox)
	watch_signals(hurtbox)

	await get_tree().physics_frame
	await get_tree().physics_frame

	assert_eq(hitbox.collision_layer, authored["hit_layer"])
	assert_eq(hitbox.collision_mask, authored["hit_mask"])
	assert_eq(hurtbox.collision_layer, authored["hurt_layer"])
	assert_eq(hurtbox.collision_mask, authored["hurt_mask"])
	assert_signal_not_emitted(hitbox, &"damage_delivered")
	assert_signal_not_emitted(hitbox, &"body_entered")
	assert_signal_not_emitted(hurtbox, &"body_entered")

func test_strike_overlapping_areas_filters_by_target_group() -> void:
	var hitbox := Hitbox.new()
	hitbox.collision_layer = CollisionLayers.PLAYER_BULLET
	hitbox.collision_mask = CollisionLayers.ENEMY
	hitbox.amount = 7
	hitbox.add_child(_circle_shape(40.0))
	add_child_autofree(hitbox)

	var grouped := DamageableAreaStub.new()
	grouped.collision_layer = CollisionLayers.ENEMY
	grouped.collision_mask = 0
	grouped.position = Vector2(10.0, 0.0)
	grouped.add_child(_circle_shape(5.0))
	grouped.add_to_group(&"enemies")
	add_child_autofree(grouped)

	var ungrouped := DamageableAreaStub.new()
	ungrouped.collision_layer = CollisionLayers.ENEMY
	ungrouped.collision_mask = 0
	ungrouped.position = Vector2(-10.0, 0.0)
	ungrouped.add_child(_circle_shape(5.0))
	add_child_autofree(ungrouped)

	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(hitbox.get_overlapping_areas().size(), 2)
	watch_signals(hitbox)

	hitbox.target_group = &"enemies"
	var grouped_total := hitbox.strike_overlapping_areas()
	assert_eq(grouped.hits, 1)
	assert_eq(ungrouped.hits, 0)
	assert_eq(grouped_total, 7)
	assert_eq(get_signal_emit_count(hitbox, &"damage_delivered"), 1)

	hitbox.target_group = &""
	var all_total := hitbox.strike_overlapping_areas()
	assert_eq(grouped.hits, 2)
	assert_eq(ungrouped.hits, 1)
	assert_eq(all_total, 14)
	assert_eq(get_signal_emit_count(hitbox, &"damage_delivered"), 3)

func test_source_path_explicit_wins_and_freed_source_yields_null() -> void:
	var host := Node.new()
	add_child_autofree(host)
	var emitter := Node.new()
	emitter.name = "Emitter"
	host.add_child(emitter)
	var hitbox := Hitbox.new()
	hitbox.amount = 3
	host.add_child(hitbox)

	assert_eq(hitbox.get_source_entity(), host)
	assert_eq(hitbox.build_damage_info().source, host)

	hitbox.source_path = hitbox.get_path_to(emitter)
	assert_eq(hitbox.get_source_entity(), emitter)
	assert_eq(hitbox.build_damage_info().source, emitter)

	emitter.free()
	assert_null(hitbox.get_source_entity())
	assert_null(hitbox.build_damage_info().source)

func test_take_damage_without_any_receiver_capability_returns_zero() -> void:
	var holder := Node.new()
	add_child_autofree(holder)
	var hurtbox := Hurtbox.new()
	holder.add_child(hurtbox)
	var info := _damage(9)

	assert_false(holder.has_method(&"take_damage"))
	assert_null(hurtbox.get_health())
	assert_eq(hurtbox.take_damage(info), 0)
