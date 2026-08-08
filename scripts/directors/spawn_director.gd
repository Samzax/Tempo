extends Node
## Diretor de spawn simples: gera inimigos no topo em intervalos, alternando
## algumas variações a partir do mesmo cenário de inimigo (dados diferentes).

const ENEMY := preload("res://scenes/enemies/enemy.tscn")

signal enemy_spawned(enemy: Enemy)
signal spawns_finished
signal spawns_failed(reason: String)

enum State { IDLE, RUNNING, FINISHED }

@export var interval: float = 1.1

var _t: float = 0.0
var _container: Node = null
var _spawn_index: int = 0
var _spawn_limit: int = 0
var _spawns_emitted: int = 0
var _finished_emitted: bool = false
var _state: State = State.IDLE
var _room_bounds := Rect2(Vector2.ZERO, Vector2(720, 405))

func _ready() -> void:
	_container = get_tree().get_first_node_in_group("enemies_container")
	set_physics_process(false)

func start(spawn_limit: int) -> bool:
	if _state != State.IDLE:
		push_warning("SpawnDirector.start() ignored after its first invocation.")
		return false
	if spawn_limit > 0:
		_container = _get_enemies_container()
		if _container == null:
			_fail_spawns("SpawnDirector requires an enemies_container.")
			return false
	_state = State.RUNNING
	_spawn_limit = spawn_limit
	_spawns_emitted = 0
	_spawn_index = 0
	_finished_emitted = false
	_t = 0.0
	if _spawn_limit <= 0:
		_finish_spawns()
		return true
	set_physics_process(true)
	return true

func stop() -> void:
	set_physics_process(false)

## Configura a area horizontal de spawn e a geometria entregue aos inimigos.
func set_room_bounds(bounds: Rect2) -> void:
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		push_error("SpawnDirector requires positive room bounds.")
		return
	_room_bounds = bounds

func _physics_process(delta: float) -> void:
	if not is_physics_processing():
		return
	_t -= delta
	if _t <= 0.0:
		var enemy := _spawn()
		if enemy != null:
			_spawns_emitted += 1
			enemy_spawned.emit(enemy)
			if _spawns_emitted >= _spawn_limit:
				_finish_spawns()
				return
		_t = interval

func _spawn() -> Enemy:
	if not is_instance_valid(_container):
		_container = _get_enemies_container()
	if _container == null:
		_fail_spawns("SpawnDirector lost its enemies_container.")
		return null
	var e := ENEMY.instantiate() as Enemy
	if e == null:
		return null
	match _spawn_index % 3:
		0:  # perseguidor vermelho
			e.movement = Enemy.Movement.CHASE
			e.speed = 55.0
			e.max_health = 3
			e.tint = Color(1.0, 1.0, 1.0)
		1:  # descida rápida, tom âmbar
			e.movement = Enemy.Movement.DESCEND
			e.speed = 110.0
			e.max_health = 2
			e.tint = Color(1.0, 0.7, 0.4)
		2:  # serpente roxa
			e.movement = Enemy.Movement.SINE
			e.speed = 80.0
			e.max_health = 3
			e.tint = Color(0.75, 0.5, 1.0)
	_spawn_index += 1
	e.set_room_bounds(_room_bounds)
	e.global_position = Vector2(
		RunManager.rng.randf_range(_room_bounds.position.x + 24.0, _room_bounds.end.x - 24.0),
		_room_bounds.position.y - 16.0
	)
	_container.add_child(e)
	return e

func _finish_spawns() -> void:
	if _finished_emitted:
		return
	_finished_emitted = true
	_state = State.FINISHED
	stop()
	spawns_finished.emit()

func _fail_spawns(reason: String) -> void:
	_state = State.FINISHED
	stop()
	push_error(reason)
	spawns_failed.emit(reason)

func _get_enemies_container() -> Node:
	return get_tree().get_first_node_in_group("enemies_container")
