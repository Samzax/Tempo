class_name ItemPoolEntry
extends Resource
## Uma entrada de peso explicitamente associada a um item.

@export var item: ItemDef
@export_range(0.0, 100000.0, 0.01) var base_weight: float = 1.0
