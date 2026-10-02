class_name Hurtbox extends Area2D
## Receptor de dano. Encaminha DamageInfo para a entidade dona sem regras
## proprias de filtro: quem escolhe tags e profundidade e o emissor.

## No que recebe o dano. Vazio usa o no pai.
@export var entity_path: NodePath

## Raio usado quando o filho direto nao fornece um CircleShape2D.
const DEFAULT_SHAPE_RADIUS := 10.0

var _entity: Node

## Entidade resolvida a partir de entity_path ou do no pai.
var entity: Node:
	get:
		return get_entity()

## Resolve a entidade receptora e a cacheia, descartando referencia invalida.
func get_entity() -> Node:
	if entity_path != NodePath(""):
		_entity = get_node_or_null(entity_path)
	else:
		_entity = get_parent()
	if _entity == self:
		# Uma hurtbox nao e a propria entidade: evita recursao em take_damage.
		_entity = null
		return null
	return _entity if is_instance_valid(_entity) else null

## Componente de vida da entidade, quando existir.
func get_health() -> HealthComponent:
	var receiver := get_entity()
	if receiver == null:
		return null
	var value: Variant = receiver.get(&"health")
	if value is HealthComponent:
		return value as HealthComponent
	return null

## Aplica apenas a camada e a mascara autoradas, sem tocar em monitoring,
## monitorable nem na forma.
func configure(layer: int, mask: int) -> void:
	collision_layer = layer
	collision_mask = mask

## Raio da forma circular direta, com piso de 1.0; sem forma, o padrao.
func get_shape_radius() -> float:
	for child in get_children():
		var collision := child as CollisionShape2D
		if collision != null and collision.shape is CircleShape2D:
			return maxf((collision.shape as CircleShape2D).radius, 1.0)
	return DEFAULT_SHAPE_RADIUS

## Recebe dano vindo de fora. Somente os dois caminhos de entrega contam:
## take_damage da entidade ou HealthComponent da entidade.
func take_damage(info: DamageInfo) -> int:
	if info == null:
		return 0
	var receiver := get_entity()
	if receiver == null:
		return 0
	if receiver.has_method(&"take_damage"):
		var reported: Variant = receiver.call(&"take_damage", info)
		return int(reported) if reported is int else 0
	var health := get_health()
	if health != null:
		return health.apply_damage(info)
	return 0

## Monta o DamageInfo de uma area que tocou esta hurtbox, extraindo amount e
## source conforme o contrato de engineer_deployable.gd:236-241.
func build_incoming_area_info(area: Area2D, fallback_amount: int, extra_tags: Array[StringName] = []) -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = fallback_amount
	info.source = null
	if area != null and is_instance_valid(area):
		if area.has_method(&"get_damage_units"):
			var reported: Variant = area.call(&"get_damage_units")
			if reported is int:
				info.amount = int(reported)
		var source: Variant = area.get(&"_source")
		if source is Node:
			info.source = source as Node
	info.position = global_position
	info.tags = extra_tags.duplicate()
	info.trigger_depth = 0
	return info
