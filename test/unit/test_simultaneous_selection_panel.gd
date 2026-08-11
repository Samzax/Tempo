extends GutTest

const PANEL_SCENE := preload("res://scenes/ui/simultaneous_selection_panel.tscn")

var panel: SimultaneousSelectionPanel
var _pressed_mouse_buttons: Array[int] = []
var _pressed_keys: Array[Key] = []
var _pressed_joypad_buttons: Array[int] = []
var _selection_changed_count := 0
var _continue_requested_count := 0

func before_each() -> void:
	panel = PANEL_SCENE.instantiate() as SimultaneousSelectionPanel
	add_child_autofree(panel)
	await get_tree().process_frame
	await get_tree().process_frame

func after_each() -> void:
	_send_mouse_button(MOUSE_BUTTON_LEFT, false, Vector2.ZERO)
	for key in (_pressed_keys + [KEY_ENTER]).duplicate():
		_send_key(key, false)
	for button in (_pressed_joypad_buttons + [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN,
		JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_A]).duplicate():
		_send_joypad_button(button, false)
	await get_tree().process_frame
	_pressed_mouse_buttons.clear()
	_pressed_keys.clear()
	_pressed_joypad_buttons.clear()

func test_scene_has_valid_initial_pair_and_six_four_metric_layout() -> void:
	assert_ne(panel.selected_ship_id(), &"")
	assert_ne(panel.selected_character_id(), &"")
	assert_eq(panel.get_node("StatsPanel/Stats").get_child_count(), 6)
	for row in panel.get_node("StatsPanel/Stats").get_children():
		assert_true(row is VBoxContainer)
		assert_true(row.get_child(0) is Label)
		var segments := row.get_child(1) as HBoxContainer
		assert_eq(segments.get_child_count(), 4)
		assert_eq(segments.get_theme_constant("separation"), 4)
		for segment in segments.get_children():
			assert_eq((segment as ColorRect).custom_minimum_size, Vector2(14, 8))
			assert_true((segment as ColorRect).color in [Color("69f6d9"), Color("203044")])

func test_stats_rows_and_segments_are_contained_in_480x270_viewport() -> void:
	get_viewport().size = Vector2i(480, 270)
	await get_tree().process_frame
	await get_tree().process_frame
	var root_rect := Rect2(panel.global_position, panel.size)
	var stats_panel := panel.get_node("StatsPanel") as Control
	var stats := panel.get_node("StatsPanel/Stats") as Control
	var stats_panel_rect := Rect2(stats_panel.global_position, stats_panel.size)
	var stats_rect := Rect2(stats.global_position, stats.size)
	var viewport_rect := Rect2(Vector2.ZERO, Vector2(480, 270))
	assert_true(viewport_rect.encloses(root_rect))
	assert_true(viewport_rect.encloses(stats_panel_rect))
	assert_true(stats_panel_rect.encloses(stats_rect))
	assert_lte(stats_panel.size.x, 72.0)
	assert_lte(stats_panel.size.y, 142.0)
	assert_gte(stats_panel.size.x, 68.0)
	assert_gte(stats_panel.size.y, 135.0)
	assert_eq(stats.get_child_count(), panel.STAT_IDS.size())
	for row_node in stats.get_children():
		var row := row_node as Control
		assert_true(stats_rect.encloses(Rect2(row.global_position, row.size)))
		assert_true(row.get_child(0) is Label)
		var segments := row.get_child(1) as HBoxContainer
		assert_true(stats_rect.encloses(Rect2(segments.global_position, segments.size)))
		for segment_node in segments.get_children():
			var segment := segment_node as Control
			assert_true(stats_rect.encloses(Rect2(segment.global_position, segment.size)))

func test_explicit_zero_base_value_is_present_and_scores_at_least_one() -> void:
	var ship := ShipDef.new()
	ship.id = &"fixture_zero_base"
	var authored := BaseStatValue.new()
	authored.stat = &"max_health"
	authored.value = 0.0
	ship.base_stats = [authored]
	var zero_modifier := StatModifierDef.new()
	zero_modifier.stat = &"max_speed"
	zero_modifier.op = StatDef.Op.FLAT
	zero_modifier.value = 0.0
	zero_modifier.source_id = ship.id
	ship.modifiers = [zero_modifier]
	var character := CharacterDef.new()
	character.id = &"fixture_character"
	panel._refresh_stats(ship, character)
	await get_tree().process_frame
	var stats := StatBlock.new(StatCatalog.get_all())
	Loadout.apply(stats, ship, character)
	var active_modifiers := stats.get_active_modifiers()
	assert_eq(active_modifiers.size(), 1)
	assert_eq(active_modifiers[0].stat, zero_modifier.stat)
	assert_eq(active_modifiers[0].op, zero_modifier.op)
	assert_eq(active_modifiers[0].value, zero_modifier.value)
	assert_eq(active_modifiers[0].source_id, zero_modifier.source_id)
	assert_true(panel._has_stat_presence(ship, active_modifiers, &"max_health"))
	assert_true(panel._has_stat_presence(ship, active_modifiers, &"max_speed"))
	assert_gte(_score_for_stat(&"max_health"), 1)
	assert_gte(_score_for_stat(&"max_speed"), 1)

