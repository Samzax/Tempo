extends GutTest

const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const BRUTA := preload("res://resources/ships/bruta.tres")
const RASTREADORA := preload("res://resources/ships/rastreadora.tres")
const ENGENHEIRA := preload("res://resources/ships/engenheira.tres")
const ENGINEER_DEPLOYABLE_SCENE := preload("res://scenes/deployables/engineer_deployable.tscn")

class EngineerCommandSession extends Node:
	var drone_commandable := false

	func _ready() -> void:
		add_to_group(&"session")

	func can_command_engineer_drone(_player: Node2D) -> bool:
		return drone_commandable

const ABILITY_ASSETS := {
	&"sobrecarga": "res://assets/ui/abilities/sobrecarga.png",
	&"escudo": "res://assets/ui/abilities/escudo.png",
	&"bruta_investida": "res://assets/ui/abilities/bruta_investida.png",
	&"engenheira_deploy": "res://assets/ui/abilities/engenheira_deploy.png",
	&"interceptadora_blink": "res://assets/ui/abilities/interceptadora_blink.png",
	&"time_warp": "res://assets/ui/abilities/time_warp.png",
	&"guardian_shield": "res://assets/ui/abilities/guardian_shield.png",
	&"hacker_overdrive": "res://assets/ui/abilities/hacker_overdrive.png",
}

func _player(ship: ShipDef, character_id: StringName = &"guardian") -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	await get_tree().process_frame
	assert_true(player.configure_selection(ship, character_id))
	return player

func _real_engineer_session(player: Player) -> Session:
	var host := Node2D.new()
	add_child_autofree(host)
	var session := Session.new()
	session.player_path = NodePath("../Player")
	session.camera_path = NodePath("../Camera2D")
	session.room_host_path = NodePath("../RoomHost")
	session.hyperspace_path = NodePath("../HyperspaceUI")
	player.get_parent().remove_child(player)
	host.add_child(player)
	player.name = "Player"
	var camera := Camera2D.new()
	camera.name = "Camera2D"
	host.add_child(camera)
	var room_host := Node2D.new()
	room_host.name = "RoomHost"
	host.add_child(room_host)
	var hyperspace := HyperspaceUI.new()
	hyperspace.name = "HyperspaceUI"
	host.add_child(hyperspace)
	host.add_child(session)
	var room := Node2D.new()
	room.name = "Room"
	var deployables := Node2D.new()
	deployables.name = "Deployables"
	room.add_child(deployables)
	host.add_child(room)
	session._active_room = room
	session._room_active = true
	await get_tree().process_frame
	return session

func test_all_ability_assets_load_with_catalog_ids() -> void:
	for ability_id in ABILITY_ASSETS:
		var path: String = ABILITY_ASSETS[ability_id]
		var texture := load(path) as Texture2D
		assert_not_null(texture, "asset nao carregou como Texture2D: %s" % ability_id)
		if texture == null:
			continue
		assert_eq(texture.get_size(), Vector2(32, 32), "dimensao inesperada: %s" % ability_id)

func test_engineer_shift_loadout_resolves_and_reflects_drone_commandability() -> void:
	var session := EngineerCommandSession.new()
	add_child_autofree(session)
	var player := await _player(ENGENHEIRA, &"guardian")
	var shift := player.get_ability_hud_slots()[2]
	assert_false(ENGENHEIRA.shift_command_id.is_empty())
	assert_eq(ENGENHEIRA.shift_command_id, &"engenheira_drone_command")
	assert_eq(ENGENHEIRA.shift_command_icon_id, &"engenheira_deploy")
	assert_eq(shift.ability_id, &"engenheira_drone_command")
	assert_eq(shift.icon_id, &"engenheira_deploy")
	assert_eq(shift.state, &"disabled")

	session.drone_commandable = true
	shift = player.get_ability_hud_slots()[2]
	assert_eq(shift.ability_id, &"engenheira_drone_command")
	assert_eq(shift.icon_id, &"engenheira_deploy")
	assert_eq(shift.state, &"ready")

