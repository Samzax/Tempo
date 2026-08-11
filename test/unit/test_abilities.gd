extends GutTest

func test_catalog_resolves_overdrive() -> void:
	var ability := AbilityCatalog.get_ability(&"sobrecarga")
	assert_true(ability is OverdriveAbility)
	assert_true(AbilityCatalog.is_valid(&"escudo"))
	assert_false(AbilityCatalog.is_valid(&"nao_existe"))

func test_catalog_resolves_bruta_charge() -> void:
	var ability := AbilityCatalog.get_ability(&"bruta_investida")
	assert_true(ability is BrutaChargeAbility)
	assert_eq(ability.id, &"bruta_investida")
	assert_true(AbilityCatalog.is_valid(&"bruta_investida"))

func test_catalog_resolves_interceptor_blink() -> void:
	var ability := AbilityCatalog.get_ability(&"interceptadora_blink")
	assert_true(ability is InterceptorBlinkAbility)
	assert_eq(ability.id, &"interceptadora_blink")
	assert_true(AbilityCatalog.is_valid(&"interceptadora_blink"))

func test_interceptor_blink_ability_delegates_without_scene_tree() -> void:
	var ability := AbilityCatalog.get_ability(&"interceptadora_blink") as InterceptorBlinkAbility
	var player := BlinkPlayerStub.new()

	assert_true(ability.try_activate(player))
	assert_eq(player.blink_calls, 1)
	player.should_blink = false
	assert_false(ability.try_activate(player))
	assert_eq(player.blink_calls, 2)

func test_interceptor_blink_ability_uses_player_cooldown_duration() -> void:
	var ability := AbilityCatalog.get_ability(&"interceptadora_blink") as InterceptorBlinkAbility
	var player := BlinkPlayerStub.new()

	assert_eq(ability.cooldown, 0.9)
	assert_eq(ability.get_cooldown(player), 0.9)
	player.cooldown_duration = 1.25
	assert_eq(ability.get_cooldown(player), 1.25)

func test_interceptor_blink_and_shift_share_player_blink_lock() -> void:
	var ability := AbilityCatalog.get_ability(&"interceptadora_blink") as InterceptorBlinkAbility
	var player := SharedBlinkPlayerStub.new()

	assert_true(ability.try_activate(player))
	assert_eq(player.blink_calls, 1)
	assert_false(ability.try_activate(player))
	assert_eq(player.blink_calls, 2)
	player.tick_blink_cooldown(0.9)
	assert_true(player.try_blink())
	assert_eq(player.blink_calls, 3)

func test_interceptor_blink_q_ratio_tracks_shift_blink_cooldown() -> void:
	var player := preload("res://scenes/player/player.tscn").instantiate() as Player
	add_child_autofree(player)
	var ship := ShipDef.new()
	ship.id = &"interceptadora_test"
	ship.ability_q = &"interceptadora_blink"
	assert_true(player.configure_ship(ship))

	assert_eq(player.ability_q_cooldown_ratio(), 0.0)
	assert_true(player.try_blink(Vector2.RIGHT))
	assert_gt(player.blink_cooldown_ratio(), 0.0)
	assert_eq(player.ability_q_cooldown_ratio(), player.blink_cooldown_ratio())
	assert_gt(player.ability_q_cooldown_ratio(), 0.0)

func test_non_interceptor_q_ratio_keeps_ability_cooldown_state() -> void:
	var player := preload("res://scenes/player/player.tscn").instantiate() as Player
	add_child_autofree(player)
	player._ability_q = AbilityCatalog.get_ability(&"sobrecarga")
	player._ability_q_cd_duration = 3.0
	player._ability_q_cd = 1.5

	assert_eq(player.ability_q_cooldown_ratio(), 0.5)
	player._blink_cd_duration = 0.9
	player._blink_cd = 0.9
	assert_eq(player.ability_q_cooldown_ratio(), 0.5)

func test_ability_def_get_cooldown_is_contract_for_e_slot() -> void:
	var ability := AbilityDef.new()
	ability.cooldown = 2.75
	var player := Node2D.new()
	add_child_autofree(player)

	assert_eq(ability.get_cooldown(player), 2.75)

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

class BlinkPlayerStub extends Node2D:
	var should_blink := true
	var blink_calls := 0
	var cooldown_duration := 0.9

	func try_blink() -> bool:
		blink_calls += 1
		return should_blink

	func blink_cooldown_duration() -> float:
		return cooldown_duration

class SharedBlinkPlayerStub extends BlinkPlayerStub:
	var blink_lock := 0.0

	func try_blink() -> bool:
		blink_calls += 1
		if blink_lock > 0.0:
			return false
		blink_lock = cooldown_duration
		return true

	func tick_blink_cooldown(delta: float) -> void:
		blink_lock = maxf(0.0, blink_lock - delta)
