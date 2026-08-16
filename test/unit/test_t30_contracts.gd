extends GutTest

const MAIN_SCENE := preload("res://scenes/main/main.tscn")
const ROOM_SCENE := preload("res://scenes/rooms/room.tscn")


class EscapeProbe:
	extends Node

	var escape_count := 0

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			escape_count += 1


func _topology_signature(sector: SectorDef) -> Array:
	# Node IDs are sector-local implementation details.  The signature only records
	# the layout and the layout of every outgoing edge.
	var result: Array = []
	for node in sector.nodes.values():
		var children: Array = []
		for child_id in node.children:
			var child := sector.get_node(child_id)
			children.append([child.column, child.row, child.node_type])
		children.sort_custom(func(a, b): return str(a) < str(b))
		result.append([node.column, node.row, node.node_type, children])
	result.sort_custom(func(a, b): return str(a) < str(b))
	return result


func _reaches(sector: SectorDef, current: int, target: int, seen: Dictionary = {}) -> bool:
	if current == target:
		return true
	if seen.has(current):
		return false
	seen[current] = true
	for child_id in sector.get_children(current):
		if _reaches(sector, child_id, target, seen.duplicate()):
			return true
	return false


func _map_position(sector: SectorDef, node_id: int) -> Vector2:
	var node := sector.get_node(node_id)
	var rows := [1, 2, 2, 1, 1]
	var row_count: int = rows[node.column]
	var row := 0 if row_count == 1 else node.row
	return Vector2(62.0 + node.column * 88.0, 135.0 + (row - (row_count - 1) * 0.5) * 66.0)


func _mouse_left(position: Vector2, source: CanvasItem = null) -> void:
	await get_tree().process_frame
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.position = position
	event.global_position = position
	if source != null and source.has_method(&"_gui_input"):
		source.call(&"_gui_input", event)
	get_viewport().push_input(event)
	var release := event.duplicate() as InputEventMouseButton
	release.pressed = false
	release.button_mask = 0
	if source != null and source.has_method(&"_gui_input"):
		source.call(&"_gui_input", release)
	get_viewport().push_input(release)
	await get_tree().process_frame


func _key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	get_viewport().push_input(event)
	var release := event.duplicate() as InputEventKey
	release.pressed = false
	get_viewport().push_input(release)
	await get_tree().process_frame


func _wait_for(condition: Callable, limit: int, message: String) -> bool:
	for _i in limit:
		if condition.call():
			return true
		await get_tree().process_frame
	assert_true(condition.call(), message)
	return condition.call()


func _wait_for_seconds(condition: Callable, timeout_seconds: float, message: String) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await get_tree().process_frame
	assert_true(condition.call(), message)
	return condition.call()


