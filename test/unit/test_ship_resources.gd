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

const SHIP_IMPORT_PATHS := [
	"res://assets/sprites/bruta.png.import",
	"res://assets/sprites/engenheira.png.import",
	"res://assets/sprites/interceptadora.png.import",
	"res://assets/sprites/interestelar.png.import",
	"res://assets/sprites/rastreadora.png.import",
]

const BRUTA_ESCAPE_ROI := Rect2i(8, 1, 1, 22)

func test_ship_resources_have_unique_non_empty_uids() -> void:
	var uids := {}
	var uid_pattern := RegEx.new()
	uid_pattern.compile("^uid://[A-Za-z0-9]+$")
	for ship_id in SHIP_PATHS:
		var resource_path: String = SHIP_PATHS[ship_id]
		assert_true(FileAccess.file_exists(resource_path), "Arquivo .tres deve existir: %s" % resource_path)
		var content := FileAccess.get_file_as_string(resource_path)
		var header := content.get_slice("\n", 0)
		var match := RegEx.create_from_string("^\\[gd_resource[^\\n]*\\buid=\\\"([^\\\"]*)\\\"").search(header)
		assert_not_null(match, "Cabeçalho deve declarar UID: %s" % resource_path)
		if match == null:
			continue
		var uid := match.get_string(1)
		assert_false(uid.is_empty(), "UID não pode ser vazio: %s" % resource_path)
		assert_not_null(uid_pattern.search(uid), "UID deve ter formato válido: %s" % resource_path)
		assert_false(uids.has(uid), "UID deve ser único: %s" % resource_path)
		uids[uid] = true
	assert_eq(uids.size(), SHIP_PATHS.size(), "Os seis .tres devem ter UIDs únicos")

func test_base_ship_uses_base_ship_texture() -> void:
	var content := FileAccess.get_file_as_string(SHIP_PATHS[&"nave_base"])
	assert_true(content.contains('path="res://assets/sprites/ship.png"'), "Nave base deve apontar para ship.png")


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
		assert_true(FileAccess.file_exists(NEW_SHIP_TEXTURES[ship_id]), "Arquivo da textura de %s deve existir" % ship_id)
		var image := Image.load_from_file(ProjectSettings.globalize_path(NEW_SHIP_TEXTURES[ship_id]))
		assert_not_null(image, "Textura de %s deve carregar diretamente do arquivo" % ship_id)
		if image != null:
			assert_eq(image.get_width(), 80, "Largura de %s" % ship_id)
			assert_eq(image.get_height(), 48, "Altura de %s" % ship_id)

func test_new_ship_textures_have_transparent_corners() -> void:
	for ship_id in NEW_SHIP_TEXTURES:
		var image := Image.load_from_file(ProjectSettings.globalize_path(NEW_SHIP_TEXTURES[ship_id]))
		assert_not_null(image, "Textura de %s deve carregar" % ship_id)
		if image == null:
			continue
		for corner in [Vector2i(0, 0), Vector2i(79, 0), Vector2i(0, 47), Vector2i(79, 47)]:
			assert_lt(image.get_pixelv(corner).a, 1.0, "Canto %s de %s deve ser transparente" % [corner, ship_id])

func test_bruta_texture_is_rgba_and_each_atlas_cell_has_content() -> void:
	var image := Image.load_from_file(ProjectSettings.globalize_path(NEW_SHIP_TEXTURES[&"nave_bruta"]))
	assert_not_null(image, "Textura da Bruta deve carregar")
	if image == null:
		return
	assert_eq(image.get_format(), Image.FORMAT_RGBA8, "Textura da Bruta deve estar em formato RGBA8")
	for row in 2:
		for column in 5:
			var has_content := false
			for y in 24:
				for x in 16:
					if image.get_pixel(column * 16 + x, row * 24 + y).a > 0.0:
						has_content = true
						break
				if has_content:
					break
			assert_true(has_content, "Célula %d,%d da Bruta deve conter pixels não transparentes" % [column, row])

func test_bruta_propulsion_frames_are_different() -> void:
	var image := Image.load_from_file(ProjectSettings.globalize_path(NEW_SHIP_TEXTURES[&"nave_bruta"]))
	assert_not_null(image, "Textura da Bruta deve carregar")
	if image == null:
		return
	for column in 5:
		assert_false(_bruta_cells_match(image, column, column, false), "Os frames de propulsão devem diferir na coluna %d" % column)
		assert_true(_bruta_cells_match(image, column, column, true), "O casco da coluna %d deve ser idêntico entre as linhas" % column)

func test_bruta_top_row_has_five_geometrically_distinct_poses() -> void:
	var image := Image.load_from_file(ProjectSettings.globalize_path(NEW_SHIP_TEXTURES[&"nave_bruta"]))
	assert_not_null(image, "Textura da Bruta deve carregar")
	if image == null:
		return
	for left_column in 5:
		for right_column in range(left_column + 1, 5):
			assert_false(_bruta_top_cells_match(image, left_column, right_column), "As poses %d e %d não podem ser idênticas" % [left_column, right_column])
			assert_false(_bruta_is_x_translation(image, left_column, right_column, 2), "As poses %d e %d não podem ser cópias deslocadas em X" % [left_column, right_column])

func test_bruta_has_four_distinct_opaque_pod_groups_per_cell() -> void:
	var image := Image.load_from_file(ProjectSettings.globalize_path(NEW_SHIP_TEXTURES[&"nave_bruta"]))
	assert_not_null(image, "Textura da Bruta deve carregar")
	if image == null:
		return
	for row in 2:
		for column in 5:
			assert_eq(_bruta_pod_group_count(image, column, row), 4, "Célula %d,%d deve ter quatro grupos opacos de propulsores" % [column, row])

