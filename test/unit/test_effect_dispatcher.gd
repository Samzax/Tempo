extends GutTest

class SpyAction extends ActionDef:
	var called := false
	var call_count := 0
	var last_context: EffectContext

	func execute(context: EffectContext) -> void:
		called = true
		call_count += 1
		last_context = context


class OwnerStub extends Node:
	var _stats: StatBlock


class HealthOwnerStub extends Node:
	var health: HealthComponent


class SelfRemovingAction extends ActionDef:
	var dispatcher: EffectDispatcher
	var effect: EffectDef
	var call_count := 0

	func execute(_context: EffectContext) -> void:
		call_count += 1
		dispatcher.remove_effects([effect])


func before_each() -> void:
	if RunManager.rng == null:
		RunManager.start_run(1)


func test_dispatch_calls_action_on_matching_event() -> void:
	var matching_spy := SpyAction.new()
	var matching_effect := EffectDef.new()
	matching_effect.event = &"on_kill"
	matching_effect.action = matching_spy
	matching_effect.chance = 1.0
	var dispatcher := EffectDispatcher.new(autofree(Node.new()), [matching_effect])

	dispatcher.dispatch(&"on_kill", null, 0)
	assert_true(matching_spy.called)

	var other_spy := SpyAction.new()
	var other_effect := EffectDef.new()
	other_effect.event = &"on_kill"
	other_effect.action = other_spy
	other_effect.chance = 1.0
	var other_dispatcher := EffectDispatcher.new(autofree(Node.new()), [other_effect])
	other_dispatcher.dispatch(&"on_fire", null, 0)
	assert_false(other_spy.called)


func test_condition_filters() -> void:
	var fire_spy := SpyAction.new()
	var effect := EffectDef.new()
	effect.event = &"on_hit"
	var condition := HasTagCondition.new()
	condition.tag = &"fire"
	effect.condition = condition
	effect.action = fire_spy
	effect.chance = 1.0
	var dispatcher := EffectDispatcher.new(autofree(Node.new()), [effect])
	var fire_damage := DamageInfo.new()
	fire_damage.tags = [&"fire"]
	var ice_damage := DamageInfo.new()
	ice_damage.tags = [&"ice"]

	dispatcher.dispatch(&"on_hit", fire_damage, 0)
	assert_true(fire_spy.called)
	fire_spy.called = false
	dispatcher.dispatch(&"on_hit", ice_damage, 0)
	assert_false(fire_spy.called)


func test_dispatch_provides_complete_context() -> void:
	var owner: OwnerStub = autofree(OwnerStub.new()) as OwnerStub
	var first_payload := DamageInfo.new()
	var second_payload := DamageInfo.new()
	var spy := SpyAction.new()
	var effect := EffectDef.new()
	effect.event = &"on_hit"
	effect.action = spy
	effect.chance = 1.0
	var dispatcher := EffectDispatcher.new(owner, [effect])

	dispatcher.dispatch(&"on_hit", first_payload, 2)

	assert_not_null(spy.last_context)
	assert_eq(spy.last_context.owner, owner)
	assert_eq(spy.last_context.event, &"on_hit")
	assert_eq(spy.last_context.payload, first_payload)
	assert_eq(spy.last_context.rng, RunManager.rng)
	assert_eq(spy.last_context.trigger_depth, 2)
	var first_context := spy.last_context

	effect.event = &"on_kill"
	dispatcher.dispatch(&"on_kill", second_payload, 1)

	assert_eq(spy.call_count, 2)
	assert_ne(spy.last_context, first_context)
	assert_eq(spy.last_context.owner, owner)
	assert_eq(spy.last_context.event, &"on_kill")
	assert_eq(spy.last_context.payload, second_payload)
	assert_eq(spy.last_context.rng, RunManager.rng)
	assert_eq(spy.last_context.trigger_depth, 1)


func test_chance_zero_never_one_always() -> void:
	var never_spy := SpyAction.new()
	var never_effect := EffectDef.new()
	never_effect.event = &"on_fire"
	never_effect.action = never_spy
	never_effect.chance = 0.0
	var never_dispatcher := EffectDispatcher.new(autofree(Node.new()), [never_effect])
	for _i in range(5):
		never_dispatcher.dispatch(&"on_fire", null, 0)
	assert_false(never_spy.called)

	var always_spy := SpyAction.new()
	var always_effect := EffectDef.new()
	always_effect.event = &"on_fire"
	always_effect.action = always_spy
	always_effect.chance = 1.0
	var always_dispatcher := EffectDispatcher.new(autofree(Node.new()), [always_effect])
	always_dispatcher.dispatch(&"on_fire", null, 0)
	assert_true(always_spy.called)


func test_cooldown_blocks_and_recovers() -> void:
	var spy := SpyAction.new()
	var effect := EffectDef.new()
	effect.event = &"on_fire"
	effect.action = spy
	effect.chance = 1.0
	effect.cooldown = 5.0
	var dispatcher := EffectDispatcher.new(autofree(Node.new()), [effect])

	dispatcher.dispatch(&"on_fire", null, 0)
	assert_true(spy.called)
	assert_eq(spy.call_count, 1)
	spy.called = false
	dispatcher.dispatch(&"on_fire", null, 0)
	assert_false(spy.called)
	assert_eq(spy.call_count, 1)
	dispatcher.tick(2.0)
	dispatcher.dispatch(&"on_fire", null, 0)
	assert_false(spy.called)
	assert_eq(spy.call_count, 1)
	dispatcher.tick(3.0)
	spy.called = false
	dispatcher.dispatch(&"on_fire", null, 0)
	assert_true(spy.called)
	assert_eq(spy.call_count, 2)


