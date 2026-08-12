extends GutTest

func test_stat_override_clamps_and_normalizes() -> void:
	var stats := StatBlock.new(StatCatalog.get_all())
	var player := SandboxPlayerDouble.new(stats, Inventory.new(stats, EffectDispatcher.new(autofree(Node.new()), [])))
	add_child_autofree(player)
	var sandbox := SandboxController.new(player, null)
	assert_true(sandbox.set_stat_override(&"aim_tier", 99.7))
	assert_eq(stats.get_stat(&"aim_tier"), StatCatalog.get_stat(&"aim_tier").default_max)
	assert_true(sandbox.set_stat_override(&"max_speed", 123.75))
	assert_eq(stats.get_stat(&"max_speed"), 123.75)
	assert_false(sandbox.set_stat_override(&"not_a_stat", 1.0))

func test_multiple_stat_overrides_and_negative_clamp() -> void:
	var stats := StatBlock.new(StatCatalog.get_all())
	var player := SandboxPlayerDouble.new(stats, null)
	add_child_autofree(player)
	var sandbox := SandboxController.new(player, null)
	var integer_def := StatCatalog.get_stat(&"aim_tier")
	assert_true(sandbox.set_stat_override(&"aim_tier", integer_def.default_min - 10.0))
	assert_eq(stats.get_stat(&"aim_tier"), integer_def.default_min)
	assert_true(sandbox.set_stat_override(&"luck", 2.25))
	assert_eq(stats.get_stat(&"luck"), 2.25)

func test_player_actions_and_reset_state_are_delegated() -> void:
	var player := SandboxPlayerDouble.new(null, null)
	var session: Session = SandboxSessionDouble.new()
	add_child_autofree(player)
	autofree(session)
	var sandbox := SandboxController.new(player, session)
	assert_true(sandbox.heal_player())
	assert_true(sandbox.set_god_mode(true))
	assert_true(player.healed)
	assert_true(player.invulnerable)
	assert_true(sandbox.clear_room())
	assert_true(session.cleared)
	assert_true(sandbox.warp(42, 1, 7, 2))
	assert_eq(session.warp_args, [42, 1, 7, 2])
	sandbox.set_targets(null, null)
	assert_false(sandbox.heal_player())
	assert_false(sandbox.set_god_mode(false))
	assert_false(sandbox.clear_room())
	assert_false(sandbox.warp(0, 0, 0, 0))

func test_f10_uses_physical_keycode() -> void:
	assert_true(InputMap.has_action(&"dev_sandbox_toggle"))
	var events := InputMap.action_get_events(&"dev_sandbox_toggle")
	assert_false(events.is_empty())
	var key_event := events[0] as InputEventKey
	assert_not_null(key_event)
	assert_eq(key_event.physical_keycode, KEY_F10)

func test_sandbox_canvas_layer_is_above_hyperspace_map() -> void:
	var sandbox_scene := load("res://scenes/ui/dev_sandbox.tscn") as PackedScene
	var main_scene := load("res://scenes/main/main.tscn") as PackedScene
	assert_not_null(sandbox_scene)
	assert_not_null(main_scene)
	var sandbox_layer := sandbox_scene.instantiate() as CanvasLayer
	var main := main_scene.instantiate()
	add_child_autofree(sandbox_layer)
	add_child_autofree(main)
	var hyperspace_layer := main.get_node("Session/HyperspaceUI") as CanvasLayer
	assert_eq(sandbox_layer.layer, 4)
	assert_eq(hyperspace_layer.layer, 3)
	assert_gt(sandbox_layer.layer, hyperspace_layer.layer)

func test_invalid_stat_and_seed_inputs_do_not_call_controller_or_mutate_state() -> void:
	var player := SandboxPlayerDouble.new(null, null)
	var session := SandboxSessionDouble.new()
	var sandbox_ui := SandboxUI.new()
	add_child_autofree(player)
	autofree(session)
	add_child_autofree(sandbox_ui)
	sandbox_ui._controller = SandboxController.new(player, session)
	sandbox_ui._status = Label.new()
	sandbox_ui._stat_id = OptionButton.new()
	sandbox_ui._stat_value = LineEdit.new()
	sandbox_ui._seed = LineEdit.new()
	add_child_autofree(sandbox_ui._status)
	add_child_autofree(sandbox_ui._stat_id)
	add_child_autofree(sandbox_ui._stat_value)
	add_child_autofree(sandbox_ui._seed)
	sandbox_ui._stat_id.add_item("max_health")
	sandbox_ui._stat_id.select(0)
	sandbox_ui._stat_value.text = "not-a-float"
	sandbox_ui._seed.text = "not-an-int"
	sandbox_ui._on_set_stat()
	sandbox_ui._on_warp()
	assert_eq(sandbox_ui._status.text, "Seed invalida.")
	assert_false(player.stat_override_called)
	assert_false(session.warp_called)
	assert_eq(player.stat_override_value, 0.0)
	assert_eq(session.warp_args, [])

