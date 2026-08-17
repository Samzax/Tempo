class_name RegenteEncounterOrchestrator
extends Node
## Produtor unico do profile da Regente. Ele implementa somente o contrato que
## RoomController ja consome; combate e ataques pertencem a blocos posteriores.

const REGENTE_SCENE := preload("res://scenes/enemies/bosses/regente_dos_ecos.tscn")

signal enemy_spawned(enemy: Enemy)
signal spawns_finished
signal spawns_failed(reason: String)

enum State { INTRO, SETTLE, READY, ATTACK_HANDOFF, DEFEATED, VICTORY }

var state: State = State.INTRO
var _enemy_container: Node
var _room_controller: RoomController
var _room_bounds := Rect2(Vector2.ZERO, Vector2(720.0, 405.0))
var _core: RegenteDosEcos
var _started := false
var _finished_emitted := false
var _torn_down := false

func set_enemy_container(container: Node) -> void:
	_enemy_container = container

func configure_encounter(room_controller: RoomController, room_bounds: Rect2) -> void:
	_room_controller = room_controller
	if room_bounds.size.x > 0.0 and room_bounds.size.y > 0.0:
		_room_bounds = room_bounds

## Mantem a assinatura do SpawnDirector para que RoomController nao precise
## conhecer detalhes do encontro. O argumento e intencionalmente ignorado.
func start(_spawn_limit: int) -> bool:
	if _started:
		return false
	_started = true
	if not _has_host_authority():
		return true
	if not is_instance_valid(_enemy_container) or _enemy_container.is_queued_for_deletion():
		_fail("Regente encounter requires an enemies_container.")
		return false
	var core := REGENTE_SCENE.instantiate() as RegenteDosEcos
	if core == null:
		_fail("Regente encounter could not instantiate its core.")
		return false
	_core = core
	_core.set_room_bounds(_room_bounds)
	_core.set_room_cull_policy(RoomDef.CullPolicy.NONE)
	_core.global_position = _room_bounds.get_center()
	_enemy_container.add_child(_core)
	# RoomController e o dono exclusivo da conexao resolved e do RoomRuntime;
	# este sinal faz o core percorrer exatamente essa API existente.
	enemy_spawned.emit(_core)
	state = State.SETTLE
	state = State.READY
	state = State.ATTACK_HANDOFF
	_finish_spawns()
	return true

func stop() -> void:
	if _torn_down:
		return
	_torn_down = true
	_clear_encounter_children()

## RoomController chama isto a partir de sua unica conexao ao resolved do core.
func notify_core_resolved(enemy: Enemy, _reason: int) -> void:
	if _torn_down or enemy == null or enemy != _core or state >= State.DEFEATED:
		return
	state = State.DEFEATED
	_clear_encounter_children()
	state = State.VICTORY

func _exit_tree() -> void:
	stop()

func _clear_encounter_children() -> void:
	if not is_instance_valid(_core):
		return
	for child in _core.get_children():
		if (child is ElectricGridController or child.get_meta(&"regente_encounter_owned", false)) and not child.is_queued_for_deletion():
			child.queue_free()

func _finish_spawns() -> void:
	if _finished_emitted:
		return
	_finished_emitted = true
	spawns_finished.emit()

func _fail(reason: String) -> void:
	if _finished_emitted:
		return
	_finished_emitted = true
	push_warning(reason)
	spawns_failed.emit(reason)

func _has_host_authority() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
