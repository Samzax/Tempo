class_name CasuloExplosivo
extends Node2D

## Unidade lógica de uma Asa explosiva. Movimento, raio e duração pertencem à
## orquestração futura: este objeto apenas registra intenção, trava e resolve dano.

enum State { IDLE, IN_SLOT, TRACKING, LOCKED, DETONATING, EMPTY, DESTROYED }

var cocoon_id: int = 0
var state: State = State.IDLE
var tracking_target: Node
var tracked_position := Vector2.ZERO
var locked_position := Vector2.ZERO

## Perfil inteiramente injetado em HealthUnits; zero significa perfil ainda não configurado.
var damage_amount: int = 0
var damage_source: Node
var damage_tags: Array[StringName] = []
var damage_position := Vector2.ZERO
var _has_damage_position := false

## Identidades já atingidas nesta detonação. Não há limite compartilhado entre Casulos.
var hit_targets: Dictionary = {}

func set_slot_id(value: int) -> bool:
	if value <= 0 or state != State.IDLE:
		return false
	cocoon_id = value
	return true

func enter_slot() -> bool:
	if cocoon_id <= 0 or state != State.IDLE:
		return false
	state = State.IN_SLOT
	tracking_target = null
	tracked_position = Vector2.ZERO
	locked_position = Vector2.ZERO
	hit_targets.clear()
	return true

func configure_damage(amount: int, source: Node, tags: Array[StringName], position: Vector2) -> bool:
	if amount < 0:
		return false
	damage_amount = amount
	damage_source = source
	damage_tags = tags.duplicate()
	damage_position = position
	_has_damage_position = true
	return true

## Aceita Node2D ou Vector2 para manter a aquisição de alvo testável sem física.
func start_tracking(target: Variant) -> bool:
	if state != State.IN_SLOT:
		return false
	if target is Vector2:
		tracking_target = null
		tracked_position = target
	elif target is Node2D:
		tracking_target = target
		tracked_position = (target as Node2D).global_position
	else:
		return false
	state = State.TRACKING
	return true

func lock_position(position: Vector2) -> bool:
	if state != State.TRACKING:
		return false
	locked_position = position
	state = State.LOCKED
	return true

func can_detonate() -> bool:
	return state == State.LOCKED

## Os alvos são resolvidos externamente. Isto evita dependência de PhysicsServer
## e permite que Casulos distintos apliquem dano cumulativo ao mesmo alvo.
func detonate(resolved_targets: Array = []) -> int:
	if not can_detonate():
		return 0
	state = State.DETONATING
	hit_targets.clear()
	var hit_count := 0
	for target in resolved_targets:
		if not is_instance_valid(target) or not target.has_method(&"take_damage"):
			continue
		var target_id: int = target.get_instance_id()
		if hit_targets.has(target_id):
			continue
		hit_targets[target_id] = true
		var info := DamageInfo.new()
		info.amount = damage_amount
		info.source = damage_source if damage_source != null else self
		info.tags = damage_tags.duplicate()
		info.position = damage_position if _has_damage_position else global_position
		target.take_damage(info)
		hit_count += 1
	state = State.EMPTY
	return hit_count

func reset() -> bool:
	if cocoon_id <= 0 or state != State.EMPTY:
		return false
	state = State.IN_SLOT
	tracking_target = null
	tracked_position = Vector2.ZERO
	locked_position = Vector2.ZERO
	hit_targets.clear()
	return true

func destroy() -> void:
	state = State.DESTROYED
	tracking_target = null
	hit_targets.clear()