func test_build_ui_populates_sorted_stat_and_item_dropdowns() -> void:
	var sandbox_ui := SandboxUI.new()
	add_child_autofree(sandbox_ui)
	sandbox_ui._build_ui()
	var expected_stats: Array[String] = []
	for stat: StatDef in StatCatalog.get_all():
		expected_stats.append(String(stat.id))
	expected_stats.sort()
	var actual_stats: Array[String] = []
	for index in sandbox_ui._stat_id.item_count:
		actual_stats.append(sandbox_ui._stat_id.get_item_text(index))
	assert_eq(actual_stats, expected_stats)
	assert_eq(sandbox_ui._stat_id.selected, 0 if not expected_stats.is_empty() else -1)
	var expected_items: Array[String] = []
	for item: ItemDef in ItemCatalog.get_all():
		expected_items.append(String(item.id))
	expected_items.sort()
	var actual_items: Array[String] = []
	for index in sandbox_ui._item_id.item_count:
		actual_items.append(sandbox_ui._item_id.get_item_text(index))
	assert_eq(actual_items, expected_items)
	assert_eq(sandbox_ui._item_id.selected, 0 if not expected_items.is_empty() else -1)
	assert_eq(sandbox_ui._node_type.item_count, 5)
	var expected_node_types := ["Opening", "Combat", "Boss", "Treasure", "Risk"]
	var expected_node_ids := [SectorNode.NodeType.OPENING, SectorNode.NodeType.COMBAT, SectorNode.NodeType.BOSS, SectorNode.NodeType.TREASURE, SectorNode.NodeType.RISK]
	for index in 5:
		assert_eq(sandbox_ui._node_type.get_item_text(index), expected_node_types[index])
		assert_eq(sandbox_ui._node_type.get_item_id(index), expected_node_ids[index])

func test_valid_stat_selection_sends_selected_id_and_value() -> void:
	var stats := StatBlock.new(StatCatalog.get_all())
	var player := SandboxPlayerDouble.new(stats, null)
	var sandbox_ui := SandboxUI.new()
	add_child_autofree(player)
	add_child_autofree(sandbox_ui)
	sandbox_ui._controller = SandboxController.new(player, null)
	sandbox_ui._build_ui()
	for index in sandbox_ui._stat_id.item_count:
		if sandbox_ui._stat_id.get_item_text(index) == "luck":
			sandbox_ui._stat_id.select(index)
			break
	sandbox_ui._stat_value.text = "2.25"
	sandbox_ui._on_set_stat()
	assert_eq(player.stat_override_id, &"luck")
	assert_eq(player.stat_override_value, 2.25)
	assert_eq(sandbox_ui._status.text, "Stat atualizado.")

func test_valid_item_actions_send_selected_id_and_amount() -> void:
	var player := SandboxPlayerDouble.new(null, null)
	var sandbox_ui := SandboxUI.new()
	add_child_autofree(player)
	add_child_autofree(sandbox_ui)
	sandbox_ui._controller = SandboxController.new(player, null)
	sandbox_ui._build_ui()
	sandbox_ui._item_id.select(0)
	sandbox_ui._amount.value = 3
	var selected_id := StringName(sandbox_ui._item_id.get_item_text(0))
	sandbox_ui._on_grant_item()
	assert_eq(player.grant_item_id, selected_id)
	assert_eq(player.grant_item_amount, 3)
	sandbox_ui._on_remove_item()
	assert_eq(player.remove_item_id, selected_id)
	assert_eq(player.remove_item_amount, 3)