func _main() -> Node:
	var main := MAIN_SCENE.instantiate()
	add_child_autofree(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var menu := main.get_node("MainMenu") as MainMenu
	var ship_id: StringName = ShipCatalog.all()[0].id
	var character_id: StringName = CharacterDef.get_roster()[0].id
	menu.start_game_requested.emit(ship_id, character_id)
	await get_tree().process_frame
	return main


func _clear_active_room(session: Session) -> void:
	var room_host := session.get_node("RoomHost")
	assert_eq(room_host.get_child_count(), 1)
	var room := room_host.get_child(0)
	var controller := room.get_node("RoomController") as RoomController
	var runtime := controller.runtime
	assert_not_null(runtime)
	if runtime == null:
		return
	var map := session.get_node_or_null("HyperspaceUI/Map") as HyperspaceUI
	assert_not_null(map, "map absent")
	if map == null:
		return

	var director := room.get_node_or_null("Directors/SpawnDirector")
	assert_not_null(director, "room spawn director absent")
	if director == null:
		return
	director.stop()
	if runtime.state == RoomRuntime.State.CREATED:
		runtime.start()
	runtime.mark_spawns_finished()
	var all_enemies: Array[Node] = []
	var enemies_container := room.get_node_or_null("Enemies")
	if enemies_container != null:
		for child in enemies_container.get_children():
			all_enemies.append(child)
	for enemy in controller._observed_enemies:
		if not all_enemies.has(enemy):
			all_enemies.append(enemy)
	for node in get_tree().get_nodes_in_group(&"enemies"):
		if not all_enemies.has(node):
			all_enemies.append(node)

	for enemy in all_enemies:
		if not is_instance_valid(enemy):
			continue
		runtime.resolve_enemy(enemy, 0)
		enemy.queue_free()

	var active_ids := runtime._active_enemies.keys().duplicate()
	for active_id in active_ids:
		runtime.resolve_enemy_id(active_id)
	assert_eq(runtime.active_enemy_count(), 0)
	assert_true(runtime.is_cleared())
	assert_true(controller.exit_is_unlocked)

	await get_tree().process_frame
	await get_tree().process_frame

	assert_true(await _wait_for(func() -> bool: return map.visible, 20, "room clear did not present the map"))


func _resolve_sector3_core_room(session: Session) -> void:
	var room := session.get_node("RoomHost").get_child(0)
	var controller := room.get_node("RoomController") as RoomController
	var runtime := controller.runtime
	var director := room.get_node("Directors/SpawnDirector")
	director.stop()
	if runtime.state == RoomRuntime.State.CREATED:
		runtime.start()
	runtime.mark_spawns_finished()
	for enemy in controller._observed_enemies.duplicate():
		if is_instance_valid(enemy):
			runtime.resolve_enemy(enemy, 0)
			enemy.queue_free()
	for active_id in runtime._active_enemies.keys().duplicate():
		runtime.resolve_enemy_id(active_id)
	assert_eq(runtime.active_enemy_count(), 0)
	assert_eq(controller._sector3_core._state, Sector3CorePresentation.State.ACTIVATABLE)
	controller._sector3_core._begin_channel()
	var chest := room.get_node("RewardChest") as RewardChest
	assert_true(await _wait_for_seconds(func() -> bool: return controller._sector3_core._state == Sector3CorePresentation.State.OFFER_PENDING and chest.current_offer() != null, 2.0, "core offer did not open"))
	var offer := chest.current_offer()
	assert_not_null(offer)
	var choice := session.get_node("../UI/ItemChoice") as ItemChoice
	assert_not_null(choice)
	assert_true(choice.visible)
	assert_eq(choice._offer, offer)
	choice._refuse()
	assert_true(await _wait_for_seconds(func() -> bool: return session.run_state.current_node_id == 6 and session.get_node("RoomHost").get_child_count() == 1, 2.0, "core sequence did not enter N6"))


func _select_next(session: Session, map: HyperspaceUI) -> void:
	var next_nodes := session.sector.get_children(session.run_state.current_node_id)
	assert_gt(next_nodes.size(), 0)
	await _mouse_left(_map_position(session.sector, next_nodes[0]), map)


func _finish_sector(session: Session, map: HyperspaceUI) -> void:
	for _step in 5:
		if session.sector.get_node(session.run_state.current_node_id).node_type == SectorNode.NodeType.BOSS:
			await _clear_active_room(session)
			return
		await _clear_active_room(session)
		await _select_next(session, map)
	assert_true(false, "sector did not reach its boss within 5 transitions")


func test_sector_dag_reaches_every_node_from_start_and_boss_from_every_node() -> void:
	var sector := SectorGenerator.generate(314159, 0)
	var boss_id := 6
	assert_eq(sector.nodes.size(), 7)
	var columns: Dictionary = {}
	var edge_count := 0
	for node in sector.nodes.values():
		columns[node.column] = true
		if node.node_type == SectorNode.NodeType.BOSS:
			boss_id = node.id
		assert_lte(node.children.size(), 2)
		for child_id in node.children:
			var child := sector.get_node(child_id)
			assert_not_null(child)
			assert_gt(child.column, node.column)
			edge_count += 1
	assert_eq(columns.size(), 5)
	assert_eq(edge_count, 3)
	assert_eq(sector.get_node(sector.start_node_id).column, 0)
	assert_eq(sector.get_node(boss_id).column, 4)
	assert_eq(sector.nodes.values().filter(func(node: SectorNode) -> bool: return node.node_type == SectorNode.NodeType.BOSS).size(), 1)
	assert_ne(boss_id, -1)
	for node_id in [0, 1, 3, 6]:
		assert_true(_reaches(sector, sector.start_node_id, node_id), "route must reach node %s" % node_id)
	for node_id in [2, 4, 5]:
		assert_false(_reaches(sector, sector.start_node_id, node_id), "disconnected node %s must not be reachable" % node_id)


func test_fixed_seed_sector_set_has_one_stable_normalized_topology() -> void:
	var signatures: Dictionary = {}
	for seed in range(10101, 10131):
		signatures[str(_topology_signature(SectorGenerator.generate(seed, 0)))] = true
	assert_eq(signatures.size(), 1)


func test_session_starts_explicitly_transitions_once_and_preserves_player() -> void:
	var main := await _main()
	var session := main.get_node("Session") as Session
	var map := main.get_node("Session/HyperspaceUI/Map") as HyperspaceUI
	var player: Node = main.get_node("World/Player")
	var room_host: Node = session.get_node("RoomHost")
	assert_not_null(session.run_state)
	assert_eq(room_host.get_child_count(), 1)
	assert_false(map.visible)
	assert_eq(map.node_selected.get_connections().size(), 1)

	var hp: int = player.health.health
	player.health.health = hp - HealthUnits.from_hp(1.0)
	var luck: float = player.get_luck()
	var max_speed: float = player._stats.get_stat(&"max_speed")
	var blink_ratio: float = player.blink_cooldown_ratio()
	var item: ItemDef = ItemCatalog.get_item(&"convergencia")
	assert_true(player.acquire_item(item))
	assert_false(player.can_acquire_item(item))
	assert_eq(player._inventory.count(item.id), 1)
	var first_room := room_host.get_child(0)

	await _clear_active_room(session)
	assert_eq(session.run_state.sector_index, 0)
	assert_eq(session.run_state.current_node_id, session.sector.start_node_id)
	assert_false(session._awaiting_boss_advance)
	assert_true(map.visible)
	assert_eq(room_host.get_child_count(), 1)
	assert_same(room_host.get_child(0), first_room, "N0 remains available until N1 is selected")
	assert_true(is_instance_valid(first_room))
	assert_eq(session.sector.get_node(session.run_state.current_node_id).node_type, SectorNode.NodeType.OPENING)
	assert_eq(session.sector.get_children(session.run_state.current_node_id), [1])
	assert_eq(session.run_state.sector_index, 0)
	assert_eq((room_host.get_child(0).get_node("RoomController") as RoomController).room_def.room_type, RoomDef.RoomType.OPENING)
	assert_same(main.get_node("World/Player"), player)
	assert_eq(player.health.health, hp - HealthUnits.from_hp(1.0))
	assert_eq(player.get_luck(), luck)
	assert_eq(player._stats.get_stat(&"max_speed"), max_speed)
	assert_eq(player.blink_cooldown_ratio(), blink_ratio)
	assert_eq(player._inventory.count(item.id), 1)
	assert_false(player.can_acquire_item(item))


func test_hyperspace_uses_input_pipeline_without_pausing_and_only_selects_presented_children() -> void:
	var ui := HyperspaceUI.new()
	add_child_autofree(ui)
	await get_tree().process_frame
	var sector := SectorGenerator.generate(7, 0)
	var selectable := sector.get_children(sector.start_node_id)
	ui.present(sector, {}, selectable, true)
	assert_true(ui.visible)
	assert_eq(get_viewport().get_visible_rect().size, Vector2(720, 405))
	assert_false(get_tree().paused)
	watch_signals(ui)
	await _mouse_left(Vector2.ZERO)
	for _i in 2:
		await get_tree().process_frame
	assert_signal_not_emitted(ui, &"node_selected")
	await _mouse_left(_map_position(sector, selectable[0]), ui)
	for _i in 2: await get_tree().process_frame
	assert_signal_emitted(ui, &"node_selected")
	await _key(KEY_RIGHT)
	await _key(KEY_ENTER)
	for _i in 2: await get_tree().process_frame
	assert_signal_emit_count(ui, &"node_selected", 2)
	await _key(KEY_ESCAPE)
	for _i in 2:
		await get_tree().process_frame
	assert_false(ui.visible)
	await _key(KEY_M)
	for _i in 2:
		await get_tree().process_frame
	assert_false(ui.visible)
	assert_false(get_tree().paused)
	ui.present_sector_advance(sector, {}, false)
	await _key(KEY_ESCAPE)
	for _i in 2:
		await get_tree().process_frame
	assert_false(ui.visible)
	assert_false(get_tree().paused)
	ui.present_sector_advance(sector, {}, false)
	assert_true(ui.visible)
	await _key(KEY_ESCAPE)
	for _i in 2:
		await get_tree().process_frame
	assert_false(ui.visible)
	ui.present_sector_advance(sector, {}, false)
	await _key(KEY_ENTER)
	await _key(KEY_ENTER)
	for _i in 2:
		await get_tree().process_frame
	assert_signal_emit_count(ui, &"sector_advance_requested", 1)


func test_boot_without_start_keeps_hud_hidden_and_session_uninitialized() -> void:
	var main := MAIN_SCENE.instantiate()
	add_child_autofree(main)
	await get_tree().process_frame

	var hud := main.get_node("UI/HUD") as Control
	var session := main.get_node("Session") as Session
	assert_false(hud.visible)
	assert_null(session.run_state)


func test_invisible_hyperspace_does_not_consume_escape() -> void:
	var ui := HyperspaceUI.new()
	var probe := EscapeProbe.new()
	add_child_autofree(ui)
	add_child_autofree(probe)
	await get_tree().process_frame

	assert_false(ui.visible)
	await _key(KEY_ESCAPE)
	assert_eq(probe.escape_count, 1)


func test_invisible_hud_does_not_poll_or_trigger_game_over() -> void:
	var main := MAIN_SCENE.instantiate()
	add_child_autofree(main)
	await get_tree().process_frame

	var hud := main.get_node("UI/HUD") as Control
	var game_state := get_node_or_null("/root/GameState")
	assert_not_null(game_state, "GameState autoload absent")
	if game_state == null:
		return
	var score_text: String = hud._score.text
	var lives_text: String = hud._lives.text
	var prior_score: int = game_state.score
	var prior_lives: int = game_state.player_lives
	game_state.score = prior_score + 100
	game_state.player_lives = 0
	await get_tree().process_frame

	assert_false(hud.visible)
	assert_eq(hud._score.text, score_text)
	assert_eq(hud._lives.text, lives_text)
	assert_false(hud._game_over.visible)
	assert_false(get_tree().paused)
	game_state.score = prior_score
	game_state.player_lives = prior_lives


func test_single_sector_flow_reaches_core_and_final_boss_then_completes_once() -> void:
	var main := await _main()
	var session := main.get_node("Session") as Session
	var map := main.get_node("Session/HyperspaceUI/Map") as HyperspaceUI
	var player := main.get_node("World/Player") as Node
	watch_signals(session)
	var n0_room := session.get_node("RoomHost").get_child(0)
	await _clear_active_room(session)
	assert_eq(session.run_state.sector_index, 0)
	assert_false(session._awaiting_boss_advance)
	assert_eq(session.get_node("RoomHost").get_child_count(), 1)
	assert_true(map.visible)
	assert_same(session.get_node("RoomHost").get_child(0), n0_room)
	assert_eq(session.sector.get_children(0), [1])
	await _mouse_left(_map_position(session.sector, 1), map)
	assert_eq(session.run_state.sector_index, 0)
	assert_eq(session.run_state.current_node_id, 1)
	assert_false(map.visible)
	assert_ne(session.get_node("RoomHost").get_child(0), n0_room)
	assert_false(is_instance_valid(n0_room))
	assert_same(main.get_node("World/Player"), player)

	await _clear_active_room(session)
	assert_eq(session.run_state.sector_index, 0)
	assert_eq(session.run_state.current_node_id, 1)
	assert_true(map.visible)
	assert_eq(session.sector.get_children(1), [3])
	await _mouse_left(_map_position(session.sector, 3), map)
	assert_eq(session.run_state.sector_index, 0)
	assert_eq(session.run_state.current_node_id, 3)
	assert_false(map.visible)
	await _resolve_sector3_core_room(session)
	assert_eq(session.run_state.sector_index, 0)
	assert_eq(session.run_state.current_node_id, 6)
	assert_false(map.visible)

	await _clear_active_room(session)
	assert_true(session._awaiting_boss_advance)
	assert_true(map.visible)
	assert_eq(session.run_state.sector_index, 0)
	assert_eq(session.run_state.current_node_id, 6)
	watch_signals(map)
	await _key(KEY_ESCAPE)
	assert_true(await _wait_for(func() -> bool: return not map.visible, 20, "final overlay map did not hide after Escape"))
	await _key(KEY_M)
	assert_true(await _wait_for(func() -> bool: return map.visible, 20, "map did not reopen after M"))
	await _key(KEY_ENTER)
	await _key(KEY_ENTER)
	assert_true(await _wait_for(func() -> bool: return not session._awaiting_boss_advance, 20, "final completion was not accepted"))
	assert_eq(session.run_state.sector_index, 0)
	assert_signal_emit_count(session, &"run_completed", 1)
	await _key(KEY_ENTER)
	await _key(KEY_M)
	await get_tree().process_frame
	assert_signal_emit_count(session, &"run_completed", 1)


func test_session_saves_chest_offer_immediately_and_room_reentry_reuses_identity() -> void:
	var main := await _main()
	var session := main.get_node("Session") as Session
	var room := session.get_node("RoomHost").get_child(0)
	var controller := room.get_node("RoomController") as RoomController
	var chest := room.get_node("RewardChest") as RewardChest
	assert_null(controller.runtime.reward_offer, "offer must not exist before room_cleared")
	var source_sector := session.run_state.sector_index
	var source_node := session.run_state.current_node_id
	controller.room_cleared.emit()
	var first := controller.runtime.reward_offer
	assert_not_null(first, "clear must unlock and create the offer immediately")
	assert_same(session.run_state.get_offer(source_sector, source_node, 0, 0), first)
	assert_true(await _wait_for(func() -> bool: return session.run_state.sector_index == 0, 20, "phase one clear did not advance sector index"))

	var reopened := ROOM_SCENE.instantiate()
	var reopened_controller := reopened.get_node("RoomController") as RoomController
	var reopened_chest := reopened.get_node("RewardChest") as RewardChest
	var reopened_def := RoomDef.new()
	reopened_def.finite_spawn_count = 0
	reopened_controller.room_def = reopened_def
	reopened_chest.configure(main.get_node("World/Player"), source_sector, source_node, 0, 0, preload("res://resources/loot/combat_pool.tres"), first)
	add_child_autofree(reopened)
	await get_tree().process_frame
	assert_same(reopened_controller.runtime.reward_offer, first)
	assert_same(session.run_state.get_offer(source_sector, source_node, 0, 0), reopened_controller.runtime.reward_offer)
	assert_same(first, reopened_controller.runtime.reward_offer)


func test_reward_chest_only_creates_offer_on_unlock_signal() -> void:
	var main := await _main()
	var session := main.get_node("Session") as Session
	var room := session.get_node("RoomHost").get_child(0)
	var controller := room.get_node("RoomController") as RoomController
	var chest := room.get_node("RewardChest") as RewardChest
	var player := main.get_node("World/Player") as Node
	chest.configure(player, 0, session.run_state.current_node_id, 0, 0, preload("res://resources/loot/combat_pool.tres"), null)
	watch_signals(chest)
	assert_null(controller.runtime.reward_offer)
	assert_signal_not_emitted(chest, &"offer_created")
	controller.room_cleared.emit()
	var offer := controller.runtime.reward_offer
	assert_not_null(offer)
	assert_signal_emitted(chest, &"offer_created")
	assert_true(await _wait_for(func() -> bool: return session.run_state.sector_index == 0, 20, "phase one clear did not advance sector index"))


func test_room_clear_releases_only_its_hostile_projectiles_and_preserves_ally() -> void:
	var main := await _main()
	var session := main.get_node("Session") as Session
	var room_a := session.get_node("RoomHost").get_child(0)
	var controller_a := room_a.get_node("RoomController") as RoomController
	var room_b := ROOM_SCENE.instantiate()
	var def_b := RoomDef.new()
	def_b.finite_spawn_count = 0
	room_b.get_node("RoomController").room_def = def_b
	main.add_child(room_b)
	await get_tree().process_frame
	var controller_b := room_b.get_node("RoomController") as RoomController
	var hostile_a := Node.new()
	var hostile_b := Node.new()
	var nested_hostile := Node.new()
	var nested := Node.new()
	var friendly := Node.new()
	main.get_node("World/Projectiles").add_child(friendly)
	for projectile in [hostile_a, hostile_b]:
		projectile.add_to_group(&"enemy_projectiles")
	nested_hostile.add_to_group(&"enemy_projectiles")
	room_a.add_child(hostile_a)
	room_a.add_child(nested)
	nested.add_child(nested_hostile)
	room_b.add_child(hostile_b)
	# Registration is recursive and synchronous: a descendant added before the
	# clear must be in the room's runtime set during this same turn.
	await _clear_active_room(session)
	await get_tree().process_frame
	assert_false(is_instance_valid(hostile_a))
	assert_false(is_instance_valid(nested_hostile))
	assert_true(is_instance_valid(hostile_b), "room A must not clear room B projectiles")
	assert_true(is_instance_valid(friendly))
	# Once the old room is disconnected, a later insertion in the other room is
	# not observed by its controller and cannot be cleared by room A.
	var after_disconnect := Node.new()
	after_disconnect.add_to_group(&"enemy_projectiles")
	room_b.add_child(after_disconnect)
	await get_tree().process_frame
	assert_true(is_instance_valid(after_disconnect))
	room_b.queue_free()


func test_room_clear_persists_offer_before_deferred_map_and_allows_current_revisit() -> void:
	var main := await _main()
	var session := main.get_node("Session") as Session
	var map := main.get_node("Session/HyperspaceUI/Map") as HyperspaceUI
	await _clear_active_room(session)
	assert_eq(session.run_state.sector_index, 0)
	var room := session.get_node("RoomHost").get_child(0)
	var controller := room.get_node("RoomController") as RoomController
	assert_not_null(controller.runtime.reward_offer)
	await _clear_active_room(session)
	# The map transition is deferred, but the chest listener has already created
	# and persisted the offer before _finish_room_clear populates choices.
	var offer: RewardOffer = controller.runtime.reward_offer
	assert_not_null(offer)
	assert_same(session.run_state.get_offer(session.run_state.sector_index, session.run_state.current_node_id, 0, 0), offer)
	await get_tree().process_frame
	assert_true(map.visible)
	assert_true(session._can_revisit_current(), "unclaimed offer allows current-node revisit")
	await _mouse_left(_map_position(session.sector, session.run_state.current_node_id), map)
	await get_tree().process_frame
	assert_eq(session.get_node("RoomHost").get_child_count(), 1)
	assert_same(session.get_node("RoomHost").get_child(0).get_node("RoomController").runtime.reward_offer, offer)


func test_session_revisits_current_completed_node_only_for_unclaimed_offer() -> void:
	var main := await _main()
	var session := main.get_node("Session") as Session
	var map := main.get_node("Session/HyperspaceUI/Map") as HyperspaceUI
	var room_host := session.get_node("RoomHost")
	await _clear_active_room(session)
	assert_eq(session.run_state.sector_index, 0)
	var room := room_host.get_child(0)
	var original_room := room
	var controller := room.get_node("RoomController") as RoomController
	await _clear_active_room(session)
	var offer := controller.runtime.reward_offer
	assert_not_null(offer)
	if offer == null:
		return
	var current := session.run_state.current_node_id
	assert_true(session._can_revisit_current())
	var arbitrary := -1
	for candidate in session.sector.nodes.keys():
		if candidate != current and not session.sector.get_children(current).has(candidate):
			arbitrary = candidate
			break
	assert_ne(arbitrary, -1)
	await _mouse_left(_map_position(session.sector, arbitrary), map)
	await get_tree().process_frame
	assert_eq(session.run_state.current_node_id, current, "arbitrary jumps must be blocked")
	assert_same(room_host.get_child(0), original_room)
	await _mouse_left(_map_position(session.sector, current), map)
	await get_tree().process_frame
	assert_eq(session.run_state.current_node_id, current)
	assert_eq(room_host.get_child_count(), 1)
	assert_ne(room_host.get_child(0), original_room, "revisit must create a new room")
	assert_eq(room_host.get_child(0).get_node("RoomController").room_def.finite_spawn_count, 0)
	assert_same(room_host.get_child(0).get_node("RoomController").runtime.reward_offer, offer)
	offer.claimed = true
	await _clear_active_room(session)
	assert_false(session._can_revisit_current(), "claimed offer blocks revisit")
	await _mouse_left(_map_position(session.sector, current), map)
	await get_tree().process_frame
	assert_eq(session.get_node("RoomHost").get_child_count(), 1)
	assert_true(offer.claimed)


func test_t30_smoke_loads_main_room_and_required_scripts_resources() -> void:
	assert_not_null(MAIN_SCENE)
	assert_not_null(ROOM_SCENE)
	for path in [
		"res://scripts/run/sector_generator.gd", "res://scripts/run/run_state.gd",
		"res://scripts/run/session.gd", "res://scripts/ui/hyperspace_ui.gd",
		"res://scripts/loot/reward_chest.gd", "res://resources/rooms/opening.tres"
	]:
		assert_not_null(load(path), path)
