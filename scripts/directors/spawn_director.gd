extends Node
## Diretor de spawn simples: gera inimigos no topo em intervalos, alternando
## algumas variações a partir do mesmo cenário de inimigo (dados diferentes).

const ENEMY := preload("res://scenes/enemies/enemy.tscn")

@export var interval: float = 1.1

var _t: float = 0.0
var _container: Node = null
var _spawn_index: int = 0
var _bounds: Vector2 = Vector2(
	float(ProjectSettings.get_setting("display/window/size/viewport_width", 480)),
	float(ProjectSettings.get_setting("display/window/size/viewport_height", 270))
)

func _ready() -> void:
	_container = get_tree().get_first_node_in_group("enemies_container")

func _process(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		_spawn()
		_t = interval

func _spawn() -> void:
	if _container == null:
		return
	var e := ENEMY.instantiate()
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
	e.global_position = Vector2(randf_range(24.0, _bounds.x - 24.0), -16.0)
	_container.add_child(e)
