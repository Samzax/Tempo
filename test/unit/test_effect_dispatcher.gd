extends GutTest

class SpyAction extends ActionDef:
	var called := false
	var last_context: EffectContext

	func execute(context):
		called = true
		last_context = context


class OwnerStub extends Node:
	var _stats: StatBlock


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
	spy.called = false
	dispatcher.dispatch(&"on_fire", null, 0)
	assert_false(spy.called)
	dispatcher.tick(5.0)
	dispatcher.dispatch(&"on_fire", null, 0)
	assert_true(spy.called)


func test_depth_guard() -> void:
	var spy := SpyAction.new()
	var effect := EffectDef.new()
	effect.event = &"on_kill"
	effect.action = spy
	effect.chance = 1.0
	var dispatcher := EffectDispatcher.new(autofree(Node.new()), [effect])

	dispatcher.dispatch(&"on_kill", null, 4)
	assert_false(spy.called)


func test_modify_stat_action_applies() -> void:
	var owner_stub := autofree(OwnerStub.new())
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
