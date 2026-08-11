class_name EngineerDeployable
extends Node2D
## Modulo da Engenheira. Cada instancia pertence a uma sala e a um jogador.

enum Kind { TRAP, DRONE, OVERCLOCK_STATION, GADGET = OVERCLOCK_STATION }

const DEPLOY_RANGE := 96.0
const DRONE_SPEED := 190.0
const DRONE_DAMAGE := 1.0
const DRONE_HIT_INTERVAL := 0.5
const DRONE_FIRE_INTERVAL := 1.0
const DRONE_PROJECTILE_SCALE := 0.5
const TRAP_DAMAGE := 3.0
const STATION_MAX_HEALTH := 6.0
const STATION_CONTACT_DAMAGE := 1.0
const STATION_CONTACT_INTERVAL := 0.5
const STATION_FIRE_RATE_BONUS := 0.20
const STATION_BUFF_REFRESH := 0.2
## Mantem a resposta visual proporcional ao giro da mira da nave.
const VISUAL_AIM_TURN_SPEED := 16.0

const BULLET := preload("res://scenes/projectiles/bullet.tscn")

@export var kind: Kind = Kind.TRAP
@export var deploying_player: Node2D

@onready var influence: Area2D = $Influence
@onready var hurtbox: Area2D = $Hurtbox
@onready var health: HealthComponent = $HealthComponent
@onready var drone_sprite: Sprite2D = $DroneSprite
@onready var muzzle: Marker2D = $Muzzle

var _next_effect_at: Dictionary = {}
var _target_position := Vector2.ZERO
var _station_shield_recipients: Dictionary = {}
var _station_buff_source := StringName()
var _drone_fire_cooldown := 0.0
var _drone_visual_angle := 0.0

func _ready() -> void:
	influence.body_entered.connect(_on_influence_body_entered)
	influence.body_exited.connect(_on_influence_body_exited)
	hurtbox.body_entered.connect(_on_hurtbox_body_entered)
	hurtbox.area_entered.connect(_on_hurtbox_area_entered)
	health.died.connect(_on_died)
	_station_buff_source = StringName("engineer_station_%d" % get_instance_id())
	_apply_kind()

func configure(next_kind: Kind, next_deploying_player: Node2D, target_position: Vector2) -> void:
	kind = next_kind
	deploying_player = next_deploying_player
	_target_position = target_position
	if is_node_ready():
		_apply_kind()

func command_to(target_position: Vector2) -> void:
	if kind == Kind.DRONE:
		_target_position = target_position

func _physics_process(delta: float) -> void:
	if is_queued_for_deletion() or (kind == Kind.DRONE and (health == null or health.health <= 0.0)):
		return
	match kind:
		Kind.DRONE:
			_move_drone(delta)
			if not _has_active_deploying_player():
				return
			_update_drone_visual_aim(delta)
			_fire_drone(delta)
			for body in influence.get_overlapping_bodies():
				_damage_enemy(body as Node2D, DRONE_DAMAGE, DRONE_HIT_INTERVAL)
		Kind.OVERCLOCK_STATION:
			for body in influence.get_overlapping_bodies():
				_buff_ally(body as Node2D)
			for body in hurtbox.get_overlapping_bodies():
				_damage_station_from_enemy(body as Node2D)

func _move_drone(delta: float) -> void:
	var remaining := global_position.distance_to(_target_position)
	if remaining <= 0.1:
		global_position = _target_position
		return
	global_position += global_position.direction_to(_target_position) * minf(DRONE_SPEED * delta, remaining)

func _fire_drone(delta: float) -> void:
	if is_queued_for_deletion() or health == null or health.health <= 0.0:
		return
	_drone_fire_cooldown = maxf(0.0, _drone_fire_cooldown - delta)
	if _drone_fire_cooldown > 0.0 or not _has_active_deploying_player():
		return
	# A fisica consulta a mira no instante do disparo; nunca usa o angulo visual suavizado.
	var direction := _owner_fire_direction()
	if direction == Vector2.ZERO:
		return
	var projectiles := get_tree().get_first_node_in_group(&"projectiles")
	if projectiles == null or projectiles.is_queued_for_deletion():
		return
	var bullet := Pools.acquire(BULLET)
	if bullet.get_parent() == null:
		projectiles.add_child(bullet)
	var projectile_speed := _owner_projectile_stat(&"projectile_speed", 320.0)
	var projectile_lifetime := _owner_projectile_stat(&"projectile_lifetime", 2.0)
	bullet.set_room_bounds(_owner_room_bounds())
	bullet.activate(
		muzzle.global_position,
		direction,
		deploying_player,
		DRONE_DAMAGE,
		projectile_speed,
		projectile_lifetime * 0.5,
		DRONE_PROJECTILE_SCALE,
		true,
	)
	_drone_fire_cooldown = DRONE_FIRE_INTERVAL

