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
	sandbox_ui._stat_id = LineEdit.new()
	sandbox_ui._stat_value = LineEdit.new()
	sandbox_ui._seed = LineEdit.new()
	add_child_autofree(sandbox_ui._status)
	add_child_autofree(sandbox_ui._stat_id)
	add_child_autofree(sandbox_ui._stat_value)
	add_child_autofree(sandbox_ui._seed)
	sandbox_ui._stat_id.text = "max_health"
	sandbox_ui._stat_value.text = "not-a-float"
	sandbox_ui._seed.text = "not-an-int"
	sandbox_ui._on_set_stat()
	sandbox_ui._on_warp()
	assert_eq(sandbox_ui._status.text, "Seed invalida.")
	assert_false(player.stat_override_called)
	assert_false(session.warp_called)
	assert_eq(player.stat_override_value, 0.0)
	assert_eq(session.warp_args, [])

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

class SandboxPlayerDouble extends Node:
	var stats: StatBlock
	var inventory: Inventory
	var item: ItemDef
	var healed := false
	var invulnerable := false
	var stat_override_called := false
	var stat_override_value := 0.0
	func _init(new_stats: StatBlock, new_inventory: Inventory, new_item: ItemDef = null) -> void:
		stats = new_stats
		inventory = new_inventory
		item = new_item
	func sandbox_set_stat_override(stat_id: StringName, value: float) -> bool:
		stat_override_called = true
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
		if item == null or item.id != item_id:
			return 0
		var count := 0
		for _index in maxi(0, amount):
			if not inventory.acquire(item):
				break
			count += 1
		return count
	func sandbox_remove_item(item_id: StringName, amount: int) -> int:
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
	func sandbox_clear_room() -> bool:
		cleared = true
		return true
	func sandbox_warp(seed_value: int, sector_index: int, node_id: int, node_type: int) -> bool:
		warp_called = true
		warp_args = [seed_value, sector_index, node_id, node_type]
		return true
