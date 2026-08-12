extends GutTest

func _definition(id: StringName, allowed_ops: Array[int]) -> StatDef:
	var definition := StatDef.new()
	definition.id = id
	definition.allowed_ops = allowed_ops
	return definition

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

func test_can_apply_modifier_is_pure_and_does_not_require_source() -> void:
	var stat_block := StatBlock.new([_definition(&"custom", [StatDef.Op.FLAT])])
	var modifier := StatModifierDef.new()
	modifier.stat = &"custom"
	modifier.op = StatDef.Op.FLAT

	assert_true(stat_block.can_apply_modifier(modifier))
	assert_eq(stat_block.get_active_modifiers().size(), 0)
	assert_push_error_count(0)
	stat_block.add_modifier(modifier)
	assert_push_error("Não é possível adicionar um modificador sem origem.")
	assert_eq(stat_block.get_active_modifiers().size(), 0)

func test_can_apply_modifier_rejects_missing_stat_and_disallowed_operation() -> void:
	var stat_block := StatBlock.new([_definition(&"custom", [StatDef.Op.FLAT])])
	var missing_stat := StatModifierDef.new()
	missing_stat.stat = &"missing"
	missing_stat.op = StatDef.Op.FLAT
	var disallowed_op := StatModifierDef.new()
	disallowed_op.stat = &"custom"
	disallowed_op.op = StatDef.Op.MULT

	assert_false(stat_block.can_apply_modifier(null))
	assert_false(stat_block.can_apply_modifier(missing_stat))
	assert_false(stat_block.can_apply_modifier(disallowed_op))
	assert_eq(stat_block.get_active_modifiers().size(), 0)
	assert_push_error_count(0)

func test_add_modifier_accepts_runtime_source_and_changes_value() -> void:
	var stat_block := StatBlock.new([_definition(&"custom", [StatDef.Op.FLAT])])
	var modifier := StatModifierDef.new()
	modifier.stat = &"custom"
	modifier.op = StatDef.Op.FLAT
	modifier.value = 3.0
	modifier.source_id = &"runtime#0"

	assert_true(stat_block.can_apply_modifier(modifier))
	stat_block.add_modifier(modifier)
	assert_eq(stat_block.get_active_modifiers().size(), 1)
	assert_eq(stat_block.get_stat(&"custom"), 3.0)