func test_all_modifier_operations_mark_presence_and_loadout_resolves_coherently() -> void:
	var ship := ShipDef.new()
	ship.id = &"fixture_operations"
	var operations := [StatDef.Op.FLAT, StatDef.Op.ADD_PCT, StatDef.Op.MULT, StatDef.Op.OVERRIDE]
	var stat_ids: Array[StringName] = [&"max_health", &"max_speed", &"acceleration", &"fire_rate"]
	for index in operations.size():
		var modifier := StatModifierDef.new()
		modifier.stat = stat_ids[index]
		modifier.op = operations[index]
		modifier.value = 1.0
		modifier.source_id = ship.id
		modifier.priority = 2
		ship.modifiers.append(modifier)
	var character := CharacterDef.new()
	character.id = &"fixture_operations_character"
	var stats := StatBlock.new(StatCatalog.get_all())
	Loadout.apply(stats, ship, character)
	for index in operations.size():
		assert_true(_expected_presence(ship, character, stat_ids[index]))
		assert_gt(stats.get_stat(stat_ids[index]), 0.0)
		assert_eq(stats.get_active_modifiers()[index].source_id, ship.id)

func test_all_fifteen_combinations_have_four_segment_scores_and_explicit_presence() -> void:
	var ranges := _expected_stat_ranges()
	for ship in panel._ships:
		for character in panel._roster:
			assert_true(panel.set_selected_ids(ship.id, character.id))
			await get_tree().process_frame
			var stats := StatBlock.new(StatCatalog.get_all())
			Loadout.apply(stats, ship, character)
			for stat_index in panel.STAT_IDS.size():
				var stat_id: StringName = panel.STAT_IDS[stat_index]
				var score := _filled_segments_by_stat()[stat_index]
				var present := _expected_presence(ship, character, stat_id)
				var value := stats.get_stat(stat_id)
				var expected := _expected_score(value, present, ranges[stat_id])
				assert_eq(score, expected)

func test_fire_rate_presence_contract_for_bruta_and_rastreadora() -> void:
	for character_id in [&"hacker", &"guardian", &"chronomancer"]:
		assert_true(panel.set_selected_ids(&"nave_bruta", character_id))
		await get_tree().process_frame
		assert_eq(_score_for_stat(&"fire_rate"), 0)
		assert_true(panel.set_selected_ids(&"nave_rastreadora", character_id))
		await get_tree().process_frame
		assert_eq(_score_for_stat(&"fire_rate"), 1)

func test_hacker_only_adds_aim_presence_to_shells_without_authorship() -> void:
	for ship in panel._ships:
		var ship_authored := _expected_presence(ship, null, &"aim_tier")
		assert_true(panel.set_selected_ids(ship.id, &"hacker"))
		await get_tree().process_frame
		assert_true(_expected_presence(ship, panel._roster[0], &"aim_tier"))
		assert_eq(_score_for_stat(&"aim_tier") > 0, true)
		for character_id in [&"guardian", &"chronomancer"]:
			var character := CharacterDef.resolve_id(character_id)
			assert_true(panel.set_selected_ids(ship.id, character_id))
			await get_tree().process_frame
			assert_eq(_expected_presence(ship, character, &"aim_tier"), ship_authored)
			assert_eq(_score_for_stat(&"aim_tier") > 0, ship_authored)

