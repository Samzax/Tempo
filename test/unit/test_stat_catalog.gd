extends GutTest

func test_catalog_loads_without_errors() -> void:
	var definitions := StatCatalog.get_all()
	assert_not_null(definitions)
	assert_eq(definitions.size(), 24)
	var ids := {}
	for stat in definitions:
		assert_false(ids.has(stat.id))
		ids[stat.id] = true
	assert_eq(StatCatalog.get_stat(&"max_speed").default_base, 150.0)
	var expected := {
		&"collision_mass": [1.0, 0.01, 100.0],
		&"collision_damage_resistance": [0.0, 0.0, 1.0],
		&"knockback_force": [1.0, 0.0, 100.0],
		&"knockback_resistance": [0.0, 0.0, 1.0],
	}
	for id in expected:
		var stat: StatDef = StatCatalog.get_stat(id)
		assert_not_null(stat)
		if stat == null:
			continue
		assert_eq(stat.id, id)
		assert_eq(stat.default_base, expected[id][0])
		assert_eq(stat.default_min, expected[id][1])
		assert_eq(stat.default_max, expected[id][2])
		assert_eq(stat.allowed_ops, [0, 1, 2, 3])
