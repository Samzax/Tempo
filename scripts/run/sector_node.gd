class_name SectorNode
extends Resource

enum NodeType { OPENING, COMBAT, BOSS, TREASURE, RISK }

@export var id: int
@export var column: int = 0
@export var row: int = 0
@export var node_type: NodeType = NodeType.COMBAT
@export var children: Array[int] = []
## Os tres perfis permitem montar uma sala sem inferir conteudo a partir do
## setor ou da posicao do no no mapa.
@export var encounter_profile: StringName = &"default"
@export var environment_profile: StringName = &"default"
@export var transition_profile: StringName = &"default"
@export var room_profile: StringName = &"default"
