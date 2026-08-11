class_name Session
extends Node
## Dono local de uma execucao. Nao e autoload: Main cria exatamente uma instancia.

signal run_completed

const ROOM_SCENE := preload("res://scenes/rooms/room.tscn")
const COMBAT_POOL := preload("res://resources/loot/combat_pool.tres")
const BOSS_POOL := preload("res://resources/loot/boss_pool.tres")
const ENGINEER_DEPLOYABLE := preload("res://scenes/deployables/engineer_deployable.tscn")
const ENGINEER_DEPLOYABLE_LIMIT := 3
const REGENTE_PREVIEW := preload("res://scenes/enemies/bosses/regente_dos_ecos.tscn")
const REGENTE_PREVIEW_META := &"sandbox_regente_preview"

@export var player_path: NodePath
@export var camera_path: NodePath
@export var room_host_path: NodePath
@export var hyperspace_path: NodePath

var run_state: RunState
var sector: SectorDef
var _player: Node2D
var _camera: Camera2D
var _room_host: Node
var _hyperspace: HyperspaceUI
var _active_room: Node
var _room_active := false
var _awaiting_boss_advance := false
var _room_generation := 0
var _has_started := false
var _engineer_deploy_sequence_by_player: Dictionary = {}

func _ready() -> void:
	add_to_group(&"session")
	_player = get_node_or_null(player_path) as Node2D
	_camera = get_node_or_null(camera_path) as Camera2D
	_room_host = get_node_or_null(room_host_path)
	_hyperspace = get_node_or_null(hyperspace_path) as HyperspaceUI
	if _player == null or _camera == null or _room_host == null or _hyperspace == null:
		push_error("Session requires Player, Camera2D, RoomHost and HyperspaceUI.")
		return
	_hyperspace.node_selected.connect(_on_node_selected)
	_hyperspace.sector_advance_requested.connect(_on_sector_advance_requested)

## Implanta por jogador e por sala. O Drone e singleton e nunca e removido pelo limite.
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
	var player_id := player.get_instance_id()
	var sequence := int(_engineer_deploy_sequence_by_player.get(player_id, 0))
	var next_kind := _next_engineer_kind(sequence, deployed_by_player)
	var selected_index := [
		EngineerDeployable.Kind.DRONE,
		EngineerDeployable.Kind.TRAP,
		EngineerDeployable.Kind.OVERCLOCK_STATION,
	].find(next_kind)
	_engineer_deploy_sequence_by_player[player_id] = (selected_index + 1) % 3
	if deployed_by_player.size() >= ENGINEER_DEPLOYABLE_LIMIT:
		var oldest_replaceable := _oldest_replaceable(deployed_by_player)
		if oldest_replaceable == null:
			return false
		container.remove_child(oldest_replaceable)
		oldest_replaceable.queue_free()
	var deployable := ENGINEER_DEPLOYABLE.instantiate() as EngineerDeployable
	container.add_child(deployable)
	var target := _engineer_target_for(player)
	deployable.global_position = player.global_position
	deployable.configure(next_kind, player, target)
	return true

func command_engineer_drone(player: Node2D) -> bool:
	if not _room_active or not is_instance_valid(_active_room) or player == null:
		return false
	var container := _active_room.get_node_or_null("Deployables") as Node2D
	if container == null:
		return false
	for child in container.get_children():
		var deployable := child as EngineerDeployable
		if deployable != null and deployable.deploying_player == player and deployable.kind == EngineerDeployable.Kind.DRONE:
			deployable.command_to(_engineer_target_for(player))
			return true
	return false

func _next_engineer_kind(sequence: int, deployed: Array[EngineerDeployable]) -> EngineerDeployable.Kind:
	const DEPLOY_ORDER := [
		EngineerDeployable.Kind.DRONE,
		EngineerDeployable.Kind.TRAP,
		EngineerDeployable.Kind.OVERCLOCK_STATION,
	]
	for offset in 3:
		var candidate := int(DEPLOY_ORDER[(sequence + offset) % DEPLOY_ORDER.size()])
		if candidate != EngineerDeployable.Kind.DRONE or not _has_engineer_drone(deployed):
			return candidate
	return EngineerDeployable.Kind.TRAP

func _has_engineer_drone(deployed: Array[EngineerDeployable]) -> bool:
	for deployable in deployed:
		if is_instance_valid(deployable) and deployable.kind == EngineerDeployable.Kind.DRONE:
			return true
	return false

func _oldest_replaceable(deployed: Array[EngineerDeployable]) -> EngineerDeployable:
	for deployable in deployed:
		if is_instance_valid(deployable) and deployable.kind != EngineerDeployable.Kind.DRONE:
			return deployable
	return null

## Mantem o contrato de sessao testavel com jogadores minimos, sem afetar Player real.
func _engineer_target_for(player: Node2D) -> Vector2:
	if player.has_method(&"get_engineer_deploy_target"):
		return player.call(&"get_engineer_deploy_target", EngineerDeployable.DEPLOY_RANGE)
	return player.global_position + Vector2.UP * EngineerDeployable.DEPLOY_RANGE

func start_new_run(seed_value: int, character_id: StringName = RunManager.DEFAULT_CHARACTER_ID) -> void:
	if _has_started:
		return
	if _player != null and _player.has_method(&"configure_character"):
		var current_character := _player.get("character") as CharacterDef
		if current_character == null or current_character.id != character_id:
			_player.call(&"configure_character", character_id)
	_has_started = true
	GameState.reset_for_new_run()
	RunManager.start_run(seed_value)
	run_state = RunState.new()
	run_state.run_seed = seed_value
	run_state.sector_index = 0
	sector = SectorGenerator.generate(seed_value, 0)
	_awaiting_boss_advance = false
	run_state.current_node_id = sector.start_node_id
	_enter_node(sector.start_node_id)

