class_name DamageAction
extends ActionDef
## Provoca um estouro em area, propagando a profundidade e limitando a cadeia.

const HEALTH_UNITS := preload("res://scripts/components/health_units.gd")

@export var amount: float = 1.0
@export var radius: float = 40.0
@export var tags: Array[StringName] = [&"explosion"]
## Limita a largura da cadeia para evitar picos de quadro.
@export var max_targets: int = 8

func execute(context: EffectContext) -> void:
	if context == null or context.owner == null:
		return
	var owner := context.owner
	if not owner.is_inside_tree():
		return
	var tree := owner.get_tree()
	if tree == null:
		return
	var depth := context.trigger_depth + 1
	if depth > 3:
		return
	var pos: Vector2
	if context.payload is DamageInfo:
		pos = (context.payload as DamageInfo).position
	elif owner is Node2D:
		pos = owner.global_position
	else:
		return
	var damage_units := HEALTH_UNITS.from_hp(amount)
	var hit := 0
	for e in tree.get_nodes_in_group(&"enemies"):
		if not is_instance_valid(e) or e.is_queued_for_deletion():
			continue
		if not (e is Node2D):
			continue
		if e.global_position.distance_to(pos) <= radius:
			var info := DamageInfo.new()
			info.amount = damage_units
			info.source = owner
			info.tags = tags.duplicate()
			info.position = e.global_position
			info.trigger_depth = depth
			if e.has_method("take_damage"):
				e.take_damage(info)
				hit += 1
				if hit >= max_targets:
					break
