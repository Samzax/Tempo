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
