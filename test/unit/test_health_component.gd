extends GutTest

const HEALTH_COMPONENT := preload("res://scripts/components/health_component.gd")
const HEALTH_UNITS := preload("res://scripts/components/health_units.gd")

func _health(maximum_hp: float = 10.0) -> HealthComponent:
	var component := HEALTH_COMPONENT.new() as HealthComponent
	component.max_health = HEALTH_UNITS.from_hp(maximum_hp)
	add_child_autofree(component)
	await get_tree().process_frame
	return component

func _damage(amount_hp: float) -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = HEALTH_UNITS.from_hp(amount_hp)
	return info

func test_quantization_has_one_explicit_scale() -> void:
	assert_eq(HEALTH_UNITS.HP_SCALE, 100)
	assert_eq(HEALTH_UNITS.from_hp(0.334), 33)
	assert_eq(HEALTH_UNITS.from_hp(3.34), 334)
	assert_eq(HEALTH_UNITS.to_hp(334), 3.34)

func test_fractional_damage_and_signal_use_exact_units() -> void:
	var health := await _health(3.34)
	var hit := _damage(0.34)
	watch_signals(health)
	assert_eq(health.apply_damage(hit), 34)
	assert_eq(health.health, 300)
	assert_signal_emitted_with_parameters(health, &"damaged", [hit, 34])

func test_fatal_damage_keeps_damage_info_and_death_signal() -> void:
	var health := await _health(1.0)
	var fatal := _damage(2.0)
	fatal.source = self
	fatal.tags = [&"test", &"fatal"]
	fatal.position = Vector2(12, 34)
	fatal.trigger_depth = 2
	watch_signals(health)
	assert_eq(health.apply_damage(fatal), 100)
	assert_signal_emitted_with_parameters(health, &"damaged", [fatal, 100])
	assert_signal_emitted_with_parameters(health, &"died", [fatal])
	assert_eq(fatal.amount, 200)
	assert_eq(fatal.source, self)
	assert_eq(fatal.tags, [&"test", &"fatal"])
	assert_eq(fatal.position, Vector2(12, 34))
	assert_eq(fatal.trigger_depth, 2)

func test_damage_is_cumulative_without_implicit_iframes() -> void:
	var health := await _health(1.0)
	assert_eq(health.apply_damage(_damage(0.25)), 25)
	assert_eq(health.apply_damage(_damage(0.25)), 25)
	assert_eq(health.health, 50)

func test_heal_and_spend_use_canonical_units() -> void:
	var health := await _health(2.0)
	health.health = 150
	assert_true(health.try_spend_health(25, 100))
	assert_eq(health.health, 125)
	health.heal(50)
	assert_eq(health.health, 175)
	health.heal(1000)
	assert_eq(health.health, 200)

func test_invalid_authored_values_are_rejected_and_large_values_saturate() -> void:
	for value in [0.0, -1.0, NAN, INF]:
		assert_eq(HEALTH_UNITS.from_hp(value), 0)
	assert_eq(HEALTH_UNITS.from_hp(1.0e308), HEALTH_UNITS.MAX_UNITS)
	assert_eq(HEALTH_UNITS.saturating_add(HEALTH_UNITS.MAX_UNITS - 1, 10), HEALTH_UNITS.MAX_UNITS)

func test_damage_clamps_at_zero_without_overflow() -> void:
	var health := await _health(1.0)
	var lethal := DamageInfo.new()
	lethal.amount = HEALTH_UNITS.MAX_UNITS
	assert_eq(health.apply_damage(lethal), 100)
	assert_eq(health.health, 0)
	assert_eq(health.apply_damage(lethal), 0)
