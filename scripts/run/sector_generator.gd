class_name SectorGenerator
extends RefCounted
## Gera a topologia localmente. Nenhuma rolagem consome o RNG de combate da execucao.

static func generate(run_seed: int, sector_index: int) -> SectorDef:
	var sector := SectorDef.new()
	sector.sector_index = sector_index
	var mixer := RandomNumberGenerator.new()
	mixer.seed = _mixed_seed(run_seed, sector_index)
	var base_id := sector_index * 10
	var start := _make_node(base_id, 0, 0, SectorNode.NodeType.OPENING)
	var left := _make_node(base_id + 1, 1, 0, SectorNode.NodeType.COMBAT)
	var right := _make_node(base_id + 2, 1, 1, SectorNode.NodeType.COMBAT)
	var upper := _make_node(base_id + 3, 2, 0, SectorNode.NodeType.COMBAT)
	upper.room_profile = &"upper"
	var lower := _make_node(base_id + 4, 2, 1, SectorNode.NodeType.COMBAT)
	var merge := _make_node(base_id + 5, 3, 0, SectorNode.NodeType.COMBAT)
	var boss := _make_node(base_id + 6, 4, 0, SectorNode.NodeType.BOSS)
	start.children = [left.id, right.id]
	# A permutacao muda por seed/setor, mantendo cada no com no maximo dois filhos.
	if mixer.randi_range(0, 1) == 0:
		left.children = [upper.id]
		right.children = [lower.id]
	else:
		left.children = [lower.id]
		right.children = [upper.id]
	upper.children = [merge.id]
	lower.children = [merge.id]
	merge.children = [boss.id]
	for node in [start, left, right, upper, lower, merge, boss]:
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

static func _mixed_seed(run_seed: int, sector_index: int) -> int:
	var value := run_seed * 1103515245 + (sector_index + 1) * 12345
	return value ^ (value >> 16)