func test_bruta_resource_loads_and_points_to_texture() -> void:
	var bruta := load(SHIP_PATHS[&"nave_bruta"]) as ShipDef
	assert_not_null(bruta, "Resource da Bruta deve carregar")
	if bruta == null:
		return
	assert_not_null(bruta.hull_texture, "Bruta deve apontar para uma textura de casco")
	if bruta.hull_texture != null:
		assert_eq(bruta.hull_texture.resource_path, NEW_SHIP_TEXTURES[&"nave_bruta"], "Bruta deve apontar para bruta.png")

func _bruta_cells_match(image: Image, left_column: int, right_column: int, ignore_energy: bool) -> bool:
	for y in 24:
		for x in 16:
			if ignore_energy and _is_bruta_energy_zone(x, y):
				continue
			if not image.get_pixel(left_column * 16 + x, y).is_equal_approx(image.get_pixel(right_column * 16 + x, y + 24)):
				return false
	return true

func _bruta_top_cells_match(image: Image, left_column: int, right_column: int) -> bool:
	for y in 24:
		for x in 16:
			if not is_equal_approx(
				image.get_pixel(left_column * 16 + x, y).a,
				image.get_pixel(right_column * 16 + x, y).a
			):
				return false
	return true

func _bruta_is_x_translation(image: Image, left_column: int, right_column: int, maximum_offset: int) -> bool:
	for offset in range(-maximum_offset, maximum_offset + 1):
		var matches := true
		for y in 24:
			for x in 16:
				var source_x := x - offset
				var source_color := Color(0, 0, 0, 0)
				if source_x >= 0 and source_x < 16:
					source_color = image.get_pixel(left_column * 16 + source_x, y)
				if source_color != image.get_pixel(right_column * 16 + x, y):
					matches = false
					break
			if not matches:
				break
		if matches:
			return true
	return false

func _bruta_pod_group_count(image: Image, column: int, row: int) -> int:
	# Four broad rear/side ROIs make this alpha-component check independent of pod colors.
	var regions := [Rect2i(0, 1, 7, 9), Rect2i(9, 1, 7, 9), Rect2i(0, 14, 7, 10), Rect2i(9, 14, 7, 10)]
	var groups := 0
	for region in regions:
		if _has_opaque_component(image, Rect2i(column * 16 + region.position.x, row * 24 + region.position.y, region.size.x, region.size.y)):
			groups += 1
	return groups

func _has_opaque_component(image: Image, region: Rect2i) -> bool:
	var pending: Array[Vector2i] = []
	var visited := {}
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var start := Vector2i(x, y)
			if visited.has(start) or image.get_pixelv(start).a <= 0.0:
				continue
			pending.append(start)
			visited[start] = true
			while not pending.is_empty():
				var pixel: Vector2i = pending.pop_back()
				for neighbor in [pixel + Vector2i.LEFT, pixel + Vector2i.RIGHT, pixel + Vector2i.UP, pixel + Vector2i.DOWN]:
					if region.has_point(neighbor) and not visited.has(neighbor) and image.get_pixelv(neighbor).a > 0.0:
						visited[neighbor] = true
						pending.append(neighbor)
			return true
	return false

func _is_bruta_energy_zone(x: int, y: int) -> bool:
	return BRUTA_ESCAPE_ROI.has_point(Vector2i(x, y))

func test_engineer_uses_engineer_deploy_ability() -> void:
	var engineer := ShipCatalog.get_ship(&"nave_engenheira")
	assert_not_null(engineer)
	if engineer != null:
		assert_eq(engineer.ability_q, &"engenheira_deploy")

func test_ship_sprite_imports_have_unique_non_empty_uids() -> void:
	var uids := {}
	var uid_pattern := RegEx.new()
	uid_pattern.compile("^uid://[A-Za-z0-9]+$")
	for import_path in SHIP_IMPORT_PATHS:
		assert_true(FileAccess.file_exists(import_path), "Arquivo .import deve existir: %s" % import_path)
		var content := FileAccess.get_file_as_string(import_path)
		var match := RegEx.create_from_string("uid=\\\"([^\\\"]*)\\\"").search(content)
		assert_not_null(match, "Arquivo .import deve declarar UID: %s" % import_path)
		if match == null:
			continue
		var uid := match.get_string(1)
		assert_false(uid.is_empty(), "UID não pode ser vazio: %s" % import_path)
		assert_not_null(uid_pattern.search(uid), "UID deve ter formato válido: %s" % import_path)
		assert_false(uids.has(uid), "UID deve ser único: %s" % import_path)
		uids[uid] = true
	assert_eq(uids.size(), SHIP_IMPORT_PATHS.size(), "Os cinco .import devem ter UIDs únicos")

func test_interceptor_uses_interceptadora_blink_ability() -> void:
	var interceptor := ShipCatalog.get_ship(&"nave_interceptadora")
	assert_not_null(interceptor)
	if interceptor != null:
		assert_eq(interceptor.ability_q, &"interceptadora_blink")

func test_interstellar_is_the_fastest_ship() -> void:
	var interstellar := ShipCatalog.get_ship(&"nave_interestelar")
	assert_not_null(interstellar)
	if interstellar == null:
		return
	var interstellar_speed := _base_stat_value(interstellar, &"max_speed")
	for ship in ShipCatalog.all():
		assert_gte(interstellar_speed, _base_stat_value(ship, &"max_speed"), "%s não pode ser mais rápida que a Interestelar" % ship.id)

func _base_stat_value(ship: ShipDef, stat: StringName) -> float:
	for base_stat in ship.base_stats:
		if base_stat != null and base_stat.stat == stat:
			return base_stat.value
	return -INF
