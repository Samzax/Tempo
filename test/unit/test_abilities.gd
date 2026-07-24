extends GutTest

func test_catalog_resolves_overdrive() -> void:
	var ability := AbilityCatalog.get_ability(&"sobrecarga")
	assert_true(ability is OverdriveAbility)
	assert_true(AbilityCatalog.is_valid(&"escudo"))
	assert_false(AbilityCatalog.is_valid(&"nao_existe"))

func test_overdrive_modifier() -> void:
	var modifier := OverdriveAbility.new().make_modifier()
	assert_eq(modifier.stat, &"fire_rate")
	assert_eq(modifier.op, StatDef.Op.ADD_PCT)
	assert_eq(modifier.value, 1.0)
	assert_eq(modifier.duration, 3.0)
	assert_eq(modifier.source_id, &"sobrecarga")

func test_overdrive_effect_and_expiry() -> void:
	var stat_block := StatBlock.new(StatCatalog.get_all())
	stat_block.add_modifier(OverdriveAbility.new().make_modifier())
	assert_eq(stat_block.get_stat(&"fire_rate"), 12.0)
	stat_block.tick(3.1)
	assert_eq(stat_block.get_stat(&"fire_rate"), 6.0)

func test_ship_validates_unknown_ability() -> void:
	var ship := ShipDef.new()
	ship.id = &"x"
	ship.ability_q = &"nao_existe"
	var errors := ship.validate_content()
	assert_string_contains("\n".join(errors), "Habilidade da nave desconhecida")
