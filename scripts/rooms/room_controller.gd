class_name RoomController
extends Node

signal room_cleared
signal exit_unlocked

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

const PROJECTILE_RUNTIME_META := &"room_runtime"

func _ready() -> void:
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
	runtime.room_cleared.connect(_on_room_cleared)
	_start_room_observation()
	_director.connect(&"enemy_spawned", _on_enemy_spawned)
	_director.connect(&"spawns_finished", _on_spawns_finished)
	_director.connect(&"spawns_failed", _on_spawns_failed)
	runtime.start()
	if not _director.call(&"start", room_def.finite_spawn_count):
		runtime.fail_start()

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

## Registra projeteis hostis quando entram nesta sala, inclusive apos seu inicio.
func _enter_tree() -> void:
	if _room_root != null:
		_start_room_observation()

func _exit_tree() -> void:
	_is_tearing_down = true
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
	if runtime != null and runtime.room_cleared.is_connected(_on_room_cleared):
		runtime.room_cleared.disconnect(_on_room_cleared)
	if is_instance_valid(_director):
		if _director.is_connected(&"enemy_spawned", _on_enemy_spawned):
			_director.disconnect(&"enemy_spawned", _on_enemy_spawned)
		if _director.is_connected(&"spawns_finished", _on_spawns_finished):
			_director.disconnect(&"spawns_finished", _on_spawns_finished)
		if _director.is_connected(&"spawns_failed", _on_spawns_failed):
			_director.disconnect(&"spawns_failed", _on_spawns_failed)
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

func _on_room_cleared() -> void:
	if _is_tearing_down or exit_is_unlocked or not is_inside_tree():
		return
	for projectile in get_tree().get_nodes_in_group(&"enemy_projectiles"):
		if projectile is Node and projectile.get_meta(PROJECTILE_RUNTIME_META, null) == runtime:
			projectile.queue_free()
	exit_is_unlocked = true
	exit_unlocked.emit()
	room_cleared.emit()
