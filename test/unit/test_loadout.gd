extends GutTest

func test_loadout_sets_ship_base_stat() -> void:
	var ship := ShipDef.new()
	var base_stat := BaseStatValue.new()
	base_stat.stat = &"max_speed"
	base_stat.value = 200.0
	ship.base_stats = [base_stat]
	var stat_block := StatBlock.new(StatCatalog.get_all())

	Loadout.apply(stat_block, ship, null)

	assert_eq(stat_block.get_stat(&"max_speed"), 200.0)

func test_loadout_applies_ship_modifier_with_source_id() -> void:
	var ship := ShipDef.new()
	ship.id = &"nave_teste"
	var modifier := StatModifierDef.new()
	modifier.stat = &"fire_rate"
	modifier.op = StatDef.Op.ADD_PCT
	modifier.value = 0.5
	ship.modifiers = [modifier]
	var stat_block := StatBlock.new(StatCatalog.get_all())

	Loadout.apply(stat_block, ship, null)

	assert_eq(stat_block.get_stat(&"fire_rate"), 9.0)
	var has_ship_source := false
	for active_modifier in stat_block.get_active_modifiers():
		if active_modifier.source_id == &"nave_teste":
			has_ship_source = true
	assert_true(has_ship_source)

func test_loadout_preserves_catalog_defaults_for_empty_providers() -> void:
	var ship := ShipDef.new()
	ship.id = &"nave_vazia"
	var character := CharacterDef.new()
	character.id = &"personagem_vazio"
	var stat_block := StatBlock.new(StatCatalog.get_all())

	Loadout.apply(stat_block, ship, character)

	assert_eq(stat_block.get_stat(&"max_health"), 3.0)
	assert_eq(stat_block.get_stat(&"max_speed"), 150.0)
	assert_eq(stat_block.get_stat(&"fire_rate"), 6.0)
