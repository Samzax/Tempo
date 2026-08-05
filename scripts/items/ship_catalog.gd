class_name ShipCatalog
extends RefCounted
## Descobre as naves de res://resources/ships de forma deterministica.
## Nenhum registro manual e mantido aqui: recursos novos passam a fazer parte do catalogo.

const SHIPS_PATH := "res://resources/ships"

static var _ships: Dictionary = {}
static var _ordered_ids: Array[StringName] = []

static func _ensure() -> void:
	if not _ships.is_empty():
		return
	var filenames := DirAccess.get_files_at(SHIPS_PATH)
	filenames.sort()
	for filename in filenames:
		if not filename.ends_with(".tres"):
			continue
		var ship := load("%s/%s" % [SHIPS_PATH, filename]) as ShipDef
		if ship == null:
			push_warning("ShipCatalog ignorou conteudo invalido: %s." % filename)
			continue
		if ship.id.is_empty():
			push_warning("ShipCatalog ignorou nave sem ID: %s." % filename)
			continue
		if _ships.has(ship.id):
			push_warning("ShipCatalog ignorou ID duplicado '%s' em %s; mantendo o primeiro arquivo em ordem alfabetica." % [ship.id, filename])
			continue
		_ships[ship.id] = ship
		_ordered_ids.append(ship.id)
	_ordered_ids.sort_custom(func(left: StringName, right: StringName) -> bool: return String(left) < String(right))

## Devolve todas as naves ordenadas pelo identificador.
static func all() -> Array[ShipDef]:
	_ensure()
	var result: Array[ShipDef] = []
	for ship_id in _ordered_ids:
		result.append(_ships[ship_id] as ShipDef)
	return result

## Devolve a nave pelo identificador, ou nulo quando nao existir.
## `get` e um metodo nativo de Object em Godot; get_ship preserva esta API sem sobrescreve-lo.
static func get_ship(ship_id: StringName) -> ShipDef:
	_ensure()
	return _ships.get(ship_id) as ShipDef

## Informa se o identificador pertence ao catalogo.
static func is_valid(ship_id: StringName) -> bool:
	_ensure()
	return _ships.has(ship_id)
