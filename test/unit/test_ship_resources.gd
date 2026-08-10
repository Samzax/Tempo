extends GutTest

const SHIP_PATHS := {
	&"nave_base": "res://resources/ships/base.tres",
	&"nave_bruta": "res://resources/ships/bruta.tres",
	&"nave_engenheira": "res://resources/ships/engenheira.tres",
	&"nave_rastreadora": "res://resources/ships/rastreadora.tres",
	&"nave_interceptadora": "res://resources/ships/interceptadora.tres",
	&"nave_interestelar": "res://resources/ships/interestelar.tres",
}
const NEW_SHIP_TEXTURES := {
	&"nave_bruta": "res://assets/sprites/bruta-hull.png",
	&"nave_engenheira": "res://assets/sprites/engenheira.png",
	&"nave_rastreadora": "res://assets/sprites/rastreadora_v2.png",
	&"nave_interceptadora": "res://assets/sprites/interceptadora.png",
	&"nave_interestelar": "res://assets/sprites/interestelar.png",
}
const SHIP_IMPORT_PATHS := [
	"res://assets/sprites/bruta-hull.png.import",
	"res://assets/sprites/engenheira.png.import",
	"res://assets/sprites/interceptadora.png.import",
	"res://assets/sprites/interestelar.png.import",
	"res://assets/sprites/rastreadora_v2.png.import",
]

func test_ship_resources_have_unique_non_empty_uids() -> void:
	var uids := {}
	var uid_pattern := RegEx.new()
	uid_pattern.compile("^uid://[A-Za-z0-9]+$")
	for ship_id in SHIP_PATHS:
		var path: String = SHIP_PATHS[ship_id]
		assert_true(FileAccess.file_exists(path))
		var match := RegEx.create_from_string("^\\[gd_resource[^\\n]*\\buid=\\\"([^\\\"]*)\\\"").search(FileAccess.get_file_as_string(path).get_slice("\\n", 0))
		assert_not_null(match)
		if match != null:
			var uid := match.get_string(1)
			assert_false(uid.is_empty())
			assert_not_null(uid_pattern.search(uid))
			assert_false(uids.has(uid))
			uids[uid] = true
	assert_eq(uids.size(), SHIP_PATHS.size())

func test_base_ship_uses_base_ship_texture() -> void:
	assert_true(FileAccess.get_file_as_string(SHIP_PATHS[&"nave_base"]).contains('path="res://assets/sprites/ship.png"'))

func test_all_ship_resources_load_with_exact_ids_and_valid_content() -> void:
	var catalog_ids := {}
	for ship in ShipCatalog.all():
		catalog_ids[ship.id] = true
	assert_eq(catalog_ids.size(), SHIP_PATHS.size())
	for expected_id in SHIP_PATHS:
		assert_true(catalog_ids.has(expected_id))
		var ship := load(SHIP_PATHS[expected_id]) as ShipDef
		assert_not_null(ship)
		if ship != null:
			assert_eq(ship.id, expected_id)
			assert_false(ship.ability_q.is_empty())
			assert_true(AbilityCatalog.is_valid(ship.ability_q))
			assert_eq(ship.validate_content().size(), 0)

func test_new_ships_have_hull_textures() -> void:
	for ship_id in NEW_SHIP_TEXTURES:
		var ship := ShipCatalog.get_ship(ship_id)
		assert_not_null(ship)
		if ship != null:
			assert_not_null(ship.hull_texture)

func test_interestelar_texture_is_rgba8_1983_by_793() -> void:
	var image := Image.load_from_file(ProjectSettings.globalize_path(NEW_SHIP_TEXTURES[&"nave_interestelar"]))
	assert_not_null(image)
	if image != null:
		assert_eq(image.get_size(), Vector2i(1983, 793))
		assert_eq(image.get_format(), Image.FORMAT_RGBA8)

