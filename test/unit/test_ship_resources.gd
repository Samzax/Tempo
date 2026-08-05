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
	&"nave_bruta": "res://assets/sprites/bruta.png",
	&"nave_engenheira": "res://assets/sprites/engenheira.png",
	&"nave_rastreadora": "res://assets/sprites/rastreadora.png",
	&"nave_interceptadora": "res://assets/sprites/interceptadora.png",
	&"nave_interestelar": "res://assets/sprites/interestelar.png",
}

func test_all_ship_resources_load_with_exact_ids_and_valid_content() -> void:
	var catalog_ids := {}
	for ship in ShipCatalog.all():
		catalog_ids[ship.id] = true
	assert_eq(catalog_ids.size(), SHIP_PATHS.size(), "Catálogo deve conter exatamente os seis ShipDef")
	for expected_id in SHIP_PATHS:
		assert_true(catalog_ids.has(expected_id), "Catálogo deve conter %s" % expected_id)

	for expected_id in SHIP_PATHS:
		var ship := load(SHIP_PATHS[expected_id]) as ShipDef
		assert_not_null(ship, "Resource da nave %s deve carregar" % expected_id)
		if ship == null:
			continue
		assert_eq(ship.id, expected_id)
		assert_false(ship.ability_q.is_empty(), "Nave %s deve declarar ability_q" % expected_id)
		assert_true(AbilityCatalog.is_valid(ship.ability_q), "ability_q de %s deve ser válida" % expected_id)
		var errors := ship.validate_content()
		assert_eq(errors.size(), 0, "Nave %s inválida: %s" % [expected_id, "; ".join(errors)])

func test_new_ships_have_hull_textures() -> void:
	for ship_id in NEW_SHIP_TEXTURES:
		var ship := ShipCatalog.get_ship(ship_id)
		assert_not_null(ship)
		if ship != null:
			assert_not_null(ship.hull_texture, "Nave %s deve ter hull_texture" % ship_id)

func test_new_ship_textures_are_80_by_48() -> void:
	for ship_id in NEW_SHIP_TEXTURES:
		var image := Image.new()
		var error := image.load_from_file(ProjectSettings.globalize_path(NEW_SHIP_TEXTURES[ship_id]))
		assert_eq(error, OK, "Textura de %s deve carregar diretamente do arquivo" % ship_id)
		if error == OK:
			assert_eq(image.get_width(), 80, "Largura de %s" % ship_id)
			assert_eq(image.get_height(), 48, "Altura de %s" % ship_id)

func test_interstellar_texture_has_transparent_corners() -> void:
	var image := Image.new()
	var error := image.load_from_file(ProjectSettings.globalize_path(NEW_SHIP_TEXTURES[&"nave_interestelar"]))
	assert_eq(error, OK)
	if error != OK:
		return
	for corner in [Vector2i(0, 0), Vector2i(79, 0), Vector2i(0, 47), Vector2i(79, 47)]:
		assert_lt(image.get_pixelv(corner).a, 1.0, "Canto %s deve ser transparente" % corner)
