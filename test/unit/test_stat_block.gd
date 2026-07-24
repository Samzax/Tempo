extends GutTest

func test_stat_block_initializes_from_catalog() -> void:
	var definitions := StatCatalog.get_all()
	var stat_block := StatBlock.new(definitions)

	for definition: StatDef in definitions:
		assert_eq(stat_block.get_stat(definition.id), definition.default_base)

func test_stat_block_applies_allowed_modifier() -> void:
	var stat_block := StatBlock.new(StatCatalog.get_all())
	var modifier := StatModifierDef.new()
	modifier.stat = &"max_speed"
	modifier.op = StatDef.Op.FLAT
	modifier.value = 25.0
	modifier.source_id = &"test_source"

	stat_block.add_modifier(modifier)
	assert_eq(stat_block.get_stat(&"max_speed"), 175.0)

func test_stat_block_clears_temporary_modifiers() -> void:
	var stat_block := StatBlock.new(StatCatalog.get_all())
	var permanent_modifier := StatModifierDef.new()
	permanent_modifier.stat = &"max_speed"
	permanent_modifier.op = StatDef.Op.FLAT
	permanent_modifier.value = 50.0
	permanent_modifier.duration = -1.0
	permanent_modifier.source_id = &"perm"
	var temporary_modifier := StatModifierDef.new()
	temporary_modifier.stat = &"fire_rate"
	temporary_modifier.op = StatDef.Op.ADD_PCT
	temporary_modifier.value = 1.0
	temporary_modifier.duration = 3.0
	temporary_modifier.source_id = &"temp"

	stat_block.add_modifier(permanent_modifier)
	stat_block.add_modifier(temporary_modifier)
	assert_eq(stat_block.get_stat(&"max_speed"), 200.0)
	assert_eq(stat_block.get_stat(&"fire_rate"), 12.0)

	stat_block.clear_temporary()
	assert_eq(stat_block.get_stat(&"fire_rate"), 6.0)
	assert_eq(stat_block.get_stat(&"max_speed"), 200.0)
