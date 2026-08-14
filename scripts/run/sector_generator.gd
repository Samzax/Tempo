class_name SectorGenerator
extends RefCounted
## Gera a topologia localmente. Nenhuma rolagem consome o RNG de combate da execucao.

static func generate(run_seed: int, sector_index: int) -> SectorDef:
	if sector_index != 0:
		return null
	var sector := SectorDef.new()
	sector.sector_index = sector_index
	var start := _make_node(0, 0, 0, SectorNode.NodeType.OPENING)
	start.encounter_profile = &"phase_one"
	var upper := _make_node(1, 1, 0, SectorNode.NodeType.COMBAT)
	upper.encounter_profile = &"upper"
	upper.environment_profile = &"upper_background_human_s2"
	var disconnected_left := _make_node(2, 1, 1, SectorNode.NodeType.COMBAT)
	var core := _make_node(3, 2, 0, SectorNode.NodeType.TREASURE)
	core.encounter_profile = &"sector3_upper"
	core.environment_profile = &"sector3_upper_core"
	core.transition_profile = &"sector3_upper_transition"
	var disconnected_lower := _make_node(4, 2, 1, SectorNode.NodeType.COMBAT)
	var disconnected_merge := _make_node(5, 3, 0, SectorNode.NodeType.COMBAT)
	var boss := _make_node(6, 4, 0, SectorNode.NodeType.BOSS)
	start.children = [upper.id]
	upper.children = [core.id]
	core.children = [boss.id]
	for node in [start, upper, disconnected_left, core, disconnected_lower, disconnected_merge, boss]:
		sector.nodes[node.id] = node
	sector.start_node_id = start.id
	return sector

static func _make_node(node_id: int, column: int, row: int, node_type: int) -> SectorNode:
	var node := SectorNode.new()
	node.id = node_id
	node.column = column
	node.row = row
	node.node_type = node_type
	return node
