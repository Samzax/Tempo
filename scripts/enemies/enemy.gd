class_name Enemy
extends CharacterBody2D
## Inimigo base, orientado a dados: o comportamento de movimento e os atributos
## vêm de valores exportados, então cada variação é o mesmo cenário com dados
## diferentes (perseguidor, serpente, descida reta...).

enum Movement { CHASE, DESCEND, SINE }

@export var max_health: int = 3
@export var speed: float = 60.0
@export var contact_damage: int = 1
@export var movement: Movement = Movement.CHASE
@export var score_value: int = 10
@export var tint: Color = Color.WHITE

const BURST_FX := preload("res://scenes/effects/burst_fx.tscn")

@onready var health: HealthComponent = $HealthComponent
@onready var sprite: Sprite2D = $Sprite2D

var _player: Node2D = null
var _effects: Node = null
var _phase: float = 0.0
var _bounds: Vector2 = Vector2(
	float(ProjectSettings.get_setting("display/window/size/viewport_width", 480)),
	float(ProjectSettings.get_setting("display/window/size/viewport_height", 270))
)

func _ready() -> void:
	add_to_group("enemies")
	health.max_health = max_health
	health.reset()
	health.died.connect(_on_died)
	sprite.modulate = tint
	_player = get_tree().get_first_node_in_group("player")
	_effects = get_tree().get_first_node_in_group("effects")

func _physics_process(delta: float) -> void:
	_phase += delta
	match movement:
		Movement.CHASE:
			if is_instance_valid(_player):
				velocity = global_position.direction_to(_player.global_position) * speed
			else:
				velocity = Vector2.DOWN * speed
		Movement.DESCEND:
			velocity = Vector2.DOWN * speed
		Movement.SINE:
			velocity = Vector2(sin(_phase * 3.0) * speed, speed * 0.6)
	move_and_slide()
	if global_position.y > _bounds.y + 40.0:
		queue_free()

## Recebe dano dos projéteis do jogador.
func take_damage(amount: int) -> void:
	health.apply_damage(amount)

func _on_died() -> void:
	GameState.score += score_value
	EventBus.enemy_died.emit(self)
	_spawn_burst()
	queue_free()

func _spawn_burst() -> void:
	if _effects == null:
		return
	var fx := BURST_FX.instantiate()
	_effects.add_child(fx)
	fx.global_position = global_position
