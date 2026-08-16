extends GutTest

const HEALTH_UNITS := preload("res://scripts/components/health_units.gd")

class OwnerStub extends Node:
	var health: HealthComponent


class EnemyStub extends Node2D:
	var received: DamageInfo = null

	func take_damage(info: DamageInfo) -> void:
		received = info


class AmountMutatingEnemyStub extends EnemyStub:
	var action: DamageAction

	func take_damage(info: DamageInfo) -> void:
		super.take_damage(info)
		action.amount = 1.55


class InertEnemyStub extends Node2D:
	pass


func test_health_component_heal_clamps_and_ignores_non_positive_amounts() -> void:
	var health: HealthComponent = autofree(HealthComponent.new()) as HealthComponent
	health.max_health = HEALTH_UNITS.from_hp(3.0)
	health.health = HEALTH_UNITS.from_hp(1.0)

	health.heal(HEALTH_UNITS.from_hp(1.0))
	assert_eq(health.health, HEALTH_UNITS.from_hp(2.0), "Positive healing should be applied.")
	health.heal(HEALTH_UNITS.from_hp(5.0))
	assert_eq(health.health, HEALTH_UNITS.from_hp(3.0), "Healing should not exceed max health.")
	health.heal(0)
	health.heal(-200)
	assert_eq(health.health, HEALTH_UNITS.from_hp(3.0), "Zero and negative healing should be ignored.")


func test_heal_action_heals_owner_and_ignores_missing_health() -> void:
	var owner: OwnerStub = autofree(OwnerStub.new()) as OwnerStub
	owner.health = autofree(HealthComponent.new()) as HealthComponent
	owner.health.max_health = HEALTH_UNITS.from_hp(3.0)
	owner.health.health = HEALTH_UNITS.from_hp(1.0)
	var context: EffectContext = autofree(EffectContext.new()) as EffectContext
	context.owner = owner
	var action: HealAction = autofree(HealAction.new()) as HealAction
	action.amount = 1.0

	action.execute(context)
	assert_eq(owner.health.health, HEALTH_UNITS.from_hp(2.0))
	owner.health = null
	action.execute(context)
	assert_null(owner.health, "An owner with null health should be a no-op.")


func test_heal_action_ignores_null_context_and_null_owner() -> void:
	var sentinel_owner: OwnerStub = autofree(OwnerStub.new()) as OwnerStub
	sentinel_owner.health = autofree(HealthComponent.new()) as HealthComponent
	sentinel_owner.health.max_health = HEALTH_UNITS.from_hp(3.0)
	sentinel_owner.health.health = HEALTH_UNITS.from_hp(1.0)
	var null_owner_context: EffectContext = autofree(EffectContext.new()) as EffectContext
	var action: HealAction = autofree(HealAction.new()) as HealAction
	action.amount = 1.0

	action.execute(null)
	action.execute(null_owner_context)
	assert_eq(sentinel_owner.health.health, HEALTH_UNITS.from_hp(1.0), "Null context and owner must leave valid owner state unchanged.")


func test_damage_action_allows_depth_two_and_blocks_depth_three() -> void:
	var enemy: EnemyStub = add_child_autofree(EnemyStub.new()) as EnemyStub
	enemy.add_to_group(&"enemies")
	var owner: Node2D = add_child_autofree(Node2D.new()) as Node2D
	var context: EffectContext = autofree(EffectContext.new()) as EffectContext
	context.owner = owner
	var action: DamageAction = autofree(DamageAction.new()) as DamageAction

	context.trigger_depth = 2
	action.execute(context)
	assert_not_null(enemy.received)
	assert_eq(enemy.received.trigger_depth, 3)

	enemy.received = null
	context.trigger_depth = 3
	action.execute(context)
	assert_null(enemy.received)


