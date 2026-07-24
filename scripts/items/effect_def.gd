class_name EffectDef
extends Resource
## Define um efeito disparado em resposta a um evento.

@export var event: StringName
@export var condition: ConditionDef
@export_range(0.0, 1.0, 0.01) var chance: float = 1.0
@export var cooldown: float = 0.0
@export var action: ActionDef