func test_interestelar_resource_uses_complete_custom_ten_frame_atlas() -> void:
	var interestelar := load(SHIP_PATHS[&"nave_interestelar"]) as ShipDef
	assert_not_null(interestelar)
	if interestelar == null:
		return
	assert_eq(interestelar.frame_size, Vector2i(397, 397))
	assert_eq(interestelar.atlas_grid_size, Vector2i(5, 2))
	assert_almost_eq(interestelar.visual_scale, 0.06, 0.00001)
	var expected_regions: Array[Rect2] = [
		Rect2(0, 0, 397, 397), Rect2(397, 0, 396, 397), Rect2(793, 0, 397, 397), Rect2(1190, 0, 396, 397), Rect2(1586, 0, 397, 397),
		Rect2(0, 397, 397, 396), Rect2(397, 397, 396, 396), Rect2(793, 397, 397, 396), Rect2(1190, 397, 396, 396), Rect2(1586, 397, 397, 397 - 1),
	]
	assert_eq(interestelar.custom_frame_regions, expected_regions)
	var covered_area := 0.0
	for region in interestelar.custom_frame_regions:
		assert_eq(region.position.x, floor(region.position.x))
		assert_eq(region.position.y, floor(region.position.y))
		assert_eq(region.size.x, floor(region.size.x))
		assert_eq(region.size.y, floor(region.size.y))
		assert_gte(region.position.x, 0.0)
		assert_gte(region.position.y, 0.0)
		assert_lte(region.end.x, 1983.0)
		assert_lte(region.end.y, 793.0)
		covered_area += region.get_area()
	assert_eq(covered_area, 1983.0 * 793.0)
	for left_index in interestelar.custom_frame_regions.size():
		for right_index in range(left_index + 1, interestelar.custom_frame_regions.size()):
			assert_false(interestelar.custom_frame_regions[left_index].intersects(interestelar.custom_frame_regions[right_index]))
	assert_eq(interestelar.validate_content(), [])

func test_custom_frame_regions_require_ten_positive_complete_non_overlapping_regions() -> void:
	var ship := ShipDef.new()
	ship.id = &"test_custom_regions"
	ship.hull_texture = load(NEW_SHIP_TEXTURES[&"nave_interestelar"])
	ship.custom_frame_regions = [Rect2(0, 0, 1, 1)]
	assert_gt(ship.validate_content().size(), 0)
	ship.custom_frame_regions = [
		Rect2(0, 0, 397, 397), Rect2(397, 0, 396, 397), Rect2(793, 0, 397, 397), Rect2(1190, 0, 396, 397), Rect2(1586, 0, 397, 397),
		Rect2(0, 397, 397, 396), Rect2(397, 397, 396, 396), Rect2(793, 397, 397, 396), Rect2(1190, 397, 396, 396), Rect2(1586, 397, 397, 396),
	]
	assert_eq(ship.validate_content(), [])
	ship.custom_frame_regions[0] = Rect2(0, 0, 0, 397)
	assert_gt(ship.validate_content().size(), 0)

func test_rastreadora_texture_is_rgba8_1254_by_1254() -> void:
	var image := Image.load_from_file(ProjectSettings.globalize_path(NEW_SHIP_TEXTURES[&"nave_rastreadora"]))
	assert_not_null(image)
	if image != null:
		assert_eq(image.get_size(), Vector2i(1254, 1254))
		assert_eq(image.get_format(), Image.FORMAT_RGBA8)

func test_rastreadora_resource_uses_two_by_two_closed_atlas_layout() -> void:
	var rastreadora := load(SHIP_PATHS[&"nave_rastreadora"]) as ShipDef
	assert_not_null(rastreadora)
	if rastreadora != null:
		assert_not_null(rastreadora.hull_texture)
		if rastreadora.hull_texture != null:
			assert_eq(rastreadora.hull_texture.resource_path, NEW_SHIP_TEXTURES[&"nave_rastreadora"])
		assert_eq(rastreadora.frame_size, Vector2i(627, 627))
		assert_eq(rastreadora.atlas_grid_size, Vector2i(2, 2))
		assert_almost_eq(rastreadora.visual_rotation_offset, -PI / 2.0, 0.00001)
		assert_eq(rastreadora.visual_scale, 0.05)
		# The right-facing source frame is rotated up, placing the nose one scaled
		# half-frame above center. The scene Marker2D already contributes -12 on Y.
		assert_eq(rastreadora.muzzle_offset, Vector2(0, -3.675))
		var front_distance := rastreadora.frame_size.x * rastreadora.visual_scale / 2.0
		assert_almost_eq(-12.0 + rastreadora.muzzle_offset.y, -front_distance, 0.00001)
		assert_eq(rastreadora.validate_content().size(), 0)

func test_engenheira_texture_is_rgba8_320_by_128_with_valid_alpha() -> void:
	var image := Image.load_from_file(ProjectSettings.globalize_path(NEW_SHIP_TEXTURES[&"nave_engenheira"]))
	assert_not_null(image)
	if image == null:
		return
	assert_eq(image.get_size(), Vector2i(320, 128))
	assert_eq(image.get_format(), Image.FORMAT_RGBA8)
	var visible_pixels := 0
	for y in image.get_height():
		for x in image.get_width():
			var alpha := image.get_pixel(x, y).a
			assert_gte(alpha, 0.0)
			assert_lte(alpha, 1.0)
			if alpha > 0.0:
				visible_pixels += 1
	assert_gt(visible_pixels, 0)

