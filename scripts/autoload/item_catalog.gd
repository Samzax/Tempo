extends Node
## Disponibiliza globalmente as definicoes de itens do catalogo.

const ITEM_CATALOG = preload("res://resources/items/item_catalog.tres")

var _items_by_id: Dictionary = {}

func _init() -> void:
	for item: ItemDef in ITEM_CATALOG.items:
		_items_by_id[item.id] = item

## Devolve a definicao de um item conhecido.
func get_item(id: StringName) -> ItemDef:
	if not _items_by_id.has(id):
		push_error("Item desconhecido: %s" % id)
		return null
	return _items_by_id[id]

## Informa se um item pertence ao catalogo.
func is_valid(id: StringName) -> bool:
	return _items_by_id.has(id)

## Devolve todas as definicoes de itens do catalogo.
func get_all() -> Array[ItemDef]:
	var items: Array[ItemDef] = []
	for item: ItemDef in ITEM_CATALOG.items:
		items.append(item)
	return items