func test_stat_score_contract_has_zero_absence_equal_range_and_four_buckets() -> void:
	# The helper is used here because no catalog pair can manufacture a degenerate range.
	panel._ranges[&"max_health"] = {"min": 10.0, "max": 10.0}
	assert_eq(panel._stat_score(&"max_health", 10.0, true), 1)
	assert_eq(panel._stat_score(&"max_health", 10.0, false), 0)
	panel._ranges[&"max_health"] = {"min": 10.0, "max": 20.0}
	assert_eq(panel._stat_score(&"max_health", 10.0, true), 1)
	assert_eq(panel._stat_score(&"max_health", 20.0, true), 4)
	assert_eq(panel._stat_score(&"max_health", 12.0, true), 2)
	assert_eq(panel._stat_score(&"max_health", 15.0, true), 3)
	assert_eq(panel._stat_score(&"max_health", 18.0, true), 3)
	assert_eq(panel._stat_score(&"max_health", 19.0, true), 4)
	assert_eq(panel._stat_score(&"max_health", 20.0, false), 0)

func test_ranges_cover_fifteen_resolved_pairs_and_keep_baseline() -> void:
	var expected: Dictionary = {}
	for stat_id in panel.STAT_IDS:
		expected[stat_id] = {"min": INF, "max": -INF}
	for ship in panel._ships:
		for character in panel._roster:
			var stats := StatBlock.new(StatCatalog.get_all())
			Loadout.apply(stats, ship, character)
			for stat_id in panel.STAT_IDS:
				expected[stat_id]["min"] = minf(expected[stat_id]["min"], stats.get_stat(stat_id))
				expected[stat_id]["max"] = maxf(expected[stat_id]["max"], stats.get_stat(stat_id))
	for stat_id in panel.STAT_IDS:
		assert_eq(panel._ranges[stat_id], expected[stat_id])
		assert_ne(panel._ranges[stat_id]["min"], INF)
		assert_ne(panel._ranges[stat_id]["max"], -INF)
		assert_lte(panel._ranges[stat_id]["min"], StatCatalog.get_stat(stat_id).default_base)
		assert_gte(panel._ranges[stat_id]["max"], StatCatalog.get_stat(stat_id).default_base)

	var isolated_ship := ShipDef.new()
	isolated_ship.id = &"fixture_range_baseline_ship"
	var authored_max_health := BaseStatValue.new()
	authored_max_health.stat = &"max_health"
	authored_max_health.value = StatCatalog.get_stat(&"max_health").default_base + 100.0
	isolated_ship.base_stats = [authored_max_health]
	var isolated_character := CharacterDef.new()
	isolated_character.id = &"fixture_range_baseline_character"
	var isolated_ships: Array[ShipDef] = [isolated_ship]
	var isolated_roster: Array[CharacterDef] = [isolated_character]
	panel._ships = isolated_ships
	panel._roster = isolated_roster
	panel._rebuild_ranges()
	var max_health_range: Dictionary = panel._ranges[&"max_health"]
	var default_max_health := StatCatalog.get_stat(&"max_health").default_base
	assert_eq(max_health_range["min"], default_max_health)
	assert_eq(max_health_range["max"], authored_max_health.value)

func test_character_carousel_wraps_both_directions_and_only_changes_on_step() -> void:
	watch_signals(panel)
	var initial := panel.selected_character_id()
	panel._step_character(-1)
	assert_ne(panel.selected_character_id(), initial)
	assert_signal_emit_count(panel, &"selection_changed", 1)
	panel._step_character(1)
	assert_eq(panel.selected_character_id(), initial)
	assert_signal_emit_count(panel, &"selection_changed", 2)

func test_character_navigation_labels_use_unicode_arrows_and_current_names() -> void:
	var previous := panel.get_node("CharacterCarousel/Previous") as Label
	var next := panel.get_node("CharacterCarousel/Next") as Label
	var roster := panel._roster

	for _i in 2:
		var index := panel._character_index
		var expected_previous := panel._display_name(roster[posmod(index - 1, roster.size())])
		var expected_next := panel._display_name(roster[posmod(index + 1, roster.size())])
		assert_true(previous.text.contains("▲"))
		assert_true(next.text.contains("▼"))
		assert_true(previous.text.contains(expected_previous))
		assert_true(next.text.contains(expected_next))
		assert_false(previous.text.contains("â"))
		assert_false(next.text.contains("â"))
		panel._step_character(1)

func test_ship_carousel_wraps_both_directions() -> void:
	var initial := panel.selected_ship_id()
	panel._step_ship(-1)
	assert_ne(panel.selected_ship_id(), initial)
	panel._step_ship(1)
	assert_eq(panel.selected_ship_id(), initial)

func test_ship_carousel_contains_exactly_the_five_approved_ids() -> void:
	var ids: Array[StringName] = []
	for ship in panel._ships:
		ids.append(ship.id)
	assert_eq(ids, [
		&"nave_interceptadora", &"nave_engenheira", &"nave_rastreadora",
		&"nave_bruta", &"nave_interestelar",
	])
	assert_eq(ids.size(), 5)
	assert_false(ids.has(&"nave_base"))

