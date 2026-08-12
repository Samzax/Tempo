class_name ItemTransactionManager
extends RefCounted
## Coordena compra paga sem acoplar Inventory ao estado global de Ecos.

## Transaciona exatamente a instancia de Inventory recebida. ItemDefs devem
## permanecer imutaveis durante esta chamada sincrona.
static func purchase(inventory: Inventory, item: ItemDef, cost: int) -> bool:
	if inventory == null or cost <= 0 or item == null or not inventory.can_acquire(item):
		return false
	if not GameState.has_temporal_echoes(cost):
		return false

	var token: Inventory.ReservationToken = inventory.reserve(item)
	if token == null:
		return false
	if not GameState.spend_temporal_echoes(cost):
		inventory.cancel_reservation(token)
		return false

	# O token permanece local, a mesma instancia continua na stack e toda
	# aquisicao publica respeita _reserved_stacks; portanto este commit e garantido.
	return inventory.commit_reservation(token)
