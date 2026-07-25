extends GutTest

class OwnerStub extends Node:
	var health: HealthComponent


class EnemyStub extends Node2D:
	var received: DamageInfo = null

	func take_damage(info: DamageInfo) -> void:
		received = info


func test_health_component_heal() -> void:
	var hc := autofree(HealthComponent.new())
	hc.max_health = 3.0
	hc.health = 1.0

	hc.heal(1.0)
	assert_eq(hc.health, 2.0)
	hc.heal(5.0)
	assert_eq(hc.health, 3.0)
	hc.heal(-2.0)
	assert_eq(hc.health, 3.0)


func test_heal_action() -> void:
	var owner := autofree(OwnerStub.new())
	owner.health = autofree(HealthComponent.new())
	owner.health.max_health = 3.0
	owner.health.health = 1.0
	var context := EffectContext.new()
	context.owner = owner
	var action := HealAction.new()
	action.amount = 1.0

	action.execute(context)
	assert_eq(owner.health.health, 2.0)


func test_damage_action_depth_guard() -> void:
	var enemy := add_child_autofree(EnemyStub.new()) as EnemyStub
	enemy.add_to_group(&"enemies")
	enemy.global_position = Vector2(10.0, 10.0)
	var owner := add_child_autofree(Node2D.new()) as Node2D
	owner.global_position = Vector2(10.0, 10.0)
	var context := EffectContext.new()
	context.owner = owner
	context.trigger_depth = 3
	var action := DamageAction.new()

	action.execute(context)
	assert_null(enemy.received)


func test_damage_action_hits_enemies_in_radius() -> void:
	var near_enemy := add_child_autofree(EnemyStub.new()) as EnemyStub
	near_enemy.add_to_group(&"enemies")
	near_enemy.global_position = Vector2(10.0, 10.0)
	var far_enemy := add_child_autofree(EnemyStub.new()) as EnemyStub
	far_enemy.add_to_group(&"enemies")
	far_enemy.global_position = Vector2(1000.0, 1000.0)
	var owner := add_child_autofree(Node2D.new()) as Node2D
	owner.global_position = Vector2(10.0, 10.0)
	var context := EffectContext.new()
	context.owner = owner
	context.trigger_depth = 0
	context.payload = null
	var action := DamageAction.new()
	action.amount = 2.0
	action.radius = 50.0

	action.execute(context)
	assert_not_null(near_enemy.received)
	assert_eq(near_enemy.received.amount, 2.0)
	assert_eq(near_enemy.received.trigger_depth, 1)
	assert_eq(near_enemy.received.source, owner)
	assert_null(far_enemy.received)
