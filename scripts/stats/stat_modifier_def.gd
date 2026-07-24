class_name StatModifierDef
extends Resource
## Representa uma alteração temporária ou permanente de uma estatística.

@export var stat: StringName
@export var op: StatDef.Op = StatDef.Op.FLAT
@export var value: float = 0.0
@export var duration: float = -1.0
@export var source_id: StringName
@export var priority: int = 0
