class_name CollisionImpactResolver
extends RefCounted

const HEALTH_UNITS := preload("res://scripts/components/health_units.gd")
## Resolve impactos player-enemy uma vez por sobreposicao.

const EPSILON := 0.001
const SPEED_UNIT := 100.0
## Converte a velocidade de jogo para a escala universal de impacto. A fisica
## de colisao e deliberadamente linear: nao ha energia quadratica nem reparto
## por massa do dano/impulso apos a massa reduzida.
const IMPACT_SCALE := 1.0 / SPEED_UNIT

static func resolve_overlaps(player: Node2D, pairs: Dictionary, preserve_ids: Dictionary = {}) -> void:
	var player_snapshot := _collision_impact_snapshot(player)
	if player_snapshot.is_empty():
		return
	var overlapping: Dictionary = {}
	var snapshots: Dictionary = {}
	for body in player.hurtbox.get_overlapping_bodies():
		if not _is_damageable_enemy(body):
			continue
		overlapping[body.get_instance_id()] = body
		snapshots[body.get_instance_id()] = _collision_impact_snapshot(body)
	for body in overlapping.values():
		var enemy_snapshot: Dictionary = snapshots.get(body.get_instance_id(), {})
		# Cada novo par precisa pertencer ao mesmo ciclo de vida que iniciou
		# esta varredura. O par atual permanece bilateral e pre-calculado.
		if not _collision_impact_snapshot_is_current(player, player_snapshot):
			break
		if not _collision_impact_snapshot_is_current(body, enemy_snapshot):
			continue
		_resolve_pair(player, body, pairs)
	_prune_pairs(pairs, overlapping, preserve_ids)

## A charge usa esta varredura em cada subpasso para nao atravessar inimigos.
static func resolve_segment(player: Node2D, origin: Vector2, destination: Vector2, pairs: Dictionary) -> void:
	var player_snapshot := _collision_impact_snapshot(player)
	if player_snapshot.is_empty() or not _finite_vector(origin) or not _finite_vector(destination):
		return
	var segment := destination - origin
	var length_squared := segment.length_squared()
	if length_squared <= EPSILON:
		resolve_overlaps(player, pairs)
		return
	var player_radius := _radius_for(player)
	var intersected: Dictionary = {}
	var candidates: Array[Dictionary] = []
	for body in player.get_tree().get_nodes_in_group(&"enemies"):
		if not _is_damageable_enemy(body):
			continue
		var enemy := body as Node2D
		if enemy == null:
			continue
		var projection := clampf((enemy.global_position - origin).dot(segment) / length_squared, 0.0, 1.0)
		var closest := origin + segment * projection
		if enemy.global_position.distance_to(closest) <= player_radius + _radius_for(enemy):
			intersected[enemy.get_instance_id()] = enemy
			candidates.append({
				&"enemy": enemy,
				&"snapshot": _collision_impact_snapshot(enemy),
				&"normal": (enemy.global_position - origin).normalized(),
			})
	for candidate in candidates:
		var enemy: Node2D = candidate[&"enemy"]
		var enemy_snapshot: Dictionary = candidate[&"snapshot"]
		if not _collision_impact_snapshot_is_current(player, player_snapshot):
			break
		if not _collision_impact_snapshot_is_current(enemy, enemy_snapshot):
			continue
		var impact_normal: Vector2 = candidate[&"normal"]
		if impact_normal == Vector2.ZERO:
			impact_normal = segment.normalized()
		_resolve_pair(player, enemy, pairs, impact_normal)
	# Nao inicie a varredura de overlap do mesmo subpasso apos uma transicao
	# reentrante: ela pertence ao proximo ciclo de simulacao, nao ao snapshot.
	if _collision_impact_snapshot_is_current(player, player_snapshot):
		resolve_overlaps(player, pairs, intersected)

## Protocolo opcional de ciclo de vida para impactos. Entidades legadas sem os
## metodos continuam elegiveis; invalidas ou em queue_free nunca participam.
static func _collision_impact_snapshot(body: Variant) -> Dictionary:
	if not body is Node2D or not is_instance_valid(body) or body.is_queued_for_deletion():
		return {}
	var active := true
	if body.has_method(&"is_collision_impact_active"):
		active = body.call(&"is_collision_impact_active") == true
	if not active:
		return {}
	var snapshot := {&"has_generation": false}
	if body.has_method(&"get_collision_impact_generation"):
		snapshot[&"has_generation"] = true
		snapshot[&"generation"] = body.call(&"get_collision_impact_generation")
	return snapshot

