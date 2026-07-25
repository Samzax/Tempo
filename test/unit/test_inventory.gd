extends GutTest

class SpyAction extends ActionDef:
	var called := 0

	func execute(_context):
		called += 1


func before_each() -> void:
	if RunManager.rng == null:
		RunManager.start_run(1)


func test_acquire_applies_modifier_with_instance_source() -> void:
	var stats := StatBlock.new(StatCatalog.get_all())
	var dispatcher := EffectDispatcher.new(autofree(Node.new()), [])
	var inventory := Inventory.new(stats, dispatcher)
	var item := ItemDef.new()
	item.id = &"item_teste"
	item.max_stacks = 3
	var modifier := StatModifierDef.new()
	modifier.stat = &"fire_rate"
	modifier.op = StatDef.Op.ADD_PCT
	modifier.value = 1.0
	item.modifiers = [modifier]
	item.effects = []

	assert_true(inventory.acquire(item))
	assert_eq(stats.get_stat(&"fire_rate"), 12.0)
	var has_instance_source := false
	for active_modifier in stats.get_active_modifiers():
		if active_modifier.source_id == &"item_teste#0":
			has_instance_source = true
	assert_true(has_instance_source)


func test_stacking_and_remove_one() -> void:
	var stats := StatBlock.new(StatCatalog.get_all())
	var dispatcher := EffectDispatcher.new(autofree(Node.new()), [])
	var inventory := Inventory.new(stats, dispatcher)
	var item := ItemDef.new()
	item.id = &"item_teste"
	item.max_stacks = 3
	var modifier := StatModifierDef.new()
	modifier.stat = &"fire_rate"
	modifier.op = StatDef.Op.ADD_PCT
	modifier.value = 1.0
	item.modifiers = [modifier]
	item.effects = []

	assert_true(inventory.acquire(item))
	assert_true(inventory.acquire(item))
	assert_eq(stats.get_stat(&"fire_rate"), 18.0)
	var source_ids: Array[StringName] = []
	for active_modifier in stats.get_active_modifiers():
		source_ids.append(active_modifier.source_id)
	assert_true(source_ids.has(&"item_teste#0"))
	assert_true(source_ids.has(&"item_teste#1"))

	assert_true(inventory.remove_one(&"item_teste"))
	assert_eq(stats.get_stat(&"fire_rate"), 12.0)
	assert_eq(inventory.count(&"item_teste"), 1)


func test_max_stacks_respected() -> void:
	var stats := StatBlock.new(StatCatalog.get_all())
	var dispatcher := EffectDispatcher.new(autofree(Node.new()), [])
	var inventory := Inventory.new(stats, dispatcher)
	var item := ItemDef.new()
	item.id = &"item_teste"
	item.max_stacks = 1
	var modifier := StatModifierDef.new()
	modifier.stat = &"fire_rate"
	modifier.op = StatDef.Op.ADD_PCT
	modifier.value = 1.0
	item.modifiers = [modifier]
	item.effects = []

	assert_true(inventory.acquire(item))
	assert_false(inventory.acquire(item))
	assert_eq(inventory.count(&"item_teste"), 1)
	assert_eq(stats.get_stat(&"fire_rate"), 12.0)


func test_remove_nonexistent() -> void:
	var stats := StatBlock.new(StatCatalog.get_all())
	var dispatcher := EffectDispatcher.new(autofree(Node.new()), [])
	var inventory := Inventory.new(stats, dispatcher)

	assert_false(inventory.remove_one(&"nao_existe"))


func test_effect_links_and_unlinks() -> void:
	var stats := StatBlock.new(StatCatalog.get_all())
	var dispatcher := EffectDispatcher.new(autofree(Node.new()), [])
	var inventory := Inventory.new(stats, dispatcher)
	var spy := SpyAction.new()
	var effect := EffectDef.new()
	effect.event = &"on_kill"
	effect.action = spy
	effect.chance = 1.0
	var item := ItemDef.new()
	item.id = &"item_efeito"
	item.max_stacks = 3
	item.modifiers = []
	item.effects = [effect]

	assert_true(inventory.acquire(item))
	dispatcher.dispatch(&"on_kill", null, 0)
	assert_eq(spy.called, 1)
	assert_true(inventory.remove_one(&"item_efeito"))
	dispatcher.dispatch(&"on_kill", null, 0)
	assert_eq(spy.called, 1)


func test_stacked_effects_independent() -> void:
	var stats := StatBlock.new(StatCatalog.get_all())
	var dispatcher := EffectDispatcher.new(autofree(Node.new()), [])
	var inventory := Inventory.new(stats, dispatcher)
	var spy := SpyAction.new()
	var effect := EffectDef.new()
	effect.event = &"on_kill"
	effect.action = spy
	effect.chance = 1.0
	effect.cooldown = 5.0
	var item := ItemDef.new()
	item.id = &"item_efeito"
	item.max_stacks = 3
	item.modifiers = []
	item.effects = [effect]

	assert_true(inventory.acquire(item))
	assert_true(inventory.acquire(item))
	dispatcher.dispatch(&"on_kill", null, 0)
	assert_eq(spy.called, 2)
	assert_true(inventory.remove_one(&"item_efeito"))
	## Zera a recarga dos dois efeitos antes de verificar a remocao.
	dispatcher.tick(5.0)
	dispatcher.dispatch(&"on_kill", null, 0)
	assert_eq(spy.called, 3)