func test_engineer_shift_uses_real_session_and_drone_command_path() -> void:
	var player := await _player(ENGENHEIRA, &"guardian")
	var session := await _real_engineer_session(player)
	var hud_slots := player.get_ability_hud_slots()
	assert_eq(hud_slots[2].ability_id, &"engenheira_drone_command")
	assert_eq(hud_slots[2].icon_id, &"engenheira_deploy")
	assert_eq(hud_slots[2].state, &"disabled")
	assert_false(session.can_command_engineer_drone(player))

	assert_true(session.deploy_engineer_deployable(player))
	await get_tree().process_frame
	var deployables := session._active_room.get_node("Deployables")
	var drone := deployables.get_child(0) as EngineerDeployable
	assert_not_null(drone)
	assert_eq(drone.kind, EngineerDeployable.Kind.DRONE)
	assert_eq(drone, deployables.get_child(0))
	assert_true(session.can_command_engineer_drone(player))
	hud_slots = player.get_ability_hud_slots()
	assert_eq(hud_slots[2].ability_id, &"engenheira_drone_command")
	assert_eq(hud_slots[2].icon_id, &"engenheira_deploy")
	assert_eq(hud_slots[2].state, &"ready")
	assert_true(session.command_engineer_drone(player))

func test_real_hud_refreshes_after_binding_and_overlays_all_input_labels() -> void:
	var player := await _player(ENGENHEIRA, &"guardian")
	var hud := HUD_SCENE.instantiate() as Control
	add_child_autofree(hud)
	await get_tree().process_frame
	hud._bind_player(player)
	hud._refresh_ability_slots()
	assert_eq(hud._ability_slots.size(), 3)
	assert_eq(hud._ability_slots[0]._key_label.text, "Q")
	assert_eq(hud._ability_slots[1]._key_label.text, "E")
	assert_eq(hud._ability_slots[2]._key_label.text, "Shift")
	for slot in hud._ability_slots:
		assert_eq(slot.size, Vector2(38, 38))
		assert_true(slot._key_label.get_parent() == slot)
		assert_true(slot._key_label.position.x >= 0.0)
		assert_true(slot._key_label.position.y >= 0.0)

func test_hud_approved_layout_contract_is_deterministic() -> void:
	var hud := HUD_SCENE.instantiate() as Control
	add_child_autofree(hud)
	await get_tree().process_frame
	var abilities := hud._ability_slots[0].get_parent() as HBoxContainer
	var slot: Control = hud._ability_slots[0]
	assert_eq(slot.SLOT_SIZE, 38.0)
	assert_eq(slot.ICON_SIZE, 32.0)
	assert_eq(slot.ICON_MARGIN, 3.0)
	assert_eq(abilities.custom_minimum_size, Vector2(122, 38))
	assert_eq(abilities.get_theme_constant("separation"), 4)
	assert_eq(abilities.offset_right, -8.0)
	assert_eq(abilities.offset_bottom, -8.0)
	assert_eq(abilities.offset_left, -130.0)
	assert_eq(abilities.offset_top, -46.0)
	for index in 3:
		assert_eq(hud._ability_slots[index].position, Vector2(index * 42, 0))

func test_hud_builds_exactly_three_compact_slots_with_overlaid_keys() -> void:
	var hud := HUD_SCENE.instantiate() as Control
	add_child_autofree(hud)
	await get_tree().process_frame
	if not hud.has_method(&"_build"):
		fail_test("HUD nao carregou o script de producao")
		return
	assert_eq(hud._ability_slots.size(), 3)
	for slot in hud._ability_slots:
		assert_eq(slot.size, Vector2(38, 38))
		assert_eq(slot.get_child_count(), 1)
		assert_true(slot.get_child(0) is Label)
	assert_eq(hud._ability_slots[0].get_child(0).text, "")

