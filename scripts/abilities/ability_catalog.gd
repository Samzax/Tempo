class_name AbilityCatalog
extends RefCounted
## Reune as habilidades ativas disponiveis para loadouts.

static var _abilities: Dictionary = {}

## Inicializa o catalogo apenas na primeira consulta.
static func _ensure() -> void:
	if _abilities.is_empty():
		var overdrive := OverdriveAbility.new()
		var shield := ShieldAbility.new()
		_abilities[overdrive.id] = overdrive
		_abilities[shield.id] = shield

## Devolve a habilidade pelo identificador, ou nulo se ela nao existir.
static func get_ability(id: StringName) -> AbilityDef:
	_ensure()
	if not _abilities.has(id):
		push_error("Habilidade desconhecida: %s" % id)
		return null
	return _abilities[id]

## Informa se um identificador pertence ao catalogo de habilidades.
static func is_valid(id: StringName) -> bool:
	_ensure()
	return _abilities.has(id)
