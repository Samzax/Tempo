extends GutTest

func _base_stat_value(ship: ShipDef, stat: StringName) -> float:
	for base_stat in ship.base_stats:
		if base_stat != null and base_stat.stat == stat:
			return base_stat.value
	return -INF

func test_interceptadora_resource_activates_runtime_contract() -> void:
	var ship := load("res://resources/ships/interceptadora.tres") as ShipDef
	assert_not_null(ship)
	if ship != null:
		assert_eq(ship.id, &"nave_interceptadora")
		assert_eq(ship.ability_q, &"interceptadora_blink")
		assert_eq(_base_stat_value(ship, &"max_health"), 2.0)
		assert_eq(_base_stat_value(ship, &"damage"), 0.5)
		assert_true(ship.blink_trail_enabled)
		assert_eq(ship.blink_trail_damage, 0.2)
		assert_eq(ship.blink_trail_width, 1.5)
		assert_eq(ship.blink_trail_duration, 0.4)
		assert_true(ship.detail_lines_enabled)
		assert_eq(ship.detail_lines_visual_scale, 0.45)
		assert_eq(ship.detail_lines_pulse_frequency, 2.0)
		assert_eq(ship.detail_lines_alpha_min, 0.3)
		assert_eq(ship.detail_lines_alpha_max, 0.8)
		assert_eq(ship.detail_lines_width, 1.0)

	var base := load("res://resources/ships/base.tres") as ShipDef
	assert_not_null(base)
	if base != null:
		assert_false(base.blink_trail_enabled)
		assert_false(base.detail_lines_enabled)

	var bruta := load("res://resources/ships/bruta.tres") as ShipDef
	assert_not_null(bruta)
	if bruta != null:
		assert_false(bruta.blink_trail_enabled)
		assert_false(bruta.detail_lines_enabled)

func test_ship_def_detail_lines_visual_scale_defaults_to_one_and_requires_positive_value() -> void:
	var defaults := ShipDef.new()
	assert_eq(defaults.detail_lines_visual_scale, 1.0)
	defaults.detail_lines_enabled = true
	defaults.detail_lines_pulse_frequency = 1.0
	defaults.detail_lines_alpha_min = 0.1
	defaults.detail_lines_alpha_max = 0.9
	defaults.detail_lines_width = 1.0
	defaults.detail_lines_visual_scale = 0.0
	var errors := defaults.validate_content()
	assert_true(errors.any(func(error: String): return error.contains("escala visual entre 0.01 e 1.0")))
	defaults.detail_lines_visual_scale = 0.009
	errors = defaults.validate_content()
	assert_true(errors.any(func(error: String): return error.contains("escala visual entre 0.01 e 1.0")))
	defaults.detail_lines_visual_scale = 1.01
	errors = defaults.validate_content()
	assert_true(errors.any(func(error: String): return error.contains("escala visual entre 0.01 e 1.0")))
