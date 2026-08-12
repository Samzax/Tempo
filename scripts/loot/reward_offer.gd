class_name RewardOffer
extends Resource
## Estado serializavel de uma oferta, sem dependencia de uma cena ou Node.

@export var run_seed: int
@export var sector_index: int
@export var node_id: int
@export var player_slot: int
@export var reward_index: int
@export var pool_id: StringName
@export var options: Array[ItemDef] = []
@export var paid_with_temporal_echoes: bool = false
@export var option_costs: Array[int] = []
@export var claimed: bool = false
@export var claimed_item_id: StringName