func test_hud_mapping_comes_from_ship_and_character_loadout() -> void:
	var player := await _player(RASTREADORA, &"hacker")
	var slots := player.get_ability_hud_slots()
	assert_eq(slots.size(), 3)
	assert_eq(slots[0].key, &"Q")
	assert_eq(slots[0].ability_id, RASTREADORA.ability_q)
	assert_eq(slots[1].ability_id, &"hacker_overdrive")
	assert_eq(slots[2].ability_id, &"interceptadora_blink")

func test_tint_follows_character_and_neutral_fallback_is_safe() -> void:
	var player := await _player(RASTREADORA, &"guardian")
	var guardian_tint: Color = player.get_ability_hud_slots()[1].tint
	assert_true(guardian_tint.is_equal_approx(Color("B985D6")))
	player.character = null
	assert_true(player.get_ability_hud_slots()[1].tint.is_equal_approx(Color("EEF1F6")))

func test_cooldown_ratio_and_disabled_passive_states_are_real() -> void:
	var player := await _player(RASTREADORA, &"guardian")
	player._ability_e_cd = 2.0
	player._ability_e_cd_duration = 4.0
	var slots := player.get_ability_hud_slots()
	assert_eq(slots[1].state, &"cooldown")
	assert_eq(slots[1].cooldown_ratio, 0.5)
	assert_eq(slots[2].state, &"ready")

	var bruta := await _player(BRUTA, &"guardian")
	var bruta_slots := bruta.get_ability_hud_slots()
	assert_eq(bruta_slots[0].state, &"passive")
	assert_eq(bruta_slots[0].ability_id, &"")
	assert_eq(bruta_slots[2].ability_id, &"bruta_investida")

func test_bruta_q_does_not_present_an_active_input() -> void:
	var player := await _player(BRUTA)
	var q := player.get_ability_hud_slots()[0]
	assert_eq(q.key, &"Q")
	assert_eq(q.state, &"passive")
	assert_eq(q.ability_id, &"")

func test_player_reconfiguration_propagates_refs_and_hud_state() -> void:
	var player := await _player(RASTREADORA, &"hacker")
	assert_eq(player.character.id, &"hacker")
	assert_eq(player.get_ability_hud_slots()[1].ability_id, &"hacker_overdrive")
	assert_true(player.configure_selection(BRUTA, &"chronomancer"))
	assert_eq(player.ship, BRUTA)
	assert_eq(player.character.id, &"chronomancer")
	assert_eq(player.get_ability_hud_slots()[0].state, &"passive")
	assert_eq(player.get_ability_hud_slots()[1].ability_id, &"time_warp")
	assert_eq(player.get_ability_hud_slots()[2].ability_id, &"bruta_investida")

func _render_hud_slots(slot_configs: Array) -> Image:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(180, 100)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	add_child_autofree(viewport)
	var clear := ColorRect.new()
	clear.color = Color(0.2, 0.23, 0.28, 1.0)
	clear.size = Vector2(180, 100)
	viewport.add_child(clear)
	var hud := HUD_SCENE.instantiate() as Control
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	viewport.add_child(hud)
	await get_tree().process_frame
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hud.size = Vector2(180, 100)
	await get_tree().process_frame
	for index in mini(slot_configs.size(), hud._ability_slots.size()):
		var slot: Control = hud._ability_slots[index]
		slot.get_parent().remove_child(slot)
		hud.add_child(slot)
		slot.position = Vector2(10 + index * 42, 20)
		slot.configure(slot_configs[index])
	await get_tree().process_frame
	await get_tree().process_frame
	var texture := viewport.get_texture()
	if texture == null:
		assert_not_null(texture, "SubViewport nao produziu Texture2D rasterizada")
		return null
	var image := texture.get_image()
	if image == null:
		assert_not_null(image, "Texture2D do SubViewport nao produziu Image rasterizada")
		return null
	return image

