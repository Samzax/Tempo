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
		assert_eq(ship.blink_trail_damage, 2.0)
		assert_eq(ship.blink_trail_width, 49.28)
		assert_eq(ship.blink_trail_duration, 0.4)
		assert_eq(ship.visual_scale, 0.7)

	var base := load("res://resources/ships/base.tres") as ShipDef
	assert_not_null(base)
	if base != null:
		assert_false(base.blink_trail_enabled)

	var bruta := load("res://resources/ships/bruta.tres") as ShipDef
	assert_not_null(bruta)
	if bruta != null:
		assert_false(bruta.blink_trail_enabled)

func test_ship_visual_scale_defaults_to_one_and_must_be_positive() -> void:
	var ship := ShipDef.new()
	assert_eq(ship.visual_scale, 1.0)
	ship.visual_scale = 0.0
	assert_true(ship.validate_content().has("Escala visual deve ser positiva."))
	ship.visual_scale = -0.1
	assert_true(ship.validate_content().has("Escala visual deve ser positiva."))
