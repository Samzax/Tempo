class_name TreasurePricing
extends RefCounted

const COMMON := 6
const RARE := 9
const LEGENDARY := 12

static func cost_for(item: ItemDef) -> int:
	if item == null:
		return -1
	return cost_for_rarity(item.rarity)

static func cost_for_rarity(rarity: int) -> int:
	match rarity:
		ItemDef.Rarity.COMMON:
			return COMMON
		ItemDef.Rarity.RARE:
			return RARE
		ItemDef.Rarity.LEGENDARY:
			return LEGENDARY
	return -1
