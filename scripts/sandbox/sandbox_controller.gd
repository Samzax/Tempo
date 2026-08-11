class_name SandboxController
extends RefCounted
## Operacoes de desenvolvimento para uma sessao ativa, separadas da interface.

var _player: Node
var _session: Session

func _init(player: Node = null, session: Session = null) -> void:
	_player = player
	_session = session

func set_targets(player: Node, session: Session) -> void:
	_player = player
	_session = session

func set_stat_override(stat_id: StringName, value: float) -> bool:
	if _player == null or not _player.has_method(&"sandbox_set_stat_override"):
		return false
	return _player.call(&"sandbox_set_stat_override", stat_id, value)

func grant_item(item_id: StringName, amount: int = 1) -> int:
	if _player == null or not _player.has_method(&"sandbox_grant_item"):
		return 0
	return _player.call(&"sandbox_grant_item", item_id, amount)

func remove_item(item_id: StringName, amount: int = 1) -> int:
	if _player == null or not _player.has_method(&"sandbox_remove_item"):
		return 0
	return _player.call(&"sandbox_remove_item", item_id, amount)

func heal_player() -> bool:
	if _player == null or not _player.has_method(&"sandbox_heal_full"):
		return false
	_player.call(&"sandbox_heal_full")
	return true

func set_god_mode(enabled: bool) -> bool:
	if _player == null or not _player.has_method(&"sandbox_set_invulnerable"):
		return false
	_player.call(&"sandbox_set_invulnerable", enabled)
	return true

func clear_room() -> bool:
	if _session == null:
		return false
	return _session.sandbox_clear_room()

func spawn_regente_preview() -> bool:
	if _session == null:
		return false
	return _session.sandbox_spawn_regente_preview()

func warp(seed_value: int, sector_index: int, node_id: int, node_type: int) -> bool:
	if _session == null:
		return false
	return _session.sandbox_warp(seed_value, sector_index, node_id, node_type)
