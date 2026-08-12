class_name SectorNode
extends Resource

enum NodeType { OPENING, COMBAT, BOSS, TREASURE, RISK }

@export var id: int
@export var column: int = 0
@export var row: int = 0
@export var node_type: NodeType = NodeType.COMBAT
@export var children: Array[int] = []
@export var room_profile: StringName = &"default"
