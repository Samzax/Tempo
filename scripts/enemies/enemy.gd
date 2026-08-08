class_name Enemy
extends CharacterBody2D
## Inimigo base, orientado a dados: o comportamento de movimento e os atributos
## vêm de valores exportados, então cada variação é o mesmo cenário com dados
## diferentes (perseguidor, serpente, descida reta...).

enum Movement { CHASE, DESCEND, SINE }
enum ResolveReason { DIED, CULLED }

signal resolved(enemy: Enemy, reason: int)

@export var max_health: float = 3.0
@export var speed: float = 60.0
@export var contact_damage: float = 1.0
@export var movement: Movement = Movement.CHASE
@export var score_value: int = 10
@export var tint: Color = Color.WHITE

const BURST_FX := preload("res://scenes/effects/burst_fx.tscn")

@onready var health: HealthComponent = $HealthComponent
@onready var sprite: Sprite2D = $Sprite2D

var _player: Node2D = null
var _effects: Node = null
var _phase: float = 0.0
var _resolved: bool = false
var _room_cull_policy: int = RoomDef.CullPolicy.DESPAWN_BOTTOM
var _room_bounds := Rect2(Vector2.ZERO, Vector2(720, 405))

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
	if _room_cull_policy == RoomDef.CullPolicy.DESPAWN_BOTTOM and global_position.y > _room_bounds.end.y + 40.0:
		_resolve(ResolveReason.CULLED)
		queue_free()

func set_room_cull_policy(policy: int) -> void:
	_room_cull_policy = policy

## Recebe os limites da sala antes de entrar em processamento.
func set_room_bounds(bounds: Rect2) -> void:
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		push_error("Enemy requires positive room bounds.")
		return
	_room_bounds = bounds

## Recebe dano dos projéteis do jogador.
func take_damage(info: DamageInfo) -> void:
	if info.trigger_depth > 3:
		return
	health.apply_damage(info)

func _on_died(fatal_info: DamageInfo) -> void:
	_resolve_death(fatal_info)
	queue_free()

## Resolve os efeitos compartilhados da morte. Variacoes que exibem uma animacao
## de morte podem chamar isto e adiar a liberacao do no.
func _resolve_death(fatal_info: DamageInfo) -> void:
	if _resolved:
		return
	GameState.score += score_value
	EventBus.enemy_died.emit(self, fatal_info)
	_spawn_burst()
	_resolve(ResolveReason.DIED)

func _resolve(reason: int) -> void:
	if _resolved:
		return
	_resolved = true
	resolved.emit(self, reason)

func _spawn_burst() -> void:
	if _effects == null:
		return
	var fx := BURST_FX.instantiate() as BurstFx
	if fx == null:
		return
	_effects.add_child(fx)
	fx.burst_at(global_position)
