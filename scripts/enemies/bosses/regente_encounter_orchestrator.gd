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
const WING_OFFSETS: Array[Vector2] = [Vector2(-38, -28), Vector2(-54, -48), Vector2(-71, -31), Vector2(-52, -8), Vector2(-40, 26), Vector2(-66, 40), Vector2(38, -28), Vector2(54, -48), Vector2(71, -31), Vector2(52, -8), Vector2(40, 26), Vector2(66, 40)]
const REPLACEMENT_INTERVAL := 1.0
var _electric_slots: Array[Dictionary] = []
var _replacement_elapsed := 0.0

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
	_initialize_electric_wings()
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
	_clear_electric_lifecycle()

func _physics_process(delta: float) -> void:
	if _torn_down or not _has_host_authority() or not is_instance_valid(_core): return
	_update_electric_slot_positions()
	_settle_electric_transitions()
	_replacement_elapsed += maxf(0.0, delta)
	if _replacement_elapsed >= REPLACEMENT_INTERVAL:
		# This is a global structural scheduler gate, not combat cadence/tuning.
		_replacement_elapsed = fposmod(_replacement_elapsed, REPLACEMENT_INTERVAL)
		_try_replace_electric_drone()

func destroy_electric_drone(drone_id: int) -> bool:
	if not _has_host_authority() or not is_instance_valid(_core): return false
	for slot in _electric_slots:
		if int(slot.get("drone_id", -1)) == drone_id:
			if not _core.destroy_electric_drone(drone_id): return false
			slot.drone_id = -1; slot.occupied = false; slot.transition = false
			return true
	return false

## RoomController chama isto a partir de sua unica conexao ao resolved do core.
func notify_core_resolved(enemy: Enemy, _reason: int) -> void:
	if _torn_down or enemy == null or enemy != _core or state >= State.DEFEATED:
		return
	state = State.DEFEATED
	_clear_encounter_children()
	_clear_electric_lifecycle()
	state = State.VICTORY

func _exit_tree() -> void:
	stop()

func _clear_encounter_children() -> void:
	if not is_instance_valid(_core):
		return
	_core.teardown_electric_grid()
	for child in _core.get_children():
		if (child is ElectricGridController or child.get_meta(&"regente_encounter_owned", false)) and not child.is_queued_for_deletion():
			child.queue_free()

func _initialize_electric_wings() -> void:
	if not is_instance_valid(_core) or not _has_host_authority(): return
	_electric_slots.clear()
	# 58/74/18 are approved structural gate candidates, not final fairness tuning.
	_core.configure_electric_geometry(58.0, 74.0, 18.0)
	for index in range(WING_OFFSETS.size()):
		var offset := WING_OFFSETS[index]
		var slot := {"index": index, "drone_id": -1, "offset": offset, "occupied": false, "transition": false}
		_electric_slots.append(slot)
		var drone := _core.spawn_electric_drone(_core.global_position, true)
		if drone.is_empty(): continue
		slot.drone_id = int(drone.id); slot.occupied = true; slot.transition = true

func _update_electric_slot_positions() -> void:
	var updates: Dictionary = {}
	for slot in _electric_slots:
		if bool(slot.get("occupied", false)) and int(slot.get("drone_id", -1)) > 0:
			updates[int(slot.drone_id)] = {"position": _core.global_position + slot.offset, "formation_open": bool(slot.get("transition", false))}
	if not updates.is_empty(): _core.update_electric_drone_positions(updates)

func _settle_electric_transitions() -> void:
	var updates: Dictionary = {}
	var settling_slots: Array[Dictionary] = []
	for slot in _electric_slots:
		if not bool(slot.get("occupied", false)) or not bool(slot.get("transition", false)): continue
		var drone_id := int(slot.get("drone_id", -1))
		if drone_id < 1: continue
		updates[drone_id] = {"position": _core.global_position + slot.offset, "formation_open": false}
		settling_slots.append(slot)
	if updates.is_empty() or not _core.update_electric_drone_positions(updates):
		return
	for slot in settling_slots:
		slot.transition = false

func _try_replace_electric_drone() -> bool:
	if _core.electric_drone_ids().size() >= WING_OFFSETS.size(): return false
	var candidate: Dictionary = {}
	for slot in _electric_slots:
		if bool(slot.get("occupied", false)): continue
		if candidate.is_empty() or Vector2(slot.offset).length_squared() < Vector2(candidate.offset).length_squared() or (is_equal_approx(Vector2(slot.offset).length_squared(), Vector2(candidate.offset).length_squared()) and int(slot.index) < int(candidate.index)):
			candidate = slot
	if candidate.is_empty(): return false
	var drone := _core.spawn_electric_drone(_core.global_position, true)
	if drone.is_empty(): return false
	candidate.drone_id = int(drone.id); candidate.occupied = true; candidate.transition = true
	return true

func _clear_electric_lifecycle() -> void:
	_replacement_elapsed = 0.0
	_electric_slots.clear()

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