func test_damage_action_uses_payload_center_and_copies_canonical_damage_info() -> void:
	var owner: Node2D = add_child_autofree(Node2D.new()) as Node2D
	owner.global_position = Vector2.ZERO
	var owner_side_enemy: EnemyStub = add_child_autofree(EnemyStub.new()) as EnemyStub
	owner_side_enemy.add_to_group(&"enemies")
	owner_side_enemy.global_position = Vector2.ZERO
	var payload_side_enemy: EnemyStub = add_child_autofree(EnemyStub.new()) as EnemyStub
	payload_side_enemy.add_to_group(&"enemies")
	payload_side_enemy.global_position = Vector2(100.0, 0.0)
	var payload: DamageInfo = autofree(DamageInfo.new()) as DamageInfo
	payload.position = payload_side_enemy.global_position
	var context: EffectContext = autofree(EffectContext.new()) as EffectContext
	context.owner = owner
	context.payload = payload
	context.trigger_depth = 2
	var action: DamageAction = autofree(DamageAction.new()) as DamageAction
	action.amount = 7.0
	action.radius = 10.0
	action.tags = [&"explosion", &"item"]

	action.execute(context)
	assert_null(owner_side_enemy.received, "Payload position must override the owner's position.")
	assert_not_null(payload_side_enemy.received)
	assert_eq(payload_side_enemy.received.amount, HEALTH_UNITS.from_hp(7.0))
	assert_eq(payload_side_enemy.received.source, owner)
	assert_eq(payload_side_enemy.received.trigger_depth, 3)
	assert_eq(payload_side_enemy.received.position, payload_side_enemy.global_position)
	assert_eq(payload_side_enemy.received.tags, [&"explosion", &"item"])
	action.tags.append(&"changed_after_execution")
	assert_false(payload_side_enemy.received.tags.has(&"changed_after_execution"), "Damage tags must be copied, not shared.")


func test_damage_action_uses_owner_center_and_caps_only_damageable_targets() -> void:
	var owner: Node2D = add_child_autofree(Node2D.new()) as Node2D
	owner.global_position = Vector2(10.0, 10.0)
	var inert: InertEnemyStub = add_child_autofree(InertEnemyStub.new()) as InertEnemyStub
	inert.add_to_group(&"enemies")
	inert.global_position = owner.global_position
	var first: EnemyStub = add_child_autofree(EnemyStub.new()) as EnemyStub
	first.add_to_group(&"enemies")
	first.global_position = owner.global_position + Vector2(1.0, 0.0)
	var second: EnemyStub = add_child_autofree(EnemyStub.new()) as EnemyStub
	second.add_to_group(&"enemies")
	second.global_position = owner.global_position + Vector2(-1.0, 0.0)
	var far: EnemyStub = add_child_autofree(EnemyStub.new()) as EnemyStub
	far.add_to_group(&"enemies")
	far.global_position = owner.global_position + Vector2(100.0, 0.0)
	var context: EffectContext = autofree(EffectContext.new()) as EffectContext
	context.owner = owner
	var action: DamageAction = autofree(DamageAction.new()) as DamageAction
	action.radius = 10.0
	action.max_targets = 1

	action.execute(context)
	var hits := int(first.received != null) + int(second.received != null)
	assert_eq(hits, 1, "One damageable target must be hit regardless of group order; inert targets do not consume the cap.")
	assert_null(far.received, "Owner position should be the fallback center when there is no payload.")


func test_damage_action_quantizes_amount_once_before_iterating_targets() -> void:
	var owner: Node2D = add_child_autofree(Node2D.new()) as Node2D
	var action: DamageAction = autofree(DamageAction.new()) as DamageAction
	action.amount = 1.45
	action.radius = 10.0
	var first: AmountMutatingEnemyStub = add_child_autofree(AmountMutatingEnemyStub.new()) as AmountMutatingEnemyStub
	var second: AmountMutatingEnemyStub = add_child_autofree(AmountMutatingEnemyStub.new()) as AmountMutatingEnemyStub
	for enemy in [first, second]:
		enemy.add_to_group(&"enemies")
		enemy.global_position = owner.global_position
		enemy.action = action
	var context: EffectContext = autofree(EffectContext.new()) as EffectContext
	context.owner = owner

	action.execute(context)
	assert_eq(first.received.amount, 145)
	assert_eq(second.received.amount, 145)


func test_damage_action_ignores_null_context_null_owner_and_off_tree_owner() -> void:
	var enemy: EnemyStub = add_child_autofree(EnemyStub.new()) as EnemyStub
	enemy.add_to_group(&"enemies")
	var null_owner_context: EffectContext = autofree(EffectContext.new()) as EffectContext
	var off_tree_owner: Node2D = autofree(Node2D.new()) as Node2D
	var off_tree_context: EffectContext = autofree(EffectContext.new()) as EffectContext
	off_tree_context.owner = off_tree_owner
	var action: DamageAction = autofree(DamageAction.new()) as DamageAction

	action.execute(null)
	action.execute(null_owner_context)
	action.execute(off_tree_context)
	assert_null(enemy.received, "Null and off-tree owners must not damage active enemies.")
