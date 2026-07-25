extends GutTest

class OwnerStub extends Node:
	var _stats: StatBlock


func before_each() -> void:
	if RunManager.rng == null:
		RunManager.start_run(1)


func test_catalog_loads() -> void:
	assert_eq(ItemCatalog.get_all().size(), 13)
	assert_not_null(ItemCatalog.get_item(&"convergencia"))
	assert_true(ItemCatalog.is_valid(&"eco_temporal"))
	assert_false(ItemCatalog.is_valid(&"nao_existe"))


func test_all_items_valid() -> void:
	for item in ItemCatalog.get_all():
		var errors := item.validate_content()
		if not errors.is_empty():
			fail("Item %s invalido: %s" % [item.id, "; ".join(errors)])
		assert_eq(errors.size(), 0)


func test_acquire_modifier_item() -> void:
	var stats := StatBlock.new(StatCatalog.get_all())
	var dispatcher := EffectDispatcher.new(autofree(Node.new()), [])
	var inventory := Inventory.new(stats, dispatcher)

	assert_true(inventory.acquire(ItemCatalog.get_item(&"nucleo_superaquecido")))
	assert_almost_eq(stats.get_stat(&"fire_rate"), 7.8, 0.0001)


func test_acquire_effect_item() -> void:
	var owner := autofree(OwnerStub.new())
	owner._stats = StatBlock.new(StatCatalog.get_all())
	var dispatcher := EffectDispatcher.new(owner, [])
	var inventory := Inventory.new(owner._stats, dispatcher)

	assert_true(inventory.acquire(ItemCatalog.get_item(&"eco_temporal")))
	assert_eq(owner._stats.get_stat(&"fire_rate"), 6.0)

	dispatcher.dispatch(&"on_blink", null, 0)
	assert_eq(owner._stats.get_stat(&"fire_rate"), 9.0)
	owner._stats.tick(2.1)
	assert_eq(owner._stats.get_stat(&"fire_rate"), 6.0)