func _assert_pixel_near(image: Image, point: Vector2i, expected: Color, tolerance := 2.0 / 255.0) -> void:
	var actual := image.get_pixelv(point)
	assert_true(absf(actual.r - expected.r) <= tolerance
		and absf(actual.g - expected.g) <= tolerance
		and absf(actual.b - expected.b) <= tolerance,
		"pixel %s inesperado: %s (esperado %s)" % [point, actual, expected])

func test_hud_headless_raster_contract_covers_all_states_and_approved_tints() -> void:
	var image := await _render_hud_slots([
		{"state": &"ready", "key": "Q", "icon_id": &"hacker_overdrive", "tint": Color("21D5DF")},
		{"state": &"cooldown", "key": "E", "icon_id": &"guardian_shield", "tint": Color("B985D6"), "cooldown_ratio": 0.5},
		{"state": &"disabled", "key": "Shift", "icon_id": &"time_warp", "tint": Color("D7A7FF")},
	])
	if image == null:
		return
	# Slots are positioned directly in the real HUD controls; each remains 38 px with 4 px gaps.
	var slot_y := 20
	var slot_x := [10, 52, 94]
	var background := Color(0.051, 0.3412, 0.3569)
	var badge := Color(0.0196, 0.0314, 0.0588)
	var wipe := Color(0.0314, 0.0431, 0.0745)
	# Ready: background and active cyan border; badge remains inside the slot.
	_assert_pixel_near(image, Vector2i(slot_x[0] + 19, slot_y + 20), background)
	_assert_pixel_near(image, Vector2i(slot_x[0], slot_y + 20), Color(0.2471, 0.2706, 0.3216))
	_assert_pixel_near(image, Vector2i(slot_x[0] + 3, slot_y + 4), badge)
	# Cooldown: purple border, badge, and wipe only over the lower half.
	_assert_pixel_near(image, Vector2i(slot_x[1], slot_y + 20), Color(0.0667, 0.0863, 0.1137))
	_assert_pixel_near(image, Vector2i(slot_x[1] + 3, slot_y + 4), badge)
	_assert_pixel_near(image, Vector2i(slot_x[1] + 19, slot_y + 8), Color(0.5961, 0.4275, 0.6902))
	_assert_pixel_near(image, Vector2i(slot_x[1] + 19, slot_y + 32), wipe)
	# Disabled: inactive border and dimmed icon area, with its badge still present.
	_assert_pixel_near(image, Vector2i(slot_x[2], slot_y + 20), Color(0.0941, 0.1176, 0.1569))
	_assert_pixel_near(image, Vector2i(slot_x[2] + 3, slot_y + 4), badge)
	_assert_pixel_near(image, Vector2i(slot_x[2] + 19, slot_y + 34), Color(0.0588, 0.0745, 0.102))

	var passive_image := await _render_hud_slots([
		{"state": &"passive", "key": "Q", "tint": Color("EEF1F6")},
		{"state": &"ready", "key": "E", "tint": Color("D7A7FF")},
		{"state": &"ready", "key": "Shift", "tint": Color("21D5DF")},
	])
	if passive_image == null:
		return
	# Passive uses the compositor's two lateral diamonds; neutral is the approved fallback tint input.
	var passive_border := Color(0.3412, 0.3725, 0.4353)
	_assert_pixel_near(passive_image, Vector2i(slot_x[0] + 11, slot_y + 20), passive_border)
	_assert_pixel_near(passive_image, Vector2i(slot_x[0] + 27, slot_y + 20), passive_border)
	_assert_pixel_near(passive_image, Vector2i(slot_x[1], slot_y + 20), Color(0.0667, 0.0863, 0.1137))
	_assert_pixel_near(passive_image, Vector2i(slot_x[2], slot_y + 20), Color(0.0941, 0.1176, 0.1569))