func test_empty_dropdowns_do_not_call_controller_and_set_status() -> void:
	var player := SandboxPlayerDouble.new(null, null)
	var sandbox_ui := SandboxUI.new()
	add_child_autofree(player)
	add_child_autofree(sandbox_ui)
	sandbox_ui._controller = SandboxController.new(player, null)
	sandbox_ui._build_ui()
	sandbox_ui._stat_id.clear()
	sandbox_ui._item_id.clear()
	sandbox_ui._on_set_stat()
	assert_eq(sandbox_ui._status.text, "Nenhuma stat disponivel.")
	assert_false(player.stat_override_called)
	sandbox_ui._on_grant_item()
	assert_eq(sandbox_ui._status.text, "Nenhum item disponivel.")
	assert_eq(player.grant_item_calls, 0)
	sandbox_ui._on_remove_item()
	assert_eq(sandbox_ui._status.text, "Nenhum item disponivel.")
	assert_eq(player.remove_item_calls, 0)

func test_unselected_dropdowns_do_not_call_controller_and_set_status() -> void:
	var player := SandboxPlayerDouble.new(null, null)
	var sandbox_ui := SandboxUI.new()
	add_child_autofree(player)
	add_child_autofree(sandbox_ui)
	sandbox_ui._controller = SandboxController.new(player, null)
	sandbox_ui._build_ui()
	sandbox_ui._stat_id.select(-1)
	sandbox_ui._item_id.select(-1)
	sandbox_ui._on_set_stat()
	assert_eq(sandbox_ui._status.text, "Nenhuma stat disponivel.")
	sandbox_ui._on_grant_item()
	assert_eq(sandbox_ui._status.text, "Nenhum item disponivel.")
	assert_eq(player.grant_item_calls, 0)
	sandbox_ui._on_remove_item()
	assert_eq(player.remove_item_calls, 0)

func test_sandbox_overlay_pauses_and_restores_previous_state() -> void:
	var sandbox_ui := SandboxUI.new()
	add_child_autofree(sandbox_ui)
	assert_eq(sandbox_ui.process_mode, Node.PROCESS_MODE_ALWAYS)
	assert_false(get_tree().paused)
	sandbox_ui._open()
	assert_true(sandbox_ui.visible)
	assert_true(get_tree().paused)
	sandbox_ui._close()
	assert_false(sandbox_ui.visible)
	assert_false(get_tree().paused)
	get_tree().paused = true
	sandbox_ui._open()
	sandbox_ui._close()
	assert_true(get_tree().paused)
	get_tree().paused = false

func test_grant_respects_item_max_stacks() -> void:
	var stats := StatBlock.new(StatCatalog.get_all())
	var inventory := Inventory.new(stats, EffectDispatcher.new(autofree(Node.new()), []))
	var item := ItemDef.new()
	item.id = &"sandbox_item"
	item.max_stacks = 2
	item.effects = []
	item.modifiers = []
	var player := SandboxPlayerDouble.new(stats, inventory, item)
	add_child_autofree(player)
	var sandbox := SandboxController.new(player, null)
	assert_eq(sandbox.grant_item(&"sandbox_item", 5), 2)
	assert_eq(inventory.count(&"sandbox_item"), 2)
	assert_eq(sandbox.grant_item(&"sandbox_item", -4), 0)
	assert_eq(sandbox.remove_item(&"sandbox_item", 1), 1)
	assert_eq(inventory.count(&"sandbox_item"), 1)
	assert_eq(sandbox.remove_item(&"sandbox_item", 9), 1)
	assert_eq(inventory.count(&"sandbox_item"), 0)
	assert_eq(sandbox.remove_item(&"sandbox_item", 1), 0)

func test_stale_clear_callback_cannot_open_hyperspace_after_sandbox_warp() -> void:
	var session := Session.new()
	var player := preload("res://scenes/player/player.tscn").instantiate()
	var room_host := Node.new()
	var hyperspace := HyperspaceUI.new()
	player.name = "Player"
	room_host.name = "RoomHost"
	hyperspace.name = "HyperspaceUI"
	session.add_child(player)
	session.add_child(room_host)
	session.add_child(hyperspace)
	session.player_path = NodePath("Player")
	session.room_host_path = NodePath("RoomHost")
	session.hyperspace_path = NodePath("HyperspaceUI")
	add_child_autofree(session)
	session.run_state = RunState.new()
	session.run_state.run_seed = 1337
	session.run_state.sector_index = 0
	session.sector = SectorGenerator.generate(1337, 0)
	var target_node := session.sector.get_node(session.sector.start_node_id)
	session._enter_node(target_node.id)
	hyperspace.show()

	assert_true(session.sandbox_clear_room())
	assert_true(session.sandbox_warp(1337, 0, target_node.id, target_node.node_type))

	await get_tree().process_frame

	assert_true(session._room_active)
	assert_false(session._awaiting_boss_advance)
	assert_false(hyperspace.visible)

