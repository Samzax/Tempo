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
	&"nave_rastreadora": "res://assets/sprites/rastreadora.png",
	&"nave_interceptadora": "res://assets/sprites/interceptadora.png",
	&"nave_interestelar": "res://assets/sprites/interestelar.png",
}
const SHIP_IMPORT_PATHS := [
	"res://assets/sprites/bruta-hull.png.import",
	"res://assets/sprites/engenheira.png.import",
	"res://assets/sprites/interceptadora.png.import",
	"res://assets/sprites/interestelar.png.import",
	"res://assets/sprites/rastreadora.png.import",
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

func test_legacy_ship_textures_are_80_by_48() -> void:
	for ship_id in [&"nave_engenheira", &"nave_rastreadora", &"nave_interestelar"]:
		var image := Image.load_from_file(ProjectSettings.globalize_path(NEW_SHIP_TEXTURES[ship_id]))
		assert_not_null(image)
		if image != null:
			assert_eq(image.get_size(), Vector2i(80, 48))

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

func _base_stat_value(ship: ShipDef, stat: StringName) -> float:
	for base_stat in ship.base_stats:
		if base_stat != null and base_stat.stat == stat:
			return base_stat.value
	return -INF
