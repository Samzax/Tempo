class_name RoomController
extends Node

signal room_cleared
signal combat_cleared
signal room_completed
signal exit_unlocked
signal spawn_warning_observed(wave_index: int, spawn_index: int, point: Vector2)

const SPAWN_WARNING_DURATION := 0.45

@export var room_def: RoomDef
@export var director_path: NodePath
@export var room_root_path: NodePath = ^".."

var runtime: RoomRuntime
var exit_is_unlocked: bool = false
var _director: Node
var _room_root: Node
var _observed_nodes: Array[Node] = []
var _observed_enemies: Array[Enemy] = []
var _enemy_tree_exit_callbacks: Dictionary = {}
var _is_observing_room := false
var _is_tearing_down := false

## Último FX de aviso criado; superfície de observação para testes de runtime.
var last_spawn_warning_fx: Node2D

const PROJECTILE_RUNTIME_META := &"room_runtime"
const TELEPORT_FX := preload("res://scenes/effects/teleport_fx.tscn")
const DEBRIS_SCENE := preload("res://scenes/world/debris.tscn")
const ENVIRONMENT_PRESENTATION := preload("res://scripts/rooms/environment_presentation.gd")

func _ready() -> void:
	add_to_group(&"room_controller")
	if room_def == null:
		push_error("RoomController requires a RoomDef.")
		return
	_director = get_node_or_null(director_path)
	if _director == null or not _director.has_method(&"start") or not _director.has_signal(&"enemy_spawned") or not _director.has_signal(&"spawns_finished") or not _director.has_signal(&"spawns_failed"):
		push_error("RoomController requires a SpawnDirector.")
		return
	_room_root = get_node_or_null(room_root_path)
	if _room_root == null:
		push_error("RoomController requires a room root.")
		return
	runtime = RoomRuntime.new()
	runtime.room_cleared.connect(_on_combat_cleared)
	var enemies := _find_local_group_member(&"enemies_container")
	if enemies != null and _director.has_method(&"set_enemy_container"):
		_director.call(&"set_enemy_container", enemies)
	_apply_environment_presentation()
	_start_room_observation()
	_director.connect(&"enemy_spawned", _on_enemy_spawned)
	_director.connect(&"spawns_finished", _on_spawns_finished)
	_director.connect(&"spawns_failed", _on_spawns_failed)
	if _director.has_signal(&"spawn_warning_started"):
		_director.connect(&"spawn_warning_started", _on_spawn_warning_started)
	runtime.start()
	# RoomController entra na arvore enquanto Room ainda esta anexando filhos;
	# o container irmao precisa ser criado no proximo idle.
	call_deferred(&"_spawn_initial_debris")
	var started: bool
	if room_def.has_waves() and _director.has_method(&"start_waves"):
		started = _director.call(&"start_waves", room_def.wave_specs)
	else:
		started = _director.call(&"start", room_def.finite_spawn_count)
	if not started:
		runtime.fail_start()

func _spawn_initial_debris() -> void:
	if not is_inside_tree() or room_def.initial_debris.is_empty() or _room_root == null:
		return
	var container := Node2D.new()
	container.name = &"Debris"
	_room_root.add_child(container)
	for spec in room_def.initial_debris:
		var debris := DEBRIS_SCENE.instantiate() as Debris
		debris.global_position = spec.position
		debris.size_class = int(spec.size_class)
		debris.drift_velocity = spec.drift_velocity
		debris.set_room_bounds(room_def.get_bounds())
		container.add_child(debris)

func _apply_environment_presentation() -> void:
	if room_def.environment_profile == &"default" or _room_root == null:
		return
	var host := _room_root.get_node_or_null("Environment")
	if host == null:
		host = _room_root
	if host.get_node_or_null("EnvironmentPresentation") != null:
		return
	var presentation := ENVIRONMENT_PRESENTATION.new()
	presentation.name = &"EnvironmentPresentation"
	presentation.environment_profile = room_def.environment_profile
	host.add_child(presentation)

