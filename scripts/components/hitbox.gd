class_name Hitbox extends Area2D
## Emissor de dano. Monta DamageInfo e entrega nos alvos informados ou
## sobrepostos, sem despawna-los e sem aplicar knockback.

## Emitida apos cada entrega feita por deliver/strike/strike_overlapping_*.
signal damage_delivered(target: Node, info: DamageInfo, actual: int)

## Dano bruto em HealthUnits.
@export var amount: int = 0
## Tags do DamageInfo autorado.
@export var tags: Array[StringName] = []
## Profundidade de origem usada quando nao ha DamageInfo de origem.
@export var chain_depth: int = 0:
	set(value):
		chain_depth = maxi(value, 0)
## No emissor do dano. Vazio usa o no pai.
@export var source_path: NodePath
## Grupo exigido do alvo. Vazio aceita qualquer alvo.
@export var target_group: StringName = &""

## No emissor resolvido a partir de source_path ou do no pai.
func get_source_entity() -> Node:
	if source_path != NodePath(""):
		return get_node_or_null(source_path)
	return get_parent()

## Constroi o DamageInfo desta hitbox. origin vence chain_depth e soma +1.
func build_damage_info(origin: DamageInfo = null, at_position: Vector2 = Vector2.INF) -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = amount
	info.source = get_source_entity()
	info.tags = tags.duplicate()
	info.is_crit = false
	info.position = at_position if at_position.is_finite() else global_position
	if origin != null:
		info.trigger_depth = origin.trigger_depth + 1
	else:
		info.trigger_depth = chain_depth
	return info

## Entrega o dano em um alvo unico. Nao remove o alvo da cena.
func deliver(target: Node, info: DamageInfo) -> int:
	if target == null or info == null:
		return 0
	var actual := 0
	if target.has_method(&"take_damage"):
		actual = int(target.call(&"take_damage", info))
	elif target.get(&"health") is HealthComponent:
		actual = (target.get(&"health") as HealthComponent).apply_damage(info)
	else:
		return 0
	damage_delivered.emit(target, info, actual)
	return actual

## Constroi o DamageInfo e entrega no alvo.
func strike(target: Node, origin: DamageInfo = null, at_position: Vector2 = Vector2.INF) -> int:
	return deliver(target, build_damage_info(origin, at_position))

## Entrega uma vez em cada corpo sobreposto aceito por target_group.
func strike_overlapping_bodies() -> int:
	var total := 0
	for body in get_overlapping_bodies():
		if target_group != &"" and not body.is_in_group(target_group):
			continue
		total += deliver(body, build_damage_info(null, Vector2.INF))
	return total

## Entrega uma vez em cada area sobreposta aceita por target_group.
func strike_overlapping_areas() -> int:
	var total := 0
	for area in get_overlapping_areas():
		if target_group != &"" and not area.is_in_group(target_group):
			continue
		total += deliver(area, build_damage_info(null, Vector2.INF))
	return total
