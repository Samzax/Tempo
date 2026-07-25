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
	_director.connect(&"enemy_spawned", _on_enemy_spawned)
	_director.connect(&"spawns_finished", _on_spawns_finished)
	_director.connect(&"spawns_failed", _on_spawns_failed)
	runtime.start()
	if not _director.call(&"start", room_def.finite_spawn_count):
		runtime.fail_start()

func _on_enemy_spawned(enemy: Enemy) -> void:
	enemy.set_room_cull_policy(room_def.cull_policy)
	runtime.register_spawn(enemy)
	enemy.resolved.connect(_on_enemy_resolved)
	var instance_id := enemy.get_instance_id()
	enemy.tree_exited.connect(_on_enemy_tree_exited.bind(instance_id), CONNECT_ONE_SHOT)

func _on_spawns_finished() -> void:
	runtime.mark_spawns_finished()

func _on_enemy_resolved(enemy: Enemy, reason: int) -> void:
	runtime.resolve_enemy(enemy, reason)

func _on_enemy_tree_exited(instance_id: int) -> void:
	runtime.resolve_enemy_id(instance_id)

func _on_spawns_failed(_reason: String) -> void:
	runtime.fail_start()

func _on_room_cleared() -> void:
	if exit_is_unlocked:
		return
	for projectile in get_tree().get_nodes_in_group(&"enemy_projectiles"):
		if projectile is Node and _room_root.is_ancestor_of(projectile):
			projectile.queue_free()
	exit_is_unlocked = true
	exit_unlocked.emit()
	room_cleared.emit()
