class_name EngineerDeployable
extends Node2D
## Unidade temporaria da Engenheira: cada modo possui uma Area2D funcional.

enum Kind { TRAP, DRONE, GADGET }

const TRAP_DAMAGE := 3.0
const DRONE_DAMAGE := 1.0
const DRONE_HIT_INTERVAL := 0.5
const GADGET_INVULN_DURATION := 0.75
const GADGET_RECHARGE := 1.0

@export var kind: Kind = Kind.TRAP
@export var deploying_player: Node2D

@onready var influence: Area2D = $Influence

var _next_effect_at: Dictionary = {}

func _ready() -> void:
	influence.body_entered.connect(_on_influence_body_entered)
	_apply_kind()

func configure(next_kind: Kind, next_deploying_player: Node2D) -> void:
	kind = next_kind
	deploying_player = next_deploying_player
	if is_node_ready():
		_apply_kind()

func _physics_process(delta: float) -> void:
	if kind == Kind.DRONE and is_instance_valid(deploying_player):
		global_position += global_position.direction_to(deploying_player.global_position) * minf(45.0 * delta, global_position.distance_to(deploying_player.global_position))
		for body in influence.get_overlapping_bodies():
			_damage_enemy(body as Node2D, DRONE_DAMAGE, DRONE_HIT_INTERVAL)
	elif kind == Kind.GADGET:
		for body in influence.get_overlapping_bodies():
			_buff_player(body as Node2D)

func _apply_kind() -> void:
	# Inimigos ocupam a camada 4; o jogador, a camada 2.
	influence.collision_mask = 2 if kind == Kind.GADGET else 4
	queue_redraw()

func _on_influence_body_entered(body: Node2D) -> void:
	match kind:
		Kind.TRAP:
			if _damage_enemy(body, TRAP_DAMAGE):
				queue_free()
		Kind.DRONE:
			_damage_enemy(body, DRONE_DAMAGE, DRONE_HIT_INTERVAL)
		Kind.GADGET:
			_buff_player(body)

func _damage_enemy(body: Node2D, amount: float, interval: float = 0.0) -> bool:
	if body == null or not body.has_method(&"take_damage"):
		return false
	var instance_id := body.get_instance_id()
	var now := Time.get_ticks_msec() * 0.001
	if now < float(_next_effect_at.get(instance_id, 0.0)):
		return false
	_next_effect_at[instance_id] = now + interval
	var info := DamageInfo.new()
	info.amount = amount
	info.source = deploying_player if is_instance_valid(deploying_player) else self
	info.position = global_position
	info.tags = [&"engineer_deployable"]
	body.call(&"take_damage", info)
	return true

func _buff_player(body: Node2D) -> void:
	if body == null or body != deploying_player or not body.has_method(&"grant_invuln"):
		return
	var instance_id := body.get_instance_id()
	var now := Time.get_ticks_msec() * 0.001
	if now < float(_next_effect_at.get(instance_id, 0.0)):
		return
	_next_effect_at[instance_id] = now + GADGET_RECHARGE
	body.call(&"grant_invuln", GADGET_INVULN_DURATION)

func _draw() -> void:
	match kind:
		Kind.TRAP:
			draw_circle(Vector2.ZERO, 6.0, Color("56d8ff"))
			for index in 4:
				draw_line(Vector2.ZERO, Vector2.UP.rotated(index * PI * 0.5) * 10.0, Color("b6f3ff"), 1.0)
		Kind.DRONE:
			draw_colored_polygon(PackedVector2Array([Vector2(0, -7), Vector2(6, 6), Vector2(-6, 6)]), Color("a66cff"))
		Kind.GADGET:
			draw_rect(Rect2(-6, -6, 12, 12), Color("ffd166"), true)
			draw_line(Vector2(-9, 0), Vector2(9, 0), Color.WHITE, 1.0)
