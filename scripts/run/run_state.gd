class_name RunState
extends Resource

@export var run_seed: int = 1
@export var sector_index: int = 0
@export var current_node_id: int
var completed_nodes: Dictionary = {}
var pending_offers: Dictionary = {}

func node_key(sector: int, node_id: int) -> String:
	return "%d:%s" % [sector, node_id]

func offer_key(sector: int, node_id: int, player_slot: int, reward_index: int) -> String:
	return "%d:%s:%d:%d" % [sector, node_id, player_slot, reward_index]

func mark_completed(sector: int, node_id: int) -> void:
	completed_nodes[node_key(sector, node_id)] = true

func is_completed(sector: int, node_id: int) -> bool:
	return completed_nodes.has(node_key(sector, node_id))

func save_offer(offer: RewardOffer) -> void:
	if offer == null:
		return
	pending_offers[offer_key(offer.sector_index, offer.node_id, offer.player_slot, offer.reward_index)] = offer

func get_offer(sector: int, node_id: int, player_slot: int, reward_index: int) -> RewardOffer:
	return pending_offers.get(offer_key(sector, node_id, player_slot, reward_index)) as RewardOffer

func has_unclaimed_offer(sector: int, node_id: int) -> bool:
	for offer in pending_offers.values():
		var reward := offer as RewardOffer
		if reward != null and reward.sector_index == sector and reward.node_id == node_id and not reward.claimed:
			return true
	return false