static func _collision_impact_snapshot_is_current(body: Variant, snapshot: Dictionary) -> bool:
	if snapshot.is_empty() or not body is Node2D or not is_instance_valid(body) or body.is_queued_for_deletion():
		return false
	if body.has_method(&"is_collision_impact_active") and body.call(&"is_collision_impact_active") != true:
		return false
	return not bool(snapshot.get(&"has_generation", false)) or (body.has_method(&"get_collision_impact_generation") and body.call(&"get_collision_impact_generation") == snapshot.get(&"generation"))

static func _resolve_pair(player: Node2D, enemy: Node2D, pairs: Dictionary, normal_override := Vector2.ZERO) -> void:
	if player == enemy or not _finite_vector(player.global_position) or not _finite_vector(enemy.global_position):
		return
	if _pair_state(pairs, enemy) == &"OVERLAPPING_SPENT":
		return
	var delta := enemy.global_position - player.global_position
	var enemy_velocity := _motion_velocity(enemy)
	var normal: Vector2 = normal_override.normalized() if _finite_vector(normal_override) and normal_override != Vector2.ZERO else (delta.normalized() if delta.length_squared() > EPSILON else (_motion_velocity(player) - enemy_velocity).normalized())
	if normal == Vector2.ZERO:
		# Um contato perfeitamente degenerado ainda precisa de uma normal estavel
		# para poder ser reavaliado sem depender de ordem/ruido de ponto flutuante.
		normal = Vector2.RIGHT
	var relative_normal_speed := maxf(0.0, (_motion_velocity(player) - enemy_velocity).dot(normal))
	if not is_finite(relative_normal_speed) or relative_normal_speed <= 0.0:
		_set_pair_state(pairs, enemy, &"OVERLAPPING_ARMED")
		return
	_set_pair_state(pairs, enemy, &"OVERLAPPING_SPENT")
	var mass_player := _effective_mass(player)
	var mass_enemy := _effective_mass(enemy)
	var total_mass := maxf(mass_player + mass_enemy, EPSILON)
	var reduced_mass := mass_player * mass_enemy / total_mass
	var impact_force := reduced_mass * relative_normal_speed * IMPACT_SCALE
	if not is_finite(impact_force):
		_set_pair_state(pairs, enemy, &"OVERLAPPING_ARMED")
		return
	var damage_to_player := impact_force * (1.0 - _damage_resistance(player))
	var damage_to_enemy := impact_force * (1.0 - _damage_resistance(enemy))
	var impact_point := player.global_position.lerp(enemy.global_position, 0.5)
	var player_info := _damage_info(damage_to_player, enemy, impact_point)
	var enemy_info := _damage_info(damage_to_enemy, player, impact_point)
	# Ambos os DamageInfo e impulsos sao calculados antes de qualquer callback de dano.
	var impulse := impact_force
	var knockback_player: Vector2 = -normal * impulse * _knockback_force(enemy) * (1.0 - _knockback_resistance(player))
	var knockback_enemy: Vector2 = normal * impulse * _knockback_force(player) * (1.0 - _knockback_resistance(enemy))
	# A etapa de dano acontece para os dois lados a partir do mesmo snapshot.
	# Knockback e quaisquer efeitos derivados so acontecem para sobreviventes.
	var player_health_before := _health_units(player)
	var enemy_health_before := _health_units(enemy)
	player.take_damage(player_info)
	if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
		enemy.take_damage(enemy_info)
	if _survived_damage(player, player_health_before, player_info.amount):
		_apply_knockback(player, knockback_player)
	if _survived_damage(enemy, enemy_health_before, enemy_info.amount):
		_apply_knockback(enemy, knockback_enemy)

static func _damage_info(amount: float, source: Node, position: Vector2) -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = HEALTH_UNITS.from_hp(amount)
	info.source = source
	info.position = position
	info.tags = [&"collision"]
	return info

static func _is_damageable_enemy(body: Variant) -> bool:
	return body is Node2D and is_instance_valid(body) and not body.is_queued_for_deletion() and body.is_in_group(&"enemies") and body.has_method(&"take_damage")

static func _motion_velocity(body: Node2D) -> Vector2:
	if body is CharacterBody2D:
		var velocity := (body as CharacterBody2D).velocity
		if _finite_vector(velocity):
			return velocity
		(body as CharacterBody2D).velocity = Vector2.ZERO
	return Vector2.ZERO