func test_rastreadora_rotation_is_consumed_as_radians_without_conversion() -> void:
	assert_true(panel.set_selected_ship_id(&"nave_rastreadora"))
	var ship := ShipCatalog.get_ship(&"nave_rastreadora")
	assert_true(panel.set_selected_ship_id(ship.id))
	var preview := panel.get_node("ShipCarousel/PreviewClip/ShipPreview") as TextureRect
	var fx := panel.get_node("ShipCarousel/PreviewClip/ShipEnergyFx") as SelectionShipEnergyFx
	assert_almost_eq(ship.visual_rotation_offset, -PI / 2.0, 0.00001)
	assert_almost_eq(preview.rotation, -PI / 2.0, 0.00001)
	assert_almost_eq(fx.ship_rotation, -PI / 2.0, 0.00001)

func test_preview_uses_real_texture_region_for_rastreadora_and_interestelar() -> void:
	for ship_id in [&"nave_rastreadora", &"nave_interestelar"]:
		assert_true(panel.set_selected_ship_id(ship_id))
		var ship := ShipCatalog.get_ship(ship_id)
		var atlas := (panel.get_node("ShipCarousel/PreviewClip/ShipPreview") as TextureRect).texture as AtlasTexture
		assert_eq(atlas.atlas, ship.hull_texture)
		assert_eq(atlas.region, panel._preview_region(ship))
		assert_gt((panel.get_node("ShipCarousel/PreviewClip/ShipPreview") as TextureRect).size.x, 0.0)

func test_bruta_resolves_frame_zero_inside_texture_and_preview_is_visible() -> void:
	var ship := ShipCatalog.get_ship(&"nave_bruta")
	var region := panel._preview_region(ship)
	assert_eq(region, Rect2(0, 0, 32, 32))
	assert_true(Rect2(Vector2.ZERO, ship.hull_texture.get_size()).encloses(region))
	assert_not_null((panel.get_node("ShipCarousel/PreviewClip/ShipPreview") as TextureRect).texture)
	assert_true((panel.get_node("ShipCarousel/PreviewClip/ShipPreview") as TextureRect).is_visible_in_tree())

func test_playable_regions_stay_inside_real_texture_and_interestelar_custom_region_is_preserved() -> void:
	for ship in panel._ships:
		var texture_bounds := Rect2(Vector2.ZERO, ship.hull_texture.get_size())
		var region := panel._preview_region(ship)
		assert_true(texture_bounds.encloses(region))
	var interestelar := ShipCatalog.get_ship(&"nave_interestelar")
	assert_false(interestelar.custom_frame_regions.is_empty())
	assert_eq(panel._preview_region(interestelar), interestelar.custom_frame_regions[2])

func test_alpha_bounds_are_non_empty_and_cached_without_changing_result() -> void:
	for ship_id in [&"nave_bruta", &"nave_rastreadora", &"nave_interestelar"]:
		var ship := ShipCatalog.get_ship(ship_id)
		var region := panel._preview_region(ship)
		var first := panel._visible_region(ship.hull_texture, region)
		var cache_size := panel._alpha_bounds_cache.size()
		var second := panel._visible_region(ship.hull_texture, region)
		assert_gt(first.size.x, 0.0)
		assert_gt(first.size.y, 0.0)
		assert_true(Rect2(Vector2.ZERO, ship.hull_texture.get_size()).encloses(first))
		assert_eq(second, first)
		assert_eq(panel._alpha_bounds_cache.size(), cache_size)

func test_preview_transform_does_not_depend_on_visual_scale() -> void:
	var original := ShipCatalog.get_ship(&"nave_rastreadora")
	var altered := original.duplicate() as ShipDef
	altered.visual_scale = original.visual_scale * 7.0
	var first := TextureRect.new()
	var second := TextureRect.new()
	add_child(first)
	add_child(second)
	panel._apply_ship_preview(first, original, Rect2(Vector2.ZERO, Vector2(240, 180)))
	panel._apply_ship_preview(second, altered, Rect2(Vector2.ZERO, Vector2(240, 180)))
	assert_eq(second.size, first.size)
	assert_eq(second.position, first.position)
	assert_eq(second.rotation, first.rotation)