## Compartilha a resolucao de mira entre sprite e projetil, preservando stubs legados.
func _owner_fire_direction() -> Vector2:
	if not _has_active_deploying_player():
		return Vector2.ZERO
	var direction: Variant = Vector2.ZERO
	if deploying_player.has_method(&"get_fire_direction_from"):
		direction = deploying_player.call(&"get_fire_direction_from", muzzle.global_position)
	elif deploying_player.has_method(&"get_aim_direction"):
		direction = deploying_player.call(&"get_aim_direction")
	if direction is Vector2 and direction.is_finite() and direction.length_squared() > 0.0001:
		return direction.normalized()
	return Vector2.ZERO

## Somente o sprite gira: muzzle, colisores e corpo permanecem no espaco fisico.
func _update_drone_visual_aim(delta: float) -> void:
	var direction := _owner_fire_direction()
	if direction == Vector2.ZERO:
		return
	var target_visual_angle := direction.angle() + PI / 2.0
	var target_local_angle := angle_difference(global_rotation, target_visual_angle)
	var weight := 1.0 - exp(-VISUAL_AIM_TURN_SPEED * delta)
	_drone_visual_angle = lerp_angle(_drone_visual_angle, target_local_angle, weight)
	drone_sprite.rotation = _drone_visual_angle

func _reset_drone_visual_aim() -> void:
	_drone_visual_angle = 0.0
	if is_instance_valid(drone_sprite):
		drone_sprite.rotation = _drone_visual_angle

func _owner_projectile_stat(stat_id: StringName, fallback: float) -> float:
	if deploying_player.has_method(&"get_projectile_stat"):
		var value: Variant = deploying_player.call(&"get_projectile_stat", stat_id, fallback)
		if (value is float or value is int) and is_finite(float(value)) and float(value) > 0.0:
			return float(value)
	return fallback

func _owner_room_bounds() -> Rect2:
	if deploying_player.has_method(&"get_room_bounds"):
		var bounds: Variant = deploying_player.call(&"get_room_bounds")
		if bounds is Rect2 and bounds.size.x > 0.0 and bounds.size.y > 0.0:
			return bounds
	return Rect2(Vector2.ZERO, Vector2(720, 405))

func _apply_kind() -> void:
	# Inimigos ocupam a camada 4; jogadores ocupam a camada 2.
	influence.collision_mask = 2 if kind == Kind.OVERCLOCK_STATION else 4
	hurtbox.monitoring = kind == Kind.DRONE or kind == Kind.OVERCLOCK_STATION
	hurtbox.monitorable = kind == Kind.DRONE or kind == Kind.OVERCLOCK_STATION
	# Camada 3 (inimigos) para contato e camada 5 (projeteis inimigos) para dano a distancia.
	hurtbox.collision_mask = 20
	drone_sprite.visible = kind == Kind.DRONE
	_reset_drone_visual_aim()
	if kind == Kind.DRONE or kind == Kind.OVERCLOCK_STATION:
		health.max_health = STATION_MAX_HEALTH
		health.reset()
	if kind != Kind.DRONE:
		_drone_fire_cooldown = 0.0
	queue_redraw()

func _on_influence_body_entered(body: Node2D) -> void:
	match kind:
		Kind.TRAP:
			if _is_enemy(body):
				_detonate()
		Kind.DRONE:
			if _has_active_deploying_player():
				_damage_enemy(body, DRONE_DAMAGE, DRONE_HIT_INTERVAL)
		Kind.OVERCLOCK_STATION:
			_buff_ally(body)

func _on_influence_body_exited(body: Node2D) -> void:
	if kind == Kind.OVERCLOCK_STATION:
		_remove_station_aura(body)

func _on_hurtbox_body_entered(body: Node2D) -> void:
	if kind == Kind.DRONE or kind == Kind.OVERCLOCK_STATION:
		_damage_station_from_enemy(body)