func test_regente_preview_button_delegates_to_session_and_disables_after_success() -> void:
	var session := SandboxSessionDouble.new()
	var sandbox_ui := SandboxUI.new()
	add_child_autofree(sandbox_ui)
	autofree(session)
	sandbox_ui._session = session
	sandbox_ui._controller = SandboxController.new(null, session)
	sandbox_ui._status = Label.new()
	sandbox_ui._regente_preview_button = Button.new()
	add_child_autofree(sandbox_ui._status)
	add_child_autofree(sandbox_ui._regente_preview_button)
	sandbox_ui._regente_preview_button.text = "Spawn Regente (Preview)"

	sandbox_ui._on_spawn_regente_preview()

	assert_eq(sandbox_ui._regente_preview_button.text, "Spawn Regente (Preview)")
	assert_eq(session.regente_preview_calls, 1)
	assert_true(sandbox_ui._regente_preview_button.disabled)
	assert_eq(sandbox_ui._status.text, "Regente posicionada para previa.")

func test_regente_preview_button_reenables_when_active_room_changes_or_preview_is_removed() -> void:
	var session := _make_regente_preview_session()
	var sandbox_ui := SandboxUI.new()
	add_child_autofree(sandbox_ui)
	sandbox_ui._session = session
	sandbox_ui._regente_preview_button = Button.new()
	add_child_autofree(sandbox_ui._regente_preview_button)

	assert_true(session.sandbox_spawn_regente_preview())
	sandbox_ui._sync_regente_preview_button()
	assert_true(sandbox_ui._regente_preview_button.disabled)
	var preview := _regente_preview_in(session._active_room)
	preview.queue_free()
	await get_tree().process_frame
	sandbox_ui._sync_regente_preview_button()
	assert_false(sandbox_ui._regente_preview_button.disabled)

	assert_true(session.sandbox_spawn_regente_preview())
	sandbox_ui._sync_regente_preview_button()
	assert_true(sandbox_ui._regente_preview_button.disabled)
	var target_node := session.sector.get_node(session.sector.start_node_id)
	assert_true(session.sandbox_warp(1337, 0, target_node.id, target_node.node_type))
	sandbox_ui._sync_regente_preview_button()
	assert_false(sandbox_ui._regente_preview_button.disabled)

func test_session_spawns_regente_preview_in_real_room_without_affecting_runtime_and_warp_discards_it() -> void:
	var session := _make_regente_preview_session()
	var room := session._active_room
	var controller := room.get_node("RoomController") as RoomController
	var enemies := room.get_node("Enemies") as Node2D
	var bounds := controller.room_def.get_bounds()
	var active_count := controller.runtime.active_enemy_count()

	assert_not_null(controller.runtime)
	assert_false(_has_regente_preview(enemies))
	assert_true(session.sandbox_spawn_regente_preview())
	var preview := _regente_preview_in(room) as RegenteDosEcos
	assert_not_null(preview)
	assert_true(preview.get_meta(&"sandbox_regente_preview", false))
	assert_eq(preview.get("_room_bounds"), bounds)
	assert_eq(preview.get("_room_cull_policy"), controller.room_def.cull_policy)
	assert_true(bounds.has_point(preview.global_position))
	assert_eq(controller.runtime.active_enemy_count(), active_count)
	assert_false(session.sandbox_spawn_regente_preview())

	var target_node := session.sector.get_node(session.sector.start_node_id)
	assert_true(session.sandbox_warp(1337, 0, target_node.id, target_node.node_type))
	assert_true(preview.is_queued_for_deletion())
	assert_false(_has_regente_preview(session._active_room.get_node("Enemies")))

func test_regente_preview_position_clamps_deterministically_at_room_edges() -> void:
	var session := _make_regente_preview_session()
	var bounds := (session._active_room.get_node("RoomController") as RoomController).room_def.get_bounds()
	var padding := Vector2(minf(96.0, bounds.size.x * 0.25), minf(96.0, bounds.size.y * 0.25))
	var safe_bounds := Rect2(bounds.position + padding, bounds.size - padding * 2.0)

	session._player.global_position = Vector2(-10000.0, -10000.0)
	assert_eq(session._regente_preview_position(bounds), safe_bounds.position)
	assert_eq(session._regente_preview_position(bounds), safe_bounds.position)
	session._player.global_position = Vector2(10000.0, 10000.0)
	assert_eq(session._regente_preview_position(bounds), safe_bounds.end)
	assert_eq(session._regente_preview_position(bounds), safe_bounds.end)