func test_rotated_fit_uses_eighty_percent_of_target_without_clipping() -> void:
	assert_true(panel.set_selected_ship_id(&"nave_rastreadora"))
	await get_tree().process_frame
	var ship := ShipCatalog.get_ship(&"nave_rastreadora")
	var target := panel.get_node("ShipCarousel/PreviewClip") as Control
	var preview := panel.get_node("ShipCarousel/PreviewClip/ShipPreview") as TextureRect
	var visible := panel._visible_region(ship.hull_texture, panel._preview_region(ship))
	var rotation := ship.visual_rotation_offset
	var cosine := absf(cos(rotation))
	var sine := absf(sin(rotation))
	var rotated_size := Vector2(cosine * visible.size.x + sine * visible.size.y, sine * visible.size.x + cosine * visible.size.y)
	var region := panel._preview_region(ship)
	var fit_scale := preview.size.x / region.size.x
	var fitted := rotated_size * fit_scale
	assert_almost_eq(maxf(fitted.x / target.size.x, fitted.y / target.size.y), 0.8, 0.03)
	assert_lte(fitted.x, target.size.x * 0.8 + 1.0)
	assert_lte(fitted.y, target.size.y * 0.8 + 1.0)
	assert_almost_eq(preview.rotation, -PI / 2.0, 0.00001)

func test_ring_of_five_applies_fit_to_every_thumbnail() -> void:
	await get_tree().process_frame
	assert_eq(panel._ship_ring_entries.size(), 5)
	for entry in panel._ship_ring_entries:
		var icon: TextureRect = entry["preview"]
		assert_not_null(icon.texture)
		assert_gt(icon.size.x, 0.0)
		assert_gt(icon.size.y, 0.0)

func test_hull_keeps_texture_without_remap_material_and_fx_receives_character_thrust_color() -> void:
	var character := CharacterDef.get_roster()[0]
	assert_true(panel.set_selected_ids(&"nave_bruta", character.id))
	var ship := ShipCatalog.get_ship(&"nave_bruta")
	var preview := panel.get_node("ShipCarousel/PreviewClip/ShipPreview") as TextureRect
	var fx := panel.get_node("ShipCarousel/PreviewClip/ShipEnergyFx") as SelectionShipEnergyFx
	assert_eq(preview.material, null)
	assert_eq((preview.texture as AtlasTexture).atlas, ship.hull_texture)
	assert_eq(fx.thrust_color, character.thrust_color)
	assert_eq(fx.ship_rotation, ship.visual_rotation_offset)

func test_ability_slots_are_separate_and_resolve_character_and_ship_catalog_names() -> void:
	assert_true(panel.set_selected_ids(&"nave_interestelar", &"hacker"))
	var character := CharacterDef.resolve_id(&"hacker")
	var ship := ShipCatalog.get_ship(&"nave_interestelar")
	var character_ability := AbilityCatalog.get_ability(character.ability_e)
	var ship_ability := AbilityCatalog.get_ability(ship.ability_q)
	assert_true(panel.get_node("AbilitySlots/CharacterAbility").text.begins_with("E  "))
	assert_true(panel.get_node("AbilitySlots/ShipAbility").text.begins_with("Q  "))
	assert_eq(panel.get_node("AbilitySlots/CharacterAbility").text, "E  " + character_ability.display_name)
	assert_eq(panel.get_node("AbilitySlots/ShipAbility").text, "Q  " + ship_ability.display_name)
	assert_ne(panel.get_node("AbilitySlots/CharacterAbility").text,
		panel.get_node("AbilitySlots/ShipAbility").text)

func test_programmatic_selection_accepts_only_valid_ids_without_signal() -> void:
	watch_signals(panel)
	var character := CharacterDef.get_roster()[2].id
	var ship := ShipCatalog.all()[1].id
	assert_true(panel.set_selected_character_id(character))
	assert_true(panel.set_selected_ship_id(ship))
	assert_false(panel.set_selected_character_id(&"missing"))
	assert_false(panel.set_selected_ship_id(&"missing"))
	assert_signal_not_emitted(panel, &"selection_changed")
	assert_eq(panel.selected_character_id(), character)
	assert_eq(panel.selected_ship_id(), ship)

func test_confirm_is_once_and_back_emits() -> void:
	watch_signals(panel)
	panel._confirm_selection()
	panel._confirm_selection()
	assert_signal_emit_count(panel, &"continue_requested", 1)
	assert_signal_emitted_with_parameters(panel, &"continue_requested", [panel.selected_ship_id(), panel.selected_character_id()])
	panel.get_node("Actions/Back").pressed.emit()
	assert_signal_emit_count(panel, &"back_requested", 1)

