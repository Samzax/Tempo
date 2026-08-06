extends GutTest

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

class FakeAbilityPlayer extends Node2D:
	var modifier_calls: Array = []
	var invuln_calls: Array[float] = []

	func apply_temporary_modifier(source_id: StringName, stat_id: StringName, op: StatDef.Op, value: float, duration: float) -> void:
		modifier_calls.append([source_id, stat_id, op, value, duration])

	func grant_invuln(duration: float) -> void:
		invuln_calls.append(duration)

func test_roster_exposes_the_three_v1_ids() -> void:
	var ids: Array[StringName] = []
	for character in CharacterDef.get_roster():
		ids.append(character.id)
	assert_eq(ids, [&"hacker", &"guardian", &"chronomancer"])

func test_roster_abilities_are_known() -> void:
	for character in CharacterDef.get_roster():
		assert_true(AbilityCatalog.is_valid(character.ability_e), str(character.id))
		assert_eq(AbilityCatalog.get_ability(character.ability_e).id, character.ability_e)
		assert_eq(character.validate_content(), [], str(character.id))

func test_roster_definitions_use_only_real_stats() -> void:
	var expected := {
		&"hacker": [&"aim_tier"],
		&"guardian": [&"max_health"],
		&"chronomancer": [&"blink_haste"],
	}
	for character in CharacterDef.get_roster():
		var stats: Array[StringName] = []
		for modifier in character.modifiers:
			stats.append(modifier.stat)
		assert_eq(stats, expected[character.id], str(character.id))
		assert_eq(character.get_runtime_modifiers()[0].source_id, character.id)

func test_character_abilities_have_distinct_ids_and_real_behavior() -> void:
	var hacker := AbilityCatalog.get_ability(&"hacker_overdrive")
	var guardian := AbilityCatalog.get_ability(&"guardian_shield")
	var chronomancer := AbilityCatalog.get_ability(&"time_warp")
	assert_ne(hacker, guardian)
	assert_ne(hacker, chronomancer)
	assert_ne(guardian, chronomancer)
	assert_eq(hacker.id, &"hacker_overdrive")
	assert_eq(guardian.id, &"guardian_shield")
	assert_eq(chronomancer.id, &"time_warp")
	assert_eq(GuardianShieldAbility.new().cooldown, 10.0)

	var player := FakeAbilityPlayer.new()
	hacker.activate(player)
	guardian.activate(player)
	chronomancer.activate(player)
	assert_eq(player.invuln_calls, [2.0])
	assert_eq(player.modifier_calls.size(), 3)
	assert_eq(player.modifier_calls[0], [&"hacker_overdrive_runtime", &"fire_rate", StatDef.Op.ADD_PCT, 0.5, 3.0])
	assert_eq(player.modifier_calls[1], [&"time_warp_haste_runtime", &"blink_haste", StatDef.Op.MULT, 1.0, 3.0])
	assert_eq(player.modifier_calls[2], [&"time_warp_invuln_runtime", &"blink_invuln", StatDef.Op.ADD_PCT, 1.0, 3.0])
	player.free()

func test_character_ability_sources_do_not_collide() -> void:
	var sources: Array[StringName] = []
	for character in CharacterDef.get_roster():
		for modifier in character.get_runtime_modifiers():
			sources.append(modifier.source_id)
	sources.append_array([
		&"hacker_overdrive_runtime",
		&"time_warp_haste_runtime",
		&"time_warp_invuln_runtime",
	])

	var source_ids := {}
	for source_id in sources:
		assert_false(source_ids.has(source_id), "source_id duplicado: %s" % source_id)
		source_ids[source_id] = true
	assert_eq(source_ids.keys().size(), sources.size())

func test_invalid_selection_is_normalized_before_run() -> void:
	RunManager.select_character(&"not_a_character")
	assert_eq(RunManager.selected_character_id, &"piloto_base")
	assert_eq(CharacterDef.resolve_id(RunManager.selected_character_id).id, &"piloto_base")
	RunManager.select_character(&"chronomancer")
	assert_eq(RunManager.selected_character_id, &"chronomancer")

func test_unknown_character_uses_the_existing_base_fallback() -> void:
	var fallback := CharacterDef.resolve_id(&"missing")
	assert_eq(fallback.id, &"piloto_base")
	assert_eq(fallback.thrust_color, Color.WHITE)

func test_character_thrust_color_defaults_to_white() -> void:
	assert_eq(CharacterDef.new().thrust_color, Color.WHITE)

func test_player_thrusters_keep_character_colors_isolated_and_reset_to_fallback() -> void:
	var blue_character := CharacterDef.new()
	blue_character.thrust_color = Color.CORNFLOWER_BLUE
	var orange_character := CharacterDef.new()
	orange_character.thrust_color = Color.DARK_ORANGE
	var first := PLAYER_SCENE.instantiate() as Player
	var second := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(first)
	add_child_autofree(second)
	await get_tree().process_frame

	first.character = blue_character
	first._configure_loadout()
	second.character = orange_character
	second._configure_loadout()
	assert_eq(first.thruster.color, Color.CORNFLOWER_BLUE)
	assert_eq(second.thruster.color, Color.DARK_ORANGE)
	assert_ne(first.thruster.color, second.thruster.color)

	assert_true(first.configure_ship(first.ship))
	assert_eq(first.thruster.color, Color.CORNFLOWER_BLUE)
	assert_true(second.configure_selection(second.ship, &"missing"))
	assert_eq(second.character.id, &"piloto_base")
	assert_eq(second.thruster.color, Color.WHITE)
	assert_eq(first.thruster.color, Color.CORNFLOWER_BLUE)
	first.configure_character(&"missing")
	assert_eq(first.character.id, &"piloto_base")
	assert_eq(first.thruster.color, Color.WHITE)
