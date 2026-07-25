class_name DamageAction
extends ActionDef
## Provoca um estouro em area, propagando a profundidade e limitando a cadeia.

@export var amount: float = 1.0
@export var radius: float = 40.0
@export var tags: Array[StringName] = [&"explosion"]
## Limita a largura da cadeia para evitar picos de quadro.
@export var max_targets: int = 8

func execute(context: EffectContext) -> void:
	var owner := context.owner
	if owner == null or not owner.has_method("get_tree"):
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
	var hit := 0
	for e in owner.get_tree().get_nodes_in_group(&"enemies"):
		if not is_instance_valid(e) or e.is_queued_for_deletion():
			continue
		if not (e is Node2D):
			continue
		if e.global_position.distance_to(pos) <= radius:
			var info := DamageInfo.new()
			info.amount = amount
			info.source = owner
			info.tags = tags.duplicate()
			info.position = e.global_position
			info.trigger_depth = depth
			if e.has_method("take_damage"):
				e.take_damage(info)
				hit += 1
				if hit >= max_targets:
					break