func test_character_changes_art_and_ship_changes_preview_and_stats() -> void:
	var art := panel.get_node("CharacterCarousel/ArtClip/CharacterArt") as TextureRect
	var preview := panel.get_node("ShipCarousel/PreviewClip/ShipPreview") as TextureRect
	assert_true(panel.set_selected_ids(&"nave_interceptadora", &"hacker"))
	await get_tree().process_frame
	var initial_art := art.texture
	var initial_preview := preview.texture
	var initial_stats := _filled_segments_by_stat()
	assert_true(panel.set_selected_character_id(&"hacker"))
	await get_tree().process_frame
	assert_eq(_filled_segments_by_stat(), initial_stats)
	var character := panel._roster[(panel._character_index + 1) % panel._roster.size()]
	assert_true(panel.set_selected_character_id(character.id))
	await get_tree().process_frame
	assert_ne(art.texture, initial_art)
	assert_ne(_filled_segments_by_stat(), initial_stats)
	var character_stats := _filled_segments_by_stat()
	assert_true(panel.set_selected_ship_id(&"nave_bruta"))
	assert_ne(preview.texture, initial_preview)
	assert_ne(_filled_segments_by_stat(), character_stats)

func test_character_carousel_exposes_three_distinct_splash_cards_and_rotates_circularly() -> void:
	var previous := panel.get_node("CharacterCarousel/ArtClip/PreviousArt") as TextureRect
	var selected := panel.get_node("CharacterCarousel/ArtClip/CharacterArt") as TextureRect
	var next := panel.get_node("CharacterCarousel/ArtClip/NextArt") as TextureRect
	var cards := [previous, selected, next]
	assert_eq(cards.size(), 3)
	var roster := panel._roster
	assert_eq(roster.size(), 3)
	var initial_index := panel._character_index
	var initial_expected := [
		roster[posmod(initial_index - 1, roster.size())],
		roster[initial_index],
		roster[posmod(initial_index + 1, roster.size())],
	]
	for index in cards.size():
		assert_eq(cards[index].texture, initial_expected[index].splash_art)
		assert_ne(cards[index].texture, null)
	assert_ne(previous.texture, selected.texture)
	assert_ne(selected.texture, next.texture)
	assert_ne(previous.texture, next.texture)
	assert_eq(selected.modulate, Color.WHITE)
	assert_almost_eq(previous.modulate.a, 0.54, 0.00001)
	assert_almost_eq(next.modulate.a, 0.54, 0.00001)

	var initial_id := panel.selected_character_id()
	panel._step_character(1)
	var rotated_index := panel._character_index
	assert_eq(panel.selected_character_id(), roster[rotated_index].id)
	assert_eq(previous.texture, roster[posmod(rotated_index - 1, roster.size())].splash_art)
	assert_eq(selected.texture, roster[rotated_index].splash_art)
	assert_eq(next.texture, roster[posmod(rotated_index + 1, roster.size())].splash_art)
	assert_eq(selected.modulate, Color.WHITE)
	assert_almost_eq(previous.modulate.a, 0.54, 0.00001)
	assert_almost_eq(next.modulate.a, 0.54, 0.00001)
	for _i in roster.size() - 1:
		panel._step_character(1)
	assert_eq(panel.selected_character_id(), initial_id)

func test_normalization_contract_includes_clamp_and_equal_range() -> void:
	panel._ranges[&"max_health"] = {"min": 10.0, "max": 20.0}
	assert_eq(panel._normalized(&"max_health", 10.0), 0.0)
	assert_eq(panel._normalized(&"max_health", 20.0), 1.0)
	assert_eq(panel._normalized(&"max_health", 5.0), 0.0)
	assert_eq(panel._normalized(&"max_health", 30.0), 1.0)
	panel._ranges[&"max_health"] = {"min": 10.0, "max": 10.0}
	assert_eq(panel._normalized(&"max_health", 10.0), 1.0)

func test_roster_splashes_are_final_resources_with_portrait_fallback() -> void:
	for character in CharacterDef.get_roster():
		assert_not_null(character.splash_art)
		assert_true(character.splash_art.resource_path.begins_with("res://assets/characters/splashes/"))
	var fallback := CharacterDef.new()
	assert_eq(fallback.splash_art, null)