func test_engenheira_resource_uses_64_by_64_frames_and_valid_content() -> void:
	var engineer := load(SHIP_PATHS[&"nave_engenheira"]) as ShipDef
	assert_not_null(engineer)
	if engineer != null:
		assert_not_null(engineer.hull_texture)
		if engineer.hull_texture != null:
			assert_eq(engineer.hull_texture.resource_path, NEW_SHIP_TEXTURES[&"nave_engenheira"])
		assert_eq(engineer.frame_size, Vector2i(64, 64))
		assert_eq(engineer.visual_scale, 0.5)
		assert_eq(engineer.muzzle_offset, Vector2(0, -10))
		assert_eq(engineer.validate_content().size(), 0)

func test_interceptadora_texture_is_rgba8_320_by_128_with_valid_alpha() -> void:
	var image := Image.load_from_file(ProjectSettings.globalize_path(NEW_SHIP_TEXTURES[&"nave_interceptadora"]))
	assert_not_null(image)
	if image == null:
		return
	assert_eq(image.get_size(), Vector2i(320, 128))
	assert_eq(image.get_format(), Image.FORMAT_RGBA8)
	var visible_pixels := 0
	for y in image.get_height():
		for x in image.get_width():
			var alpha := image.get_pixel(x, y).a
			assert_gte(alpha, 0.0)
			assert_lte(alpha, 1.0)
			if alpha > 0.0:
				visible_pixels += 1
	assert_gt(visible_pixels, 0)

func test_interceptadora_neutral_variant_lower_frames_are_not_blue_cyan_dominant() -> void:
	var image := Image.load_from_file(ProjectSettings.globalize_path(NEW_SHIP_TEXTURES[&"nave_interceptadora"]))
	assert_not_null(image)
	if image == null:
		return
	var visible_pixels := 0
	var saturated_blue_cyan_pixels := 0
	for y in range(64, image.get_height()):
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			if color.a > 0.0:
				visible_pixels += 1
				var is_blue_dominant := color.b > color.r + 0.20 and color.b > color.g + 0.10
				var is_cyan_dominant := color.b > color.r + 0.20 and color.g > color.r + 0.20
				if is_blue_dominant or is_cyan_dominant:
					saturated_blue_cyan_pixels += 1
	assert_gt(visible_pixels, 0)
	assert_eq(saturated_blue_cyan_pixels, 0)

func test_interceptadora_resource_uses_64_by_64_frames() -> void:
	var ship := load(SHIP_PATHS[&"nave_interceptadora"]) as ShipDef
	assert_not_null(ship)
	if ship != null:
		assert_eq(ship.frame_size, Vector2i(64, 64))

func test_bruta_texture_is_standalone_rgba8_32_with_opaque_hull_and_no_partial_alpha() -> void:
	var image := Image.load_from_file(ProjectSettings.globalize_path(NEW_SHIP_TEXTURES[&"nave_bruta"]))
	assert_not_null(image)
	if image == null:
		return
	assert_eq(image.get_format(), Image.FORMAT_RGBA8)
	assert_eq(image.get_size(), Vector2i(32, 32))
	var opaque_pixels := 0
	var partial_alpha_pixels := 0
	for y in image.get_height():
		for x in image.get_width():
			var alpha := image.get_pixel(x, y).a
			if alpha >= 1.0:
				opaque_pixels += 1
			elif alpha > 0.0:
				partial_alpha_pixels += 1
	assert_gt(opaque_pixels, 0)
	assert_eq(partial_alpha_pixels, 0)

func test_bruta_texture_has_transparent_corners() -> void:
	var image := Image.load_from_file(ProjectSettings.globalize_path(NEW_SHIP_TEXTURES[&"nave_bruta"]))
	assert_not_null(image)
	if image != null:
		for corner in [Vector2i.ZERO, Vector2i(31, 0), Vector2i(0, 31), Vector2i(31, 31)]:
			assert_eq(image.get_pixelv(corner).a, 0.0)

func test_bruta_resource_loads_and_points_to_texture() -> void:
	var bruta := load(SHIP_PATHS[&"nave_bruta"]) as ShipDef
	assert_not_null(bruta)
	if bruta != null:
		assert_not_null(bruta.hull_texture)
		if bruta.hull_texture != null:
			assert_eq(bruta.hull_texture.resource_path, NEW_SHIP_TEXTURES[&"nave_bruta"])

