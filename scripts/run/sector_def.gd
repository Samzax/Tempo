class_name SectorDef
extends Resource

@export var sector_index: int = 0
@export var nodes: Dictionary = {}
@export var start_node_id: int

func get_node(node_id: int) -> SectorNode:
	return nodes.get(node_id) as SectorNode

func get_children(node_id: int) -> Array[int]:
	var node := get_node(node_id)
	return node.children.duplicate() if node != null else []