func test_keyboard_navigation_actions_are_bound_to_focusable_controls() -> void:
	assert_eq(panel.get_node("CharacterCarousel/Up").focus_mode, Control.FOCUS_NONE)
	assert_eq(panel.get_node("CharacterCarousel/Down").focus_mode, Control.FOCUS_NONE)
	assert_eq(panel.get_node("ShipCarousel/Left").focus_mode, Control.FOCUS_NONE)
	assert_eq(panel.get_node("ShipCarousel/Right").focus_mode, Control.FOCUS_NONE)
	assert_true(panel.get_node("Actions/Confirm").focus_mode != Control.FOCUS_NONE)
	assert_true(panel.get_node("Actions/Back").focus_mode != Control.FOCUS_NONE)

func test_navigation_button_click_then_real_enter_does_not_rotate_again() -> void:
	watch_signals(panel)
	_selection_changed_count = 0
	_continue_requested_count = 0
	panel.selection_changed.connect(_on_selection_changed)
	panel.continue_requested.connect(_on_continue_requested)
	var cases := [
		{
			"button": panel.get_node("CharacterCarousel/Up") as Button,
			"changes_character": true,
		},
		{
			"button": panel.get_node("ShipCarousel/Left") as Button,
			"changes_character": false,
		},
	]
	for _index in cases.size():
		panel.reset()
		var button: Button = cases[_index].button
		var before_ship := panel.selected_ship_id()
		var before_character := panel.selected_character_id()
		var before_selection_changed := _selection_changed_count
		var before_continue_requested := _continue_requested_count
		var click_position := button.get_global_rect().get_center()
		_send_mouse_motion(click_position)
		_send_mouse_button(MOUSE_BUTTON_LEFT, true, click_position)
		await get_tree().process_frame
		_send_mouse_button(MOUSE_BUTTON_LEFT, false, click_position)
		await get_tree().process_frame
		var post_click_ship := panel.selected_ship_id()
		var post_click_character := panel.selected_character_id()
		assert_eq(post_click_ship != before_ship, not cases[_index].changes_character)
		assert_eq(post_click_character != before_character, cases[_index].changes_character)
		assert_eq(panel.selected_ship_id(), post_click_ship)
		assert_eq(panel.selected_character_id(), post_click_character)
		assert_eq(_selection_changed_count, before_selection_changed + 1)
		assert_eq(_continue_requested_count, before_continue_requested)
		_send_key(KEY_ENTER, true)
		await get_tree().process_frame
		await get_tree().process_frame
		assert_eq(panel.selected_ship_id(), post_click_ship)
		assert_eq(panel.selected_character_id(), post_click_character)
		assert_eq(_selection_changed_count, before_selection_changed + 1)
		assert_eq(_continue_requested_count, before_continue_requested + 1)
		_send_key(KEY_ENTER, false)
		await get_tree().process_frame

func _on_selection_changed(_ship_id: StringName, _character_id: StringName) -> void:
	_selection_changed_count += 1

func _on_continue_requested(_ship_id: StringName, _character_id: StringName) -> void:
	_continue_requested_count += 1

