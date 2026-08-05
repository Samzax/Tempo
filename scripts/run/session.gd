class_name Session
extends Node
## Dono local de uma execucao. Nao e autoload: Main cria exatamente uma instancia.

signal run_completed

const ROOM_SCENE := preload("res://scenes/rooms/room.tscn")
const COMBAT_POOL := preload("res://resources/loot/combat_pool.tres")
const BOSS_POOL := preload("res://resources/loot/boss_pool.tres")
const ENGINEER_DEPLOYABLE := preload("res://scenes/deployables/engineer_deployable.tscn")
const ENGINEER_DEPLOYABLE_LIMIT := 3

@export var player_path: NodePath
@export var room_host_path: NodePath
@export var hyperspace_path: NodePath

var run_state: RunState
var sector: SectorDef
var _player: Node2D
var _room_host: Node
var _hyperspace: HyperspaceUI
var _active_room: Node
var _room_active := false
var _awaiting_boss_advance := false
var _room_generation := 0
var _has_started := false
var _engineer_deploy_sequence := 0

func _ready() -> void:
	add_to_group(&"session")
	_player = get_node_or_null(player_path) as Node2D
	_room_host = get_node_or_null(room_host_path)
	_hyperspace = get_node_or_null(hyperspace_path) as HyperspaceUI
	if _player == null or _room_host == null or _hyperspace == null:
		push_error("Session requires Player, RoomHost and HyperspaceUI.")
		return
	_hyperspace.node_selected.connect(_on_node_selected)
	_hyperspace.sector_advance_requested.connect(_on_sector_advance_requested)

## Instancia a proxima unidade da Engenheira no container da sala e remove a mais antiga do mesmo jogador no limite.
func deploy_engineer_deployable(player: Node2D) -> bool:
	if not _room_active or not is_instance_valid(_active_room) or player == null:
		return false
	var container := _active_room.get_node_or_null("Deployables") as Node2D
	if container == null:
		return false
	var deployed_by_player: Array[EngineerDeployable] = []
	for child in container.get_children():
		var existing := child as EngineerDeployable
		if existing != null and existing.deploying_player == player:
			deployed_by_player.append(existing)
	while deployed_by_player.size() >= ENGINEER_DEPLOYABLE_LIMIT:
		var oldest := deployed_by_player.pop_front()
		container.remove_child(oldest)
		oldest.queue_free()
	var deployable := ENGINEER_DEPLOYABLE.instantiate() as EngineerDeployable
	container.add_child(deployable)
	deployable.global_position = player.global_position + Vector2.UP.rotated(_engineer_deploy_sequence * TAU / 3.0) * 20.0
	deployable.configure(_engineer_deploy_sequence % 3, player)
	_engineer_deploy_sequence += 1
	return true

func start_new_run(seed_value: int, character_id: StringName = RunManager.DEFAULT_CHARACTER_ID) -> void:
	if _has_started:
		return
	if _player != null and _player.has_method(&"configure_character"):
		var current_character := _player.get("character") as CharacterDef
		if current_character == null or current_character.id != character_id:
			_player.call(&"configure_character", character_id)
	_has_started = true
	RunManager.start_run(seed_value)
	run_state = RunState.new()
	run_state.run_seed = seed_value
	run_state.sector_index = 0
	sector = SectorGenerator.generate(seed_value, 0)
	_awaiting_boss_advance = false
	run_state.current_node_id = sector.start_node_id
	_enter_node(sector.start_node_id)

func _enter_node(node_id: int, is_revisit: bool = false) -> void:
	if _room_active or sector == null or sector.get_node(node_id) == null:
		return
	_room_generation += 1
	var room_generation := _room_generation
	run_state.current_node_id = node_id
	_room_active = true
	_hyperspace.hide()
	_hyperspace.refresh(run_state.completed_nodes, [], false)
	var node_def := sector.get_node(node_id)
	var room := ROOM_SCENE.instantiate()
	var controller := room.get_node("RoomController") as RoomController
	var chest := room.get_node("RewardChest") as RewardChest
	controller.room_def = _room_def_for(node_def, is_revisit)
	chest.configure(_player, run_state.sector_index, node_id, 0, 0, _pool_for(node_def), run_state.get_offer(run_state.sector_index, node_id, 0, 0))
	controller.room_cleared.connect(_on_room_cleared.bind(node_def, room_generation))
	chest.offer_created.connect(run_state.save_offer)
	chest.offer_requested.connect(_open_offer)
	_room_host.add_child(room)
	_active_room = room
	_player.global_position = Vector2(240, 135)

func _on_room_cleared(node_def: SectorNode, room_generation: int) -> void:
	if room_generation != _room_generation or not _room_active:
		return
	run_state.mark_completed(run_state.sector_index, node_def.id)
	_room_active = false
	# RewardChest is another listener of room_cleared. Finish this transition on
	# the next idle turn so its offer is persisted before the map is populated.
	call_deferred(&"_finish_room_clear", node_def, room_generation)

func _finish_room_clear(node_def: SectorNode, room_generation: int) -> void:
	if room_generation != _room_generation:
		return
	_persist_active_offer()
	if node_def.node_type == SectorNode.NodeType.BOSS:
		_awaiting_boss_advance = true
		_hyperspace.present_sector_advance(sector, run_state.completed_nodes, run_state.sector_index >= 2)
	else:
		_show_next_nodes(node_def.id)