static func _apply_knockback(body: Node2D, impulse: Vector2) -> void:
	if body.has_method(&"apply_collision_knockback"):
		body.call(&"apply_collision_knockback", impulse)
	elif body is CharacterBody2D:
		if _finite_vector(impulse):
			(body as CharacterBody2D).velocity += impulse

## Algumas entidades morrem e se reposicionam sincronicamente dentro de
## take_damage(). O snapshot de HP preserva o fato de que o impacto foi letal
## mesmo quando o callback restaura a vida antes de retornar.
static func _survived_damage(body: Node2D, health_before: int, damage: int) -> bool:
	if not is_instance_valid(body) or body.is_queued_for_deletion():
		return false
	if body.has_method(&"is_dead") and body.call(&"is_dead") == true:
		return false
	if body.get(&"_resolved") == true or body.get(&"_dead") == true:
		return false
	return health_before < 0 or damage < health_before

static func _health_units(body: Node2D) -> int:
	var health: Variant = body.get(&"health")
	if health is HealthComponent:
		return health.health
	return -1

static func _radius_for(body: Node2D) -> float:
	if body.has_method(&"get_collision_radius"):
		return maxf(_finite_or_default(float(body.call(&"get_collision_radius")), 10.0), 1.0)
	for child in body.get_children():
		var collision := child as CollisionShape2D
		if collision != null and collision.shape is CircleShape2D:
			return maxf(_finite_or_default((collision.shape as CircleShape2D).radius, 10.0), 1.0)
	return 10.0

static func _effective_mass(body: Node2D) -> float:
	return maxf(_collision_mass(body), 0.01)

static func _collision_mass(body: Node2D) -> float:
	return maxf(_finite_or_default(float(body.call(&"get_collision_mass")), 1.0), 0.01) if body.has_method(&"get_collision_mass") else maxf(_numeric_property_or_default(body, &"collision_mass", 1.0), 0.01)

static func _damage_resistance(body: Node2D) -> float:
	return clampf(_finite_or_default(float(body.call(&"get_collision_damage_resistance")), 0.0) if body.has_method(&"get_collision_damage_resistance") else _numeric_property_or_default(body, &"collision_damage_resistance", 0.0), 0.0, 1.0)

static func _knockback_force(body: Node2D) -> float:
	return maxf(_finite_or_default(float(body.call(&"get_knockback_force")), 1.0) if body.has_method(&"get_knockback_force") else _numeric_property_or_default(body, &"knockback_force", 1.0), 0.0)

static func _knockback_resistance(body: Node2D) -> float:
	return clampf(_finite_or_default(float(body.call(&"get_knockback_resistance")), 0.0) if body.has_method(&"get_knockback_resistance") else _numeric_property_or_default(body, &"knockback_resistance", 0.0), 0.0, 1.0)

static func _numeric_property_or_default(body: Node2D, property_name: StringName, default_value: float) -> float:
	var value: Variant = body.get(property_name)
	return _finite_or_default(float(value), default_value) if value is int or value is float else default_value

static func _pair_state(pairs: Dictionary, enemy: Node2D) -> StringName:
	var entry: Variant = pairs.get(enemy.get_instance_id())
	if entry is Dictionary:
		var reference: Variant = entry.get(&"enemy")
		if reference is WeakRef and (reference as WeakRef).get_ref() == enemy:
			return entry.get(&"state", &"OVERLAPPING_ARMED")
	return &"OVERLAPPING_ARMED"

static func _set_pair_state(pairs: Dictionary, enemy: Node2D, state: StringName) -> void:
	pairs[enemy.get_instance_id()] = {&"enemy": weakref(enemy), &"state": state}

static func _prune_pairs(pairs: Dictionary, overlapping: Dictionary, preserve: Dictionary) -> void:
	for id in pairs.keys():
		var entry: Variant = pairs[id]
		if not entry is Dictionary or not entry.get(&"enemy") is WeakRef:
			pairs.erase(id)
			continue
		var enemy: Variant = (entry.get(&"enemy") as WeakRef).get_ref()
		if enemy == null or not is_instance_valid(enemy) or (not overlapping.has(id) and not preserve.has(id)):
			pairs.erase(id)
			continue
		var current: Variant = overlapping.get(id, preserve.get(id))
		if current != enemy:
			pairs.erase(id)

static func _finite_vector(value: Vector2) -> bool:
	return is_finite(value.x) and is_finite(value.y)

static func _finite_or_default(value: float, default_value: float) -> float:
	return value if is_finite(value) else default_value
