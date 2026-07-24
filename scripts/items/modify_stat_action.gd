class_name ModifyStatAction
extends ActionDef
## Aplica um modificador temporario nas estatisticas do dono.

@export var stat: StringName
@export var op: StatDef.Op = StatDef.Op.ADD_PCT
@export var value: float = 0.0
@export var duration: float = 3.0
@export var source_id: StringName = &"efeito"

func execute(context: EffectContext) -> void:
	var stats = context.owner.get("_stats")
	if stats == null:
		return
	var modifier := StatModifierDef.new()
	modifier.stat = stat
	modifier.op = op
	modifier.value = value
	modifier.duration = duration
	modifier.source_id = source_id
	stats.add_modifier(modifier)
