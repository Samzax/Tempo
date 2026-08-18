class_name LaserBeam2D
extends Node2D

## Feixe lógico reutilizável. Não possui renderer nem assets: o estado público
## permite que uma camada visual futura desenhe telegraph e disparo sem alterar
## a autoridade nem a colisão deste slice.

enum State { INACTIVE, TELEGRAPH, FIRING }

@export_range(1.0, 4096.0, 1.0) var beam_length_px := 900.0
@export_range(1.0, 256.0, 1.0) var beam_width_px := 16.0
@export_range(0.01, 50.0, 0.01) var turn_rate_radians := 5.5
@export_range(0.01, 10.0, 0.01) var hit_tick_seconds := 0.25
@export var collision_mask := 6 # player (2) | enemy (3)

var state: State = State.INACTIVE
var damage_amount := 25
var damage_source: Node
var damage_tags: Array[StringName] = []
var tracking_target: Node2D
var fixed_origin := Vector2.ZERO
var _tracking_frozen := false
var _fire_elapsed := 0.0
var _last_hit_by_target: Dictionary = {}

func configure(origin: Vector2, amount: int, source: Node, tags: Array[StringName], mask := 6) -> bool:
	if amount < 0:
		return false
	fixed_origin = origin
	global_position = origin
	damage_amount = amount
	damage_source = source
	damage_tags = tags.duplicate()
	collision_mask = mask
	return true

## Configures this logical beam as a finite world-space segment.  This keeps
## collision, damage ownership and local hit dedupe identical to long beams.
func configure_segment(origin: Vector2, endpoint: Vector2) -> bool:
	var segment := endpoint - origin
	if segment.length_squared() <= 0.0001:
		return false
	fixed_origin = origin
	global_position = origin
	beam_length_px = segment.length()
	global_rotation = segment.angle()
	_tracking_frozen = true
	tracking_target = null
	return true

func set_tracking_target(target: Node2D) -> void:
	tracking_target = target

func freeze_tracking() -> void:
	_tracking_frozen = true

func start_telegraph() -> bool:
	if state != State.INACTIVE:
		return false
	_tracking_frozen = false
	state = State.TELEGRAPH
	_update_tracking(0.0)
	return true

func start_firing() -> bool:
	if state != State.TELEGRAPH:
		return false
	state = State.FIRING
	_fire_elapsed = 0.0
	_last_hit_by_target.clear()
	return true

func stop() -> void:
	state = State.INACTIVE
	_fire_elapsed = 0.0
	_last_hit_by_target.clear()

func cleanup() -> void:
	stop()
	_tracking_frozen = false
	tracking_target = null

func runtime_snapshot() -> Dictionary:
	return {"state": state, "origin": fixed_origin, "rotation": global_rotation, "hit_targets": _last_hit_by_target.size()}

func _physics_process(delta: float) -> void:
	if state == State.INACTIVE:
		return
	global_position = fixed_origin
	_update_tracking(delta)
	if state == State.FIRING:
		_fire_elapsed += maxf(0.0, delta)
		_apply_firing_hits()

func _update_tracking(delta: float) -> void:
	if _tracking_frozen:
		return
	if not is_instance_valid(tracking_target) or tracking_target.is_queued_for_deletion():
		return
	var to_target := global_position.direction_to(tracking_target.global_position)
	if to_target == Vector2.ZERO:
		return
	var desired_rotation := to_target.angle()
	global_rotation = rotate_toward(global_rotation, desired_rotation, turn_rate_radians * maxf(0.0, delta))

func _apply_firing_hits() -> void:
	if not is_inside_tree():
		return
	var shape := RectangleShape2D.new()
	shape.size = Vector2(beam_length_px, beam_width_px)
	var direction := Vector2.RIGHT.rotated(global_rotation)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(global_rotation, global_position + direction * (beam_length_px * 0.5))
	query.collision_mask = collision_mask
	query.collide_with_bodies = true
	query.collide_with_areas = false
	for result in get_world_2d().direct_space_state.intersect_shape(query):
		var target := result.get("collider") as Node
		if not _is_damage_target(target):
			continue
		var target_id := target.get_instance_id()
		var last_hit: float = float(_last_hit_by_target.get(target_id, -INF))
		if _fire_elapsed - last_hit < hit_tick_seconds:
			continue
		_last_hit_by_target[target_id] = _fire_elapsed
		var info := DamageInfo.new()
		info.amount = damage_amount
		info.source = damage_source if is_instance_valid(damage_source) else self
		info.tags = damage_tags.duplicate()
		info.position = global_position
		target.take_damage(info)

func _is_damage_target(target: Node) -> bool:
	if target == null or not is_instance_valid(target) or target.is_queued_for_deletion():
		return false
	if not (target.is_in_group(&"player") or target.is_in_group(&"enemies")) or not target.has_method(&"take_damage"):
		return false
	return target.get("health") is HealthComponent or target.get_node_or_null("HealthComponent") is HealthComponent