func test_engineer_uses_engineer_deploy_ability() -> void:
	var engineer := ShipCatalog.get_ship(&"nave_engenheira")
	assert_not_null(engineer)
	if engineer != null:
		assert_eq(engineer.ability_q, &"engenheira_deploy")

func test_ship_sprite_imports_have_unique_non_empty_uids() -> void:
	var uids := {}
	for import_path in SHIP_IMPORT_PATHS:
		assert_true(FileAccess.file_exists(import_path))
		var match := RegEx.create_from_string("uid=\\\"([^\\\"]*)\\\"").search(FileAccess.get_file_as_string(import_path))
		assert_not_null(match)
		if match != null:
			var uid := match.get_string(1)
			assert_false(uid.is_empty())
			assert_false(uids.has(uid))
			uids[uid] = true
	assert_eq(uids.size(), SHIP_IMPORT_PATHS.size())

func test_interceptor_uses_interceptadora_blink_ability() -> void:
	var ship := ShipCatalog.get_ship(&"nave_interceptadora")
	assert_not_null(ship)
	if ship != null:
		assert_eq(ship.ability_q, &"interceptadora_blink")

func test_interstellar_is_the_fastest_ship() -> void:
	var fastest := ShipCatalog.get_ship(&"nave_interestelar")
	assert_not_null(fastest)
	if fastest != null:
		for ship in ShipCatalog.all():
			assert_gte(_base_stat_value(fastest, &"max_speed"), _base_stat_value(ship, &"max_speed"))

func test_ship_thrusters_enabled_match_expected_resources() -> void:
	var interceptadora := load(SHIP_PATHS[&"nave_interceptadora"]) as ShipDef
	assert_not_null(interceptadora)
	if interceptadora != null:
		assert_false(interceptadora.thrusters_enabled)
	var base := load(SHIP_PATHS[&"nave_base"]) as ShipDef
	assert_not_null(base)
	if base != null:
		assert_true(base.thrusters_enabled)
	var bruta := load(SHIP_PATHS[&"nave_bruta"]) as ShipDef
	assert_not_null(bruta)
	if bruta != null:
		assert_true(bruta.thrusters_enabled)

func test_engine_trail_contract_is_opt_in_and_interestelar_defaults_are_exact() -> void:
	var interestelar := load(SHIP_PATHS[&"nave_interestelar"]) as ShipDef
	assert_not_null(interestelar)
	if interestelar == null:
		return
	assert_true(interestelar.engine_trail_enabled)
	assert_eq(interestelar.engine_trail_damage, 1.0)
	assert_eq(interestelar.engine_trail_width, 16.0)
	assert_eq(interestelar.engine_trail_duration, 0.8)
	assert_eq(interestelar.engine_trail_min_speed_ratio, 0.5)
	assert_eq(interestelar.engine_trail_damage_cooldown, 0.5)
	assert_eq(interestelar.engine_trail_segment_spacing, 32.0)
	assert_eq(interestelar.validate_content().size(), 0)

	for ship in ShipCatalog.all():
		if ship.id != &"nave_interestelar":
			assert_false(ship.engine_trail_enabled)
			assert_eq(ship.engine_trail_damage, 0.0)

func test_interestelar_engine_trail_contract_has_speed_threshold_and_shared_cooldown() -> void:
	var interestelar := load(SHIP_PATHS[&"nave_interestelar"]) as ShipDef
	assert_not_null(interestelar)
	if interestelar != null:
		assert_true(interestelar.engine_trail_enabled)
		assert_gt(interestelar.engine_trail_min_speed_ratio, 0.0)
		assert_lte(interestelar.engine_trail_min_speed_ratio, 1.0)
		assert_gt(interestelar.engine_trail_damage_cooldown, 0.0)
		assert_gt(interestelar.engine_trail_segment_spacing, 0.0)

func test_engine_trail_validation_rejects_enabled_invalid_values_but_disabled_defaults_are_inert() -> void:
	var ship := ShipDef.new()
	ship.id = &"test_ship"
	assert_eq(ship.validate_content().size(), 0)
	ship.engine_trail_enabled = true
	assert_gt(ship.validate_content().size(), 0)

func _base_stat_value(ship: ShipDef, stat: StringName) -> float:
	for base_stat in ship.base_stats:
		if base_stat != null and base_stat.stat == stat:
			return base_stat.value
	return -INF