func _on_enemy_spawned(enemy: Enemy) -> void:
	if _is_tearing_down or runtime == null or enemy == null:
		return
	enemy.set_room_cull_policy(room_def.cull_policy)
	enemy.set_meta(PROJECTILE_RUNTIME_META, runtime)
	runtime.register_spawn(enemy)
	enemy.resolved.connect(_on_enemy_resolved)
	var instance_id := enemy.get_instance_id()
	var tree_exit_callback := _on_enemy_tree_exited.bind(instance_id)
	_enemy_tree_exit_callbacks[instance_id] = tree_exit_callback
	_observed_enemies.append(enemy)
	enemy.tree_exited.connect(tree_exit_callback, CONNECT_ONE_SHOT)

func _on_spawns_finished() -> void:
	if _is_tearing_down or runtime == null:
		return
	runtime.mark_spawns_finished()

## Consome o contrato de aviso do diretor. O sinal espelhado mantem a janela
## de 0,45 s observavel mesmo em salas sem um conteiner global de efeitos.
func _on_spawn_warning_started(wave_index: int, spawn_index: int) -> void:
	var point := _spawn_point_for_warning(wave_index, spawn_index)
	# Prefira o host da propria sala. O fallback mantem cenas legadas cujos FX
	# vivem no container global do mundo.
	var effects := _find_local_group_member(&"effects")
	if effects == null:
		effects = get_tree().get_first_node_in_group(&"effects")
	if effects != null:
		var teleport_fx := TELEPORT_FX.instantiate() as Node2D
		teleport_fx.set(&"duration", SPAWN_WARNING_DURATION)
		teleport_fx.global_position = point
		effects.add_child(teleport_fx)
		last_spawn_warning_fx = teleport_fx
	# Quem observa o aviso pode inspecionar o FX ja anexado, como no contrato
	# legado de telegraph.
	spawn_warning_observed.emit(wave_index, spawn_index, point)

func _spawn_point_for_warning(wave_index: int, spawn_index: int) -> Vector2:
	if _director != null and _director.has_method(&"get_spawn_agenda"):
		for entry in _director.call(&"get_spawn_agenda"):
			if int(entry.wave_index) == wave_index and int(entry.spawn_index) == spawn_index:
				return entry.point
	return Vector2.ZERO

func _on_enemy_resolved(enemy: Enemy, reason: int) -> void:
	if _is_tearing_down or runtime == null:
		return
	runtime.resolve_enemy(enemy, reason)

func _on_enemy_tree_exited(instance_id: int) -> void:
	_enemy_tree_exit_callbacks.erase(instance_id)
	if _is_tearing_down or runtime == null:
		return
	runtime.resolve_enemy_id(instance_id)

func _on_spawns_failed(_reason: String) -> void:
	if _is_tearing_down or runtime == null:
		return
	runtime.fail_start()

## Produtores hostis devem registrar o projétil na sala que originou o disparo.
## A associação por runtime evita afetar projéteis de outras salas persistentes.
func register_enemy_projectile(projectile: Node) -> void:
	if projectile == null or runtime == null:
		return
	projectile.set_meta(PROJECTILE_RUNTIME_META, runtime)

## Encerra os spawns e elimina inimigos por dano para manter o ciclo normal da sala.
func sandbox_clear() -> bool:
	if _is_tearing_down or runtime == null or runtime.is_cleared():
		return false
	if _director != null and _director.has_method(&"stop"):
		_director.call(&"stop")
	runtime.mark_spawns_finished()
	for enemy in _observed_enemies.duplicate():
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		var info := DamageInfo.new()
		info.amount = enemy.health.health
		info.tags = [&"sandbox"]
		enemy.take_damage(info)
	return true

## Registra projeteis hostis quando entram nesta sala, inclusive apos seu inicio.
func _enter_tree() -> void:
	if _room_root != null:
		_start_room_observation()

func _exit_tree() -> void:
	_is_tearing_down = true
	if is_instance_valid(_director) and _director.has_method(&"stop"):
		_director.call(&"stop")
	_stop_room_observation()
	_disconnect_runtime_callbacks()

