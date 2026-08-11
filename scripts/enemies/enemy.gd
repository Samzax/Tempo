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
## Chefes modulares podem expor o reator como visual principal em vez de um
## Sprite2D de folha unica; inimigos legados continuam usando $Sprite2D.
@onready var sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D

var _player: Node2D = null
var _effects: Node = null
var _phase: float = 0.0
var _resolved: bool = false
var _room_cull_policy: int = RoomDef.CullPolicy.DESPAWN_BOTTOM
var _room_bounds := Rect2(Vector2.ZERO, Vector2(720, 405))
var _entry_inward := Vector2.DOWN
var _has_entered_room := false
## Estado público de duração restante para UI, efeitos e testes de comportamento.
var stun_remaining := 0.0

func _ready() -> void:
	add_to_group("enemies")
	if sprite == null:
		sprite = get_node_or_null("CoreReactor") as Sprite2D
	health.max_health = max_health
	health.reset()
	health.died.connect(_on_died)
	if sprite != null:
		sprite.modulate = tint
	_player = get_tree().get_first_node_in_group("player")
	_effects = get_tree().get_first_node_in_group("effects")

func _physics_process(delta: float) -> void:
	if _should_cull():
		_resolve(ResolveReason.CULLED)
		queue_free()
		return
	delta = _consume_stun_delta(delta)
	if delta <= 0.0:
		return
	_phase += delta
	match movement:
		Movement.CHASE:
			if is_instance_valid(_player):
				velocity = global_position.direction_to(_player.global_position) * speed
			else:
				velocity = _entry_inward * speed
		Movement.DESCEND:
			velocity = _entry_inward * speed
		Movement.SINE:
			velocity = _entry_inward * speed * 0.6 + _entry_inward.rotated(PI * 0.5) * sin(_phase * 3.0) * speed
	move_and_slide()
	if _room_bounds.grow(16.0).has_point(global_position):
		_has_entered_room = true
	if _should_cull():
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

func set_entry_inward(direction: Vector2) -> void:
	if direction == Vector2.ZERO:
		return
	_entry_inward = direction.normalized()

func _should_cull() -> bool:
	if _room_cull_policy == RoomDef.CullPolicy.NONE:
		return false
	if _room_cull_policy == RoomDef.CullPolicy.DESPAWN_BOTTOM:
		return global_position.y > _room_bounds.end.y + 40.0
	return _has_entered_room and not _room_bounds.grow(40.0).has_point(global_position)

## Atordoamento genérico: reaplicações apenas estendem a duração, nunca acumulam dano.
func apply_stun(duration: float) -> void:
	if not is_finite(duration) or duration <= 0.0 or _resolved:
		return
	stun_remaining = maxf(stun_remaining, duration)

func is_stunned() -> bool:
	return stun_remaining > 0.0

## Chamado pelas IAs derivadas antes de decidirem movimento ou ataques.
func _update_stun(delta: float) -> bool:
	if stun_remaining <= 0.0:
		return false
	return _consume_stun_delta(delta) <= 0.0

## Consome somente a parcela do frame coberta pelo stun e devolve o tempo que
## a IA ainda pode simular neste mesmo frame.
func _consume_stun_delta(delta: float) -> float:
	var frame_delta := maxf(delta, 0.0)
	if stun_remaining <= 0.0:
		return frame_delta
	var stunned_delta := minf(frame_delta, stun_remaining)
	stun_remaining = maxf(0.0, stun_remaining - stunned_delta)
	velocity = Vector2.ZERO
	return frame_delta - stunned_delta

## Recebe dano dos projéteis do jogador.
func take_damage(info: DamageInfo) -> float:
	if info == null or info.trigger_depth > 3:
		return 0.0
	return health.apply_damage(info)

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