func _send_mouse_motion(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	Input.parse_input_event(event)

func _send_mouse_button(button: MouseButton, pressed: bool, position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = position
	event.global_position = position
	Input.parse_input_event(event)
	if button == MOUSE_BUTTON_LEFT:
		if pressed and not _pressed_mouse_buttons.has(button):
			_pressed_mouse_buttons.append(button)
		elif not pressed:
			_pressed_mouse_buttons.erase(button)

func _filled_segments_by_stat() -> Array[int]:
	var filled: Array[int] = []
	for row in panel.get_node("StatsPanel/Stats").get_children():
		assert_true(row is VBoxContainer)
		assert_true(row.get_child(0) is Label)
		assert_true(row.get_child(1) is HBoxContainer)
		var count := 0
		for segment in row.get_child(1).get_children():
			if segment.color == Color("69f6d9"):
				count += 1
		filled.append(count)
	return filled

func _score_for_stat(stat_id: StringName) -> int:
	var index := panel.STAT_IDS.find(stat_id)
	assert_gte(index, 0)
	return _filled_segments_by_stat()[index]

func _expected_presence(ship: ShipDef, character: CharacterDef, stat_id: StringName) -> bool:
	var stats := StatBlock.new(StatCatalog.get_all())
	Loadout.apply(stats, ship, character)
	var active_modifiers := stats.get_active_modifiers()
	for base_stat in ship.base_stats:
		if base_stat != null and base_stat.stat == stat_id:
			return true
	for modifier in active_modifiers:
		if modifier != null and modifier.stat == stat_id:
			return true
	return false

func _expected_stat_ranges() -> Dictionary:
	var ranges: Dictionary = {}
	for stat_id in panel.STAT_IDS:
		var baseline := StatCatalog.get_stat(stat_id).default_base
		ranges[stat_id] = {"min": baseline, "max": baseline}
	for ship in panel._ships:
		for character in panel._roster:
			var stats := StatBlock.new(StatCatalog.get_all())
			Loadout.apply(stats, ship, character)
			for stat_id in panel.STAT_IDS:
				var value := stats.get_stat(stat_id)
				ranges[stat_id]["min"] = minf(ranges[stat_id]["min"], value)
				ranges[stat_id]["max"] = maxf(ranges[stat_id]["max"], value)
	return ranges

func _expected_score(value: float, present: bool, range: Dictionary) -> int:
	if not present:
		return 0
	var minimum := float(range["min"])
	var maximum := float(range["max"])
	if is_equal_approx(maximum, minimum):
		return 1
	var normalized := clampf((value - minimum) / (maximum - minimum), 0.0, 1.0)
	return clampi(1 + roundi(3.0 * normalized), 1, 4)

func _send_key(keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)
	if pressed and not _pressed_keys.has(keycode):
		_pressed_keys.append(keycode)
	elif not pressed:
		_pressed_keys.erase(keycode)

func test_keyboard_and_controller_navigation_rotate_circularly_once_per_action() -> void:
	watch_signals(panel)
	var initial_character := panel.selected_character_id()
	var initial_ship := panel.selected_ship_id()
	var key_e := InputEventKey.new()
	key_e.keycode = KEY_E
	key_e.pressed = true
	panel._unhandled_input(key_e)
	assert_ne(panel.selected_character_id(), initial_character)
	assert_signal_emit_count(panel, &"selection_changed", 1)
	var key_q := InputEventKey.new()
	key_q.keycode = KEY_Q
	key_q.pressed = true
	panel._unhandled_input(key_q)
	assert_ne(panel.selected_ship_id(), initial_ship)
	assert_signal_emit_count(panel, &"selection_changed", 2)
	panel.get_node("CharacterCarousel/Down").pressed.emit()
	assert_true(panel.set_selected_ship_id(&"nave_bruta"))
	for _i in 5:
		panel.get_node("ShipCarousel/Right").pressed.emit()
		assert_signal_emit_count(panel, &"selection_changed", 3 + _i + 1)
	assert_eq(panel.selected_ship_id(), &"nave_bruta")
	assert_signal_emit_count(panel, &"selection_changed", 8)

func test_real_joypad_input_reaches_focused_panel_control_once() -> void:
	watch_signals(panel)
	panel.grab_initial_focus()
	var initial_character := panel.selected_character_id()
	var initial_ship := panel.selected_ship_id()
	_send_joypad_button(JOY_BUTTON_DPAD_DOWN, true)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_ne(panel.selected_character_id(), initial_character)
	assert_eq(panel.selected_ship_id(), initial_ship)
	assert_signal_emit_count(panel, &"selection_changed", 1)
	_send_joypad_button(JOY_BUTTON_DPAD_DOWN, false)
	await get_tree().process_frame
	assert_eq(panel.selected_character_id(), panel._roster[posmod(panel._character_index, panel._roster.size())].id)
	assert_signal_emit_count(panel, &"selection_changed", 1)

	_send_joypad_button(JOY_BUTTON_A, true)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_signal_emit_count(panel, &"continue_requested", 1)
	_send_joypad_button(JOY_BUTTON_A, false)
	await get_tree().process_frame
	assert_signal_emit_count(panel, &"selection_changed", 1)
	assert_signal_emit_count(panel, &"continue_requested", 1)

func _send_joypad_button(button: int, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)
	if pressed and not _pressed_joypad_buttons.has(button):
		_pressed_joypad_buttons.append(button)
	elif not pressed:
		_pressed_joypad_buttons.erase(button)

func test_programmatic_pair_setter_is_atomic_silent_and_confirmation_is_single() -> void:
	watch_signals(panel)
	var old_ship := panel.selected_ship_id()
	var old_character := panel.selected_character_id()
	assert_false(panel.set_selected_ids(&"missing", &"hacker"))
	assert_eq(panel.selected_ship_id(), old_ship)
	assert_eq(panel.selected_character_id(), old_character)
	assert_signal_not_emitted(panel, &"selection_changed")
	assert_true(panel.set_selected_ids(&"nave_bruta", &"hacker"))
	assert_signal_not_emitted(panel, &"selection_changed")
	panel._confirm_selection()
	panel._confirm_selection()
	assert_signal_emit_count(panel, &"continue_requested", 1)