func test_normal_session_flow_does_not_spawn_regente_preview_without_sandbox_action() -> void:
	var session := _make_regente_preview_session()
	var enemies := session._active_room.get_node("Enemies") as Node2D

	assert_false(_has_regente_preview(enemies))
	assert_eq((session._active_room.get_node("RoomController") as RoomController).runtime.active_enemy_count(), 0)

func _make_regente_preview_session() -> Session:
	var session := Session.new()
	var player := preload("res://scenes/player/player.tscn").instantiate() as Node2D
	var camera := Camera2D.new()
	var room_host := Node2D.new()
	var hyperspace := HyperspaceUI.new()
	player.name = "Player"
	camera.name = "Camera2D"
	room_host.name = "RoomHost"
	hyperspace.name = "HyperspaceUI"
	session.add_child(player)
	session.add_child(camera)
	session.add_child(room_host)
	session.add_child(hyperspace)
	session.player_path = NodePath("Player")
	session.camera_path = NodePath("Camera2D")
	session.room_host_path = NodePath("RoomHost")
	session.hyperspace_path = NodePath("HyperspaceUI")
	add_child_autofree(session)
	session.run_state = RunState.new()
	session.run_state.run_seed = 1337
	session.run_state.sector_index = 0
	session.sector = SectorGenerator.generate(1337, 0)
	session._enter_node(session.sector.start_node_id)
	return session

func _regente_preview_in(room: Node) -> Node:
	var enemies := room.get_node_or_null("Enemies")
	if enemies == null:
		return null
	for child in enemies.get_children():
		if child.get_meta(&"sandbox_regente_preview", false):
			return child
	return null

func _has_regente_preview(enemies: Node) -> bool:
	if enemies == null:
		return false
	for child in enemies.get_children():
		if child.get_meta(&"sandbox_regente_preview", false):
			return true
	return false

class SandboxPlayerDouble extends Node:
	var stats: StatBlock
	var inventory: Inventory
	var item: ItemDef
	var healed := false
	var invulnerable := false
	var stat_override_called := false
	var stat_override_id: StringName
	var stat_override_value := 0.0
	var grant_item_id: StringName
	var grant_item_amount := 0
	var grant_item_calls := 0
	var remove_item_id: StringName
	var remove_item_amount := 0
	var remove_item_calls := 0
	func _init(new_stats: StatBlock, new_inventory: Inventory, new_item: ItemDef = null) -> void:
		stats = new_stats
		inventory = new_inventory
		item = new_item
	func sandbox_set_stat_override(stat_id: StringName, value: float) -> bool:
		stat_override_called = true
		stat_override_id = stat_id
		stat_override_value = value
		if not StatCatalog.has_stat(stat_id):
			return false
		var definition := StatCatalog.get_stat(stat_id)
		var normalized := clampf(value, definition.default_min, definition.default_max)
		if definition.is_integer:
			normalized = float(roundi(normalized))
		stats.set_base(stat_id, normalized)
		return true
	func sandbox_grant_item(item_id: StringName, amount: int) -> int:
		grant_item_id = item_id
		grant_item_amount = amount
		grant_item_calls += 1
		if item == null:
			return amount
		if item == null or item.id != item_id:
			return 0
		var count := 0
		for _index in maxi(0, amount):
			if not inventory.acquire(item):
				break
			count += 1
		return count
	func sandbox_remove_item(item_id: StringName, amount: int) -> int:
		remove_item_id = item_id
		remove_item_amount = amount
		remove_item_calls += 1
		if inventory == null:
			return amount
		var removed := 0
		for _index in maxi(0, amount):
			if inventory == null or inventory.count(item_id) <= 0:
				break
			inventory.remove_one(item_id)
			removed += 1
		return removed
	func sandbox_heal_full() -> void:
		healed = true
	func sandbox_set_invulnerable(enabled: bool) -> void:
		invulnerable = enabled

class SandboxSessionDouble extends Session:
	var cleared := false
	var warp_called := false
	var warp_args: Array = []
	var regente_preview_calls := 0
	func sandbox_clear_room() -> bool:
		cleared = true
		return true
	func sandbox_warp(seed_value: int, sector_index: int, node_id: int, node_type: int) -> bool:
		warp_called = true
		warp_args = [seed_value, sector_index, node_id, node_type]
		return true
	func sandbox_spawn_regente_preview() -> bool:
		regente_preview_calls += 1
		return true