func test_depth_guard() -> void:
	var spy := SpyAction.new()
	var effect := EffectDef.new()
	effect.event = &"on_kill"
	effect.action = spy
	effect.chance = 1.0
	var dispatcher := EffectDispatcher.new(autofree(Node.new()), [effect])

	dispatcher.dispatch(&"on_kill", null, 3)
	assert_true(spy.called)
	assert_eq(spy.call_count, 1)
	spy.called = false
	dispatcher.dispatch(&"on_kill", null, 4)
	assert_false(spy.called)
	assert_eq(spy.call_count, 1)


func test_add_and_remove_effects_by_identity() -> void:
	var spy_a := SpyAction.new()
	var effect_a := EffectDef.new()
	effect_a.event = &"on_fire"
	effect_a.action = spy_a
	effect_a.chance = 1.0
	effect_a.cooldown = 5.0
	var spy_b := SpyAction.new()
	var effect_b := EffectDef.new()
	effect_b.event = &"on_fire"
	effect_b.action = spy_b
	effect_b.chance = 1.0
	var effects: Array[EffectDef] = []
	var dispatcher := EffectDispatcher.new(autofree(Node.new()), effects)

	dispatcher.dispatch(&"on_fire", null, 0)
	assert_eq(spy_a.call_count, 0)
	assert_eq(spy_b.call_count, 0)
	dispatcher.add_effects([effect_a, effect_b])
	dispatcher.dispatch(&"on_fire", null, 0)
	assert_eq(spy_a.call_count, 1)
	assert_eq(spy_b.call_count, 1)
	assert_true(dispatcher._cooldowns.has(effect_a))
	dispatcher.remove_effects([effect_a])
	assert_false(effect_a in dispatcher._effects)
	assert_false(dispatcher._cooldowns.has(effect_a))
	assert_true(effect_b in dispatcher._effects)
	assert_false(dispatcher._cooldowns.has(effect_b))
	dispatcher.dispatch(&"on_fire", null, 0)
	assert_eq(spy_a.call_count, 1)
	assert_eq(spy_b.call_count, 2)


func test_self_removal_during_execute_leaves_no_cooldown() -> void:
	var action := SelfRemovingAction.new()
	var effect := EffectDef.new()
	effect.event = &"on_fire"
	effect.action = action
	effect.chance = 1.0
	effect.cooldown = 5.0
	var dispatcher := EffectDispatcher.new(autofree(Node.new()), [effect])
	action.dispatcher = dispatcher
	action.effect = effect

	dispatcher.dispatch(&"on_fire", null, 0)
	assert_eq(action.call_count, 1)
	assert_false(effect in dispatcher._effects)
	assert_false(dispatcher._cooldowns.has(effect))
	dispatcher.dispatch(&"on_fire", null, 0)
	assert_eq(action.call_count, 1)
	action.dispatcher = null
	action.effect = null
	effect.action = null


func test_health_below_condition() -> void:
	var owner: HealthOwnerStub = autofree(HealthOwnerStub.new()) as HealthOwnerStub
	var health := HealthComponent.new()
	health.max_health = 10000
	health.health = 4900
	owner.health = health
	owner.add_child(health)
	var context := EffectContext.new()
	context.owner = owner
	var condition := HealthBelowCondition.new()
	condition.fraction = 0.5

	assert_true(condition.check(context))
	health.health = 5000
	assert_false(condition.check(context))
	owner.health = null
	assert_false(condition.check(context))


func test_modify_stat_action_applies() -> void:
	var owner_stub: OwnerStub = autofree(OwnerStub.new()) as OwnerStub
	owner_stub._stats = StatBlock.new(StatCatalog.get_all())
	var context := EffectContext.new()
	context.owner = owner_stub
	var action := ModifyStatAction.new()
	action.stat = &"fire_rate"
	action.op = StatDef.Op.ADD_PCT
	action.value = 1.0
	action.duration = 3.0
	action.source_id = &"teste"

	action.execute(context)
	assert_eq(owner_stub._stats.get_stat(&"fire_rate"), 12.0)
	owner_stub._stats.tick(3.1)
	assert_eq(owner_stub._stats.get_stat(&"fire_rate"), 6.0)


func test_dispatcher_isolation() -> void:
	var first_spy := SpyAction.new()
	var first_effect := EffectDef.new()
	first_effect.event = &"on_fire"
	first_effect.action = first_spy
	first_effect.chance = 1.0
	var first_dispatcher := EffectDispatcher.new(autofree(Node.new()), [first_effect])

	var second_spy := SpyAction.new()
	var second_effect := EffectDef.new()
	second_effect.event = &"on_fire"
	second_effect.action = second_spy
	second_effect.chance = 1.0
	var second_dispatcher := EffectDispatcher.new(autofree(Node.new()), [second_effect])

	first_dispatcher.dispatch(&"on_fire", null, 0)
	assert_true(first_spy.called)
	assert_false(second_spy.called)