func _on_hurtbox_area_entered(area: Area2D) -> void:
	if (kind != Kind.DRONE and kind != Kind.OVERCLOCK_STATION) or area == null or not area.is_in_group(&"enemy_projectiles"):
		return
	var info := DamageInfo.new()
	var projectile_damage: Variant = area.get(&"damage")
	info.amount = float(projectile_damage) if projectile_damage != null else STATION_CONTACT_DAMAGE
	info.source = area.get(&"_source") as Node
	info.position = global_position
	info.tags = [&"enemy_projectile", &"engineer_deployable"]
	take_damage(info)
	area.queue_free()

func _damage_enemy(body: Node2D, amount: float, interval: float = 0.0) -> bool:
	if not _is_enemy(body):
		return false
	if kind == Kind.DRONE and not _has_active_deploying_player():
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

func _damage_station_from_enemy(body: Node2D) -> void:
	if not _is_enemy(body):
		return
	var key := body.get_instance_id()
	var now := Time.get_ticks_msec() * 0.001
	if now < float(_next_effect_at.get(key, 0.0)):
		return
	_next_effect_at[key] = now + STATION_CONTACT_INTERVAL
	var info := DamageInfo.new()
	var contact_damage: Variant = body.get(&"contact_damage")
	info.amount = float(contact_damage) if contact_damage != null else STATION_CONTACT_DAMAGE
	info.source = body
	info.position = global_position
	info.tags = [&"contact", &"engineer_drone"] if kind == Kind.DRONE else [&"contact", &"engineer_station"]
	take_damage(info)

## Consumido por projeteis/AoE inimigos e por contratos futuros de dano.
func take_damage(info: DamageInfo) -> void:
	if info == null or _is_player_source(info.source):
		return
	if kind == Kind.TRAP and (info.tags.has(&"burst") or info.tags.has(&"aoe")):
		_detonate()
	elif kind == Kind.DRONE or kind == Kind.OVERCLOCK_STATION:
		health.apply_damage(info)

func _buff_ally(body: Node2D) -> void:
	if body == null or not body.is_in_group(&"player"):
		return
	var player_id := body.get_instance_id()
	if not _station_shield_recipients.has(player_id) and body.has_method(&"grant_shield_charge"):
		body.call(&"grant_shield_charge", _station_buff_source)
		# Keep the recipient, not only its id: teardown must revoke the aura
		# even when the Station is removed by damage, FIFO, or a room change.
		_station_shield_recipients[player_id] = body
	if body.has_method(&"apply_temporary_modifier"):
		body.call(&"apply_temporary_modifier", _station_buff_source, &"fire_rate", StatDef.Op.ADD_PCT, STATION_FIRE_RATE_BONUS, STATION_BUFF_REFRESH)

func _detonate() -> void:
	for body in influence.get_overlapping_bodies():
		_damage_enemy(body as Node2D, TRAP_DAMAGE)
	queue_free()

func _on_died(_fatal_info: DamageInfo) -> void:
	_reset_drone_visual_aim()
	queue_free()

func _exit_tree() -> void:
	for recipient in _station_shield_recipients.values():
		_remove_station_aura(recipient as Node2D)

func _remove_station_aura(body: Node2D) -> void:
	if body == null or not is_instance_valid(body):
		return
	var player_id := body.get_instance_id()
	if not _station_shield_recipients.has(player_id):
		return
	if body.has_method(&"remove_temporary_modifier"):
		body.call(&"remove_temporary_modifier", _station_buff_source)
	if body.has_method(&"revoke_shield_charge"):
		body.call(&"revoke_shield_charge", _station_buff_source)
	_station_shield_recipients.erase(player_id)

func _is_enemy(body: Node2D) -> bool:
	return body != null and body.is_in_group(&"enemies") and body.has_method(&"take_damage")

func _has_active_deploying_player() -> bool:
	return is_instance_valid(deploying_player) and not deploying_player.is_queued_for_deletion()

func _is_player_source(source: Node) -> bool:
	return source != null and source.is_in_group(&"player")

func _draw() -> void:
	match kind:
		Kind.TRAP:
			draw_circle(Vector2.ZERO, 6.0, Color("56d8ff"))
			for index in 4:
				draw_line(Vector2.ZERO, Vector2.UP.rotated(index * PI * 0.5) * 10.0, Color("b6f3ff"), 1.0)
		Kind.DRONE:
			pass
		Kind.OVERCLOCK_STATION:
			draw_rect(Rect2(-6, -6, 12, 12), Color("ffd166"), true)
			draw_line(Vector2(-9, 0), Vector2(9, 0), Color.WHITE, 1.0)
