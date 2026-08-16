class_name StatDef
extends Resource
## Define os limites e as operações aceitas por uma estatística.

enum Op {
	FLAT,
	ADD_PCT,
	MULT,
	OVERRIDE,
}

@export var id: StringName
@export var default_base: float = 0.0
@export var default_min: float = 0.0
@export var default_max: float = 100000.0
@export var max_limit_enabled: bool = true
@export var is_integer: bool = false
@export var allowed_ops: Array[int] = []