func _show_next_nodes(node_id: int) -> void:
	_hyperspace.present(sector, run_state.completed_nodes, _selectable_nodes(node_id), true)

func _on_node_selected(node_id: int) -> void:
	if _room_active or _awaiting_boss_advance or sector == null:
		return
	var current := run_state.current_node_id
	var is_revisit := node_id == current and _can_revisit_current()
	if not is_revisit and not sector.get_children(current).has(node_id):
		return
	_dispose_active_room()
	_enter_node(node_id, is_revisit)

func _unhandled_input(event: InputEvent) -> void:
	if not _has_started or run_state == null or _room_active or sector == null or _hyperspace.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		if _awaiting_boss_advance:
			_hyperspace.present_sector_advance(sector, run_state.completed_nodes, run_state.sector_index >= 2)
		else:
			_hyperspace.present(sector, run_state.completed_nodes, _selectable_nodes(run_state.current_node_id), true)
		get_viewport().set_input_as_handled()

func _selectable_nodes(node_id: int) -> Array[int]:
	var selectable := sector.get_children(node_id)
	if node_id == run_state.current_node_id and _can_revisit_current():
		selectable.append(node_id)
	return selectable

func _can_revisit_current() -> bool:
	return run_state != null and run_state.is_completed(run_state.sector_index, run_state.current_node_id) and run_state.has_unclaimed_offer(run_state.sector_index, run_state.current_node_id)

func _advance_after_boss() -> void:
	_dispose_active_room()
	if run_state.sector_index >= 2:
		_hyperspace.present(sector, run_state.completed_nodes, [], false)
		run_completed.emit()
		return
	run_state.sector_index += 1
	sector = SectorGenerator.generate(run_state.run_seed, run_state.sector_index)
	run_state.current_node_id = sector.start_node_id
	_enter_node(sector.start_node_id)

func _on_sector_advance_requested() -> void:
	if not _awaiting_boss_advance or _room_active or sector == null:
		return
	var current := sector.get_node(run_state.current_node_id)
	if current == null or current.node_type != SectorNode.NodeType.BOSS:
		return
	_awaiting_boss_advance = false
	_advance_after_boss()

func _dispose_active_room() -> void:
	_room_generation += 1
	_persist_active_offer()
	if is_instance_valid(_active_room):
		# Os deployables pertencem a sala; nao sobrevivem a troca de no nem ao fim da execucao.
		var deployables := _active_room.get_node_or_null("Deployables")
		if deployables != null:
			for deployable in deployables.get_children():
				deployable.queue_free()
		var director := _active_room.get_node_or_null("Directors/SpawnDirector")
		if director != null and director.has_method(&"stop"):
			director.call(&"stop")
		for enemy in _active_room.get_node("Enemies").get_children():
			enemy.queue_free()
		var controller := _active_room.get_node_or_null("RoomController") as RoomController
		var old_runtime := controller.runtime if controller != null else null
		if old_runtime != null:
			for projectile in get_tree().get_nodes_in_group(&"enemy_projectiles"):
				if projectile is Node and projectile.get_meta(&"room_runtime", null) == old_runtime:
					projectile.queue_free()
		_active_room.get_parent().remove_child(_active_room)
		_active_room.queue_free()
	_active_room = null

## Entrada validada para o overlay de sandbox. A sala anterior e descartada antes da nova Runtime existir.
func sandbox_warp(seed_value: int, sector_index: int, node_id: int, node_type: int) -> bool:
	if sector_index < 0 or sector_index > 2:
		return false
	var target_sector := SectorGenerator.generate(seed_value, sector_index)
	var target_node := target_sector.get_node(node_id)
	if target_node == null or target_node.node_type != node_type:
		return false
	_dispose_active_room()
	RunManager.start_run(seed_value)
	run_state = RunState.new()
	run_state.run_seed = seed_value
	run_state.sector_index = sector_index
	run_state.current_node_id = node_id
	sector = target_sector
	_room_active = false
	_awaiting_boss_advance = false
	_enter_node(node_id)
	return true

func sandbox_clear_room() -> bool:
	if not _room_active or not is_instance_valid(_active_room):
		return false
	var controller := _active_room.get_node_or_null("RoomController") as RoomController
	return controller != null and controller.sandbox_clear()

func _persist_active_offer() -> void:
	if not is_instance_valid(_active_room) or run_state == null:
		return
	var controller := _active_room.get_node_or_null("RoomController") as RoomController
	if controller != null and controller.runtime != null:
		run_state.save_offer(controller.runtime.reward_offer)

func _open_offer(offer: RewardOffer, player: Node) -> void:
	run_state.save_offer(offer)
	get_node("../UI/ItemChoice").open_offer(offer, player)

func _room_def_for(node_def: SectorNode, is_revisit: bool = false) -> RoomDef:
	var def := RoomDef.new()
	def.id = StringName(str(node_def.id))
	def.room_type = RoomDef.RoomType.BOSS if node_def.node_type == SectorNode.NodeType.BOSS else (RoomDef.RoomType.OPENING if node_def.node_type == SectorNode.NodeType.OPENING else RoomDef.RoomType.COMBAT)
	def.finite_spawn_count = 0 if is_revisit else 5
	return def

func _pool_for(node_def: SectorNode) -> ItemPoolDef:
	return BOSS_POOL if node_def.node_type == SectorNode.NodeType.BOSS else COMBAT_POOL