## Observa somente a subarvore desta sala. Projeteis adicionados a conteineres
## globais devem receber o runtime pela API explicita do produtor.
func _start_room_observation() -> void:
	if _is_observing_room or _room_root == null:
		return
	_is_observing_room = true
	_observe_subtree(_room_root)

func _stop_room_observation() -> void:
	for observed in _observed_nodes:
		if is_instance_valid(observed) and observed.child_entered_tree.is_connected(_on_local_child_entered_tree):
			observed.child_entered_tree.disconnect(_on_local_child_entered_tree)
	_observed_nodes.clear()
	_is_observing_room = false

func _disconnect_runtime_callbacks() -> void:
	if runtime != null and runtime.room_cleared.is_connected(_on_combat_cleared):
		runtime.room_cleared.disconnect(_on_combat_cleared)
	if is_instance_valid(_director):
		if _director.is_connected(&"enemy_spawned", _on_enemy_spawned):
			_director.disconnect(&"enemy_spawned", _on_enemy_spawned)
		if _director.is_connected(&"spawns_finished", _on_spawns_finished):
			_director.disconnect(&"spawns_finished", _on_spawns_finished)
		if _director.is_connected(&"spawns_failed", _on_spawns_failed):
			_director.disconnect(&"spawns_failed", _on_spawns_failed)
		if _director.has_signal(&"spawn_warning_started") and _director.is_connected(&"spawn_warning_started", _on_spawn_warning_started):
			_director.disconnect(&"spawn_warning_started", _on_spawn_warning_started)
	for enemy in _observed_enemies:
		if not is_instance_valid(enemy):
			continue
		if enemy.resolved.is_connected(_on_enemy_resolved):
			enemy.resolved.disconnect(_on_enemy_resolved)
		var callback: Callable = _enemy_tree_exit_callbacks.get(enemy.get_instance_id(), Callable())
		if not callback.is_null() and enemy.tree_exited.is_connected(callback):
			enemy.tree_exited.disconnect(callback)
	_observed_enemies.clear()
	_enemy_tree_exit_callbacks.clear()

func _observe_subtree(node: Node) -> void:
	if node == null:
		return
	if not node.child_entered_tree.is_connected(_on_local_child_entered_tree):
		node.child_entered_tree.connect(_on_local_child_entered_tree)
		_observed_nodes.append(node)
	_register_local_enemy_projectile(node)
	for child in node.get_children():
		_observe_subtree(child)

func _on_local_child_entered_tree(node: Node) -> void:
	if not _is_observing_room or _room_root == null or not _room_root.is_ancestor_of(node):
		return
	_observe_subtree(node)

func _register_local_enemy_projectile(projectile: Node) -> void:
	if not is_instance_valid(projectile) or not _room_root.is_ancestor_of(projectile):
		return
	if projectile.is_in_group(&"enemy_projectiles"):
		register_enemy_projectile(projectile)

## Busca somente na subarvore da sala; grupos globais de outra sala nao podem
## receber inimigos ou FX desta execucao.
func _find_local_group_member(group_name: StringName) -> Node:
	if _room_root == null:
		return null
	return _find_group_member_in_subtree(_room_root, group_name)

func _find_group_member_in_subtree(node: Node, group_name: StringName) -> Node:
	if node.is_in_group(group_name):
		return node
	for child in node.get_children():
		var found := _find_group_member_in_subtree(child, group_name)
		if found != null:
			return found
	return null

func _on_combat_cleared() -> void:
	if _is_tearing_down or exit_is_unlocked or not is_inside_tree():
		return
	combat_cleared.emit()
	# Track A preserva a conclusao e recompensa legadas; Track B podera reter
	# room_completed para um profile de transicao proprio.
	if room_def.transition_profile == &"default":
		_complete_room()

func _complete_room() -> void:
	if _is_tearing_down or exit_is_unlocked or not is_inside_tree():
		return
	for projectile in get_tree().get_nodes_in_group(&"enemy_projectiles"):
		if projectile is Node and projectile.get_meta(PROJECTILE_RUNTIME_META, null) == runtime:
			projectile.queue_free()
	exit_is_unlocked = true
	exit_unlocked.emit()
	room_completed.emit()
	room_cleared.emit()