## Descarta todos os objetos e referencias pertencentes a execucao atual.
func reset_run() -> void:
	_dispose_active_room()
	_hyperspace.hide()
	run_state = null
	sector = null
	_room_active = false
	_awaiting_boss_advance = false
	_has_started = false
	_engineer_deploy_sequence_by_player.clear()

func _enter_node(node_id: int, is_revisit: bool = false) -> void:
	if _room_active or sector == null or sector.get_node(node_id) == null:
		return
	_room_generation += 1
	_engineer_deploy_sequence_by_player.clear()
	var room_generation := _room_generation
	run_state.current_node_id = node_id
	_room_active = true
	_hyperspace.hide()
	_hyperspace.refresh(run_state.completed_nodes, [], false)
	var node_def := sector.get_node(node_id)
	var room := ROOM_SCENE.instantiate()
	var controller := room.get_node("RoomController") as RoomController
	var chest := room.get_node("RewardChest") as RewardChest
	var room_def := _room_def_for(node_def, is_revisit)
	var room_bounds := room_def.get_bounds()
	controller.room_def = room_def
	_configure_room_geometry(room, room_bounds)
	chest.configure(_player, run_state.sector_index, node_id, 0, 0, _pool_for(node_def), run_state.get_offer(run_state.sector_index, node_id, 0, 0))
	chest.position = Vector2(room_def.size.x * 0.5, room_def.size.y - 52.0)
	controller.room_cleared.connect(_on_room_cleared.bind(node_def, room_generation))
	chest.offer_created.connect(run_state.save_offer)
	chest.offer_requested.connect(_open_offer)
	_room_host.add_child(room)
	_active_room = room
	_player.global_position = room_bounds.get_center()

func _configure_room_geometry(room: Node, bounds: Rect2) -> void:
	_player.call(&"set_room_bounds", bounds)
	_camera.limit_left = int(bounds.position.x)
	_camera.limit_top = int(bounds.position.y)
	_camera.limit_right = int(bounds.end.x)
	_camera.limit_bottom = int(bounds.end.y)
	_camera.global_position = bounds.get_center()
	var director := room.get_node_or_null("Directors/SpawnDirector")
	if director != null and director.has_method(&"set_room_bounds"):
		director.call(&"set_room_bounds", bounds)

func _on_room_cleared(node_def: SectorNode, room_generation: int) -> void:
	if room_generation != _room_generation or not _room_active:
		return
	var is_first_clear := not run_state.is_completed(run_state.sector_index, node_def.id)
	if is_first_clear and _player != null and _player.has_method(&"on_room_clear"):
		_player.call(&"on_room_clear")
	run_state.mark_completed(run_state.sector_index, node_def.id)
	_room_active = false
	# RewardChest is another listener of room_cleared. Finish this transition on
	# the next idle turn so its offer is persisted before the map is populated.
	call_deferred(&"_finish_room_clear", node_def, room_generation)

func _finish_room_clear(node_def: SectorNode, room_generation: int) -> void:
	if room_generation != _room_generation:
		return
	_persist_active_offer()
	if _is_phase_one_wave_node(node_def):
		# A Fase 1 aprovada nao possui chefe: a limpeza apos W5 avanca de
		# setor diretamente, sem armar o fluxo de chefe.
		_advance_after_boss()
		return
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
		var debris_container := _active_room.get_node_or_null("Debris")
		if debris_container != null:
			for debris in debris_container.get_children():
				debris.queue_free()
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
	GameState.reset_for_new_run()
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

## Cria uma unica Regente de previa fora do RoomRuntime para nao afetar a limpeza.
func sandbox_spawn_regente_preview() -> bool:
	if not _room_active or not is_instance_valid(_active_room) or not is_instance_valid(_player):
		return false
	var enemies := _active_room.get_node_or_null("Enemies") as Node2D
	var controller := _active_room.get_node_or_null("RoomController") as RoomController
	if enemies == null or controller == null or controller.room_def == null:
		return false
	for child in enemies.get_children():
		if child.get_meta(REGENTE_PREVIEW_META, false):
			return false
	var bounds := controller.room_def.get_bounds()
	var boss := REGENTE_PREVIEW.instantiate() as RegenteDosEcos
	if boss == null:
		return false
	boss.set_room_bounds(bounds)
	boss.set_room_cull_policy(controller.room_def.cull_policy)
	boss.global_position = _regente_preview_position(bounds)
	boss.set_meta(REGENTE_PREVIEW_META, true)
	enemies.add_child(boss)
	return true

func _regente_preview_position(bounds: Rect2) -> Vector2:
	var padding := Vector2(minf(96.0, bounds.size.x * 0.25), minf(96.0, bounds.size.y * 0.25))
	var safe_bounds := Rect2(bounds.position + padding, bounds.size - padding * 2.0)
	var desired := _player.global_position + Vector2(140.0, -72.0)
	return desired.clamp(safe_bounds.position, safe_bounds.end)

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
	if is_revisit:
		def.finite_spawn_count = 0
	elif node_def.room_profile == &"upper":
		def.configure_upper_waves()
	elif _is_phase_one_wave_node(node_def):
		def.configure_phase_one_waves()
	return def

func _is_phase_one_wave_node(node_def: SectorNode) -> bool:
	return run_state != null and run_state.sector_index == 0 and node_def.node_type == SectorNode.NodeType.OPENING

func _pool_for(node_def: SectorNode) -> ItemPoolDef:
	return BOSS_POOL if node_def.node_type == SectorNode.NodeType.BOSS else COMBAT_POOL
