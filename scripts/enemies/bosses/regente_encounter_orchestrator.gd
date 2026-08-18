class_name RegenteEncounterOrchestrator
extends Node
## Produtor unico do profile da Regente. Ele implementa somente o contrato que
## RoomController ja consome; combate e ataques pertencem a blocos posteriores.

const REGENTE_SCENE := preload("res://scenes/enemies/bosses/regente_dos_ecos.tscn")
const CASULO_EXPLOSIVO := preload("res://scripts/enemies/bosses/wings/casulo_explosivo.gd")
const FORMACAO_ASAS_CONTROLLER := preload("res://scripts/enemies/bosses/wings/formacao_asas_controller.gd")
const LASER_BEAM_2D := preload("res://scripts/enemies/bosses/wings/laser_beam_2d.gd")

signal enemy_spawned(enemy: Enemy)
signal spawns_finished
signal spawns_failed(reason: String)

enum State { INTRO, SETTLE, READY, ATTACK_HANDOFF, DEFEATED, VICTORY }
# Kept separate from State: State describes encounter resolution, while this
# host-only loop describes the playable electric combat cadence.
enum CombatCycle { COOLDOWN, TELEGRAPH, ATTACK_PULSE, SETTLE }
enum ExplosiveCycle { INACTIVE, TRANSITION, TRACKING, LOCKED, DETONATION, BANK_INTERVAL, RECONSTITUTE }
enum LaserCycle { INACTIVE, TRANSITION, TELEGRAPH, FIRING, RECOVERY }
enum LaserPattern { SHIELD, BOW, WINGS }

# Provisional first-slice timings. These are implementation placeholders, not
# final combat tuning.
const ELECTRIC_COOLDOWN_SECONDS := 5.0
const ELECTRIC_TELEGRAPH_SECONDS := 1.5
const ELECTRIC_ATTACK_PULSE_SECONDS := 0.5
const ELECTRIC_SETTLE_SECONDS := 0.5
# Provisional deterministic expansion of the approved wing offsets; it does
# not introduce a second topology or alter the grid's connection rules.
const ELECTRIC_OPEN_OFFSET_SCALE := 1.65

## Provisional explosive slice values. Damage is expressed in authored HP and
## converted once to HealthUnits (0.25 HP = 25 units); radius is likewise an
## editable initial interpretation of the approved provisional 24 px answer.
const EXPLOSIVE_DAMAGE_HP := 0.25
const EXPLOSIVE_DAMAGE_HEALTH_UNITS := 25
const EXPLOSIVE_RADIUS_PX := 24.0
const EXPLOSIVE_TRANSITION_SECONDS := 0.8
const EXPLOSIVE_TRACKING_SECONDS := 0.75
const EXPLOSIVE_LOCKED_SECONDS := 0.45
const EXPLOSIVE_DETONATION_SECONDS := 0.15
const EXPLOSIVE_BANK_INTERVAL_SECONDS := 0.35
const EXPLOSIVE_RECONSTITUTE_SECONDS := 0.8
const EXPLOSIVE_COLLISION_MASK := 6 # layers player (2) | enemy (3)

## Os padrões laser compartilham o mesmo componente
## autoritativo de dano. Os offsets ficam manuais para ajuste fino de design.
@export_category("Laser Attacks")
@export_range(0, 100000, 1) var LASER_DAMAGE_HEALTH_UNITS := 25
@export_range(1.0, 256.0, 1.0) var LASER_BEAM_WIDTH_PX := 16.0
@export_range(0.01, 10.0, 0.01) var LASER_TRANSITION_SECONDS := 0.8
@export_range(0.01, 10.0, 0.01) var LASER_TELEGRAPH_SECONDS := 0.8
@export_range(0.01, 10.0, 0.01) var LASER_FIRE_SECONDS := 1.5
@export_range(0.01, 10.0, 0.01) var LASER_RECOVERY_SECONDS := 0.8
@export_range(0.01, 10.0, 0.01) var LASER_HIT_TICK_SECONDS := 0.25
@export_range(0.01, 50.0, 0.01) var LASER_TURN_RATE_RADIANS := 5.5
@export_range(0.01, 10.0, 0.01) var LASER_WINGS_BANK_TELEGRAPH_SECONDS := 0.8
@export_range(0.01, 10.0, 0.01) var LASER_WINGS_BANK_FIRE_SECONDS := 1.0
const LASER_COLLISION_MASK := 6 # layers player (2) | enemy (3)
const LASER_SHIELD_OFFSETS: Array[Vector2] = [Vector2(-108, -132), Vector2(-119, -108), Vector2(-126, -84), Vector2(-130, -60), Vector2(-132, -36), Vector2(-133, -12), Vector2(133, -132), Vector2(132, -108), Vector2(130, -84), Vector2(126, -60), Vector2(119, -36), Vector2(108, -12)]
## Sete drones formam o crescente (0..6) e cinco o chevron (7..11).
## O ápice frontal do chevron, índice zero-based 9, é o único emissor.
const LASER_BOW_OFFSETS: Array[Vector2] = [Vector2(-140, -40), Vector2(-110, -80), Vector2(-60, -110), Vector2(0, -120), Vector2(60, -110), Vector2(110, -80), Vector2(140, -40), Vector2(-50, 20), Vector2(-25, 60), Vector2(0, 100), Vector2(25, 60), Vector2(50, 20)]
const LASER_BOW_EMITTER_INDEX := 9
const LASER_WINGS_BANK_A: Array[int] = [0, 1, 6, 7]
const LASER_WINGS_BANK_B: Array[int] = [2, 3, 8, 9]
const LASER_WINGS_BANK_F: Array[int] = [4, 5, 10, 11]

var state: State = State.INTRO
var _enemy_container: Node
var _room_controller: RoomController
var _room_bounds := Rect2(Vector2.ZERO, Vector2(720.0, 405.0))
var _core: RegenteDosEcos
var _started := false
var _finished_emitted := false
var _torn_down := false
var _combat_cycle: CombatCycle = CombatCycle.COOLDOWN
var _combat_cycle_elapsed := 0.0
var _combat_loop_active := false
const WING_OFFSETS: Array[Vector2] = [Vector2(-38, -28), Vector2(-54, -48), Vector2(-71, -31), Vector2(-52, -8), Vector2(-40, 26), Vector2(-66, 40), Vector2(38, -28), Vector2(54, -48), Vector2(71, -31), Vector2(52, -8), Vector2(40, 26), Vector2(66, 40)]
const REPLACEMENT_INTERVAL := 1.0
var _electric_slots: Array[Dictionary] = []
var _replacement_elapsed := 0.0
var _electric_laps_completed := 0
var _explosive_formation: FormacaoAsasController
var _explosive_cocoons: Array[CasuloExplosivo] = []
var _explosive_cycle: ExplosiveCycle = ExplosiveCycle.INACTIVE
var _explosive_elapsed := 0.0
var _explosive_bank_index := 0
var _explosive_tracking_origins: Dictionary = {}
# TRANSITION starts at a physics-frame boundary. This prevents the residual
# electric SETTLE frame from being charged against the explosive timer.
var _explosive_transition_just_started := false
var _laser_cycle: LaserCycle = LaserCycle.INACTIVE
var _laser_elapsed := 0.0
var _laser_beams: Array[LaserBeam2D] = []
var _laser_pattern: LaserPattern = LaserPattern.SHIELD
var _next_laser_pattern: LaserPattern = LaserPattern.SHIELD
var _laser_bank_index := 0

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
	_initialize_explosive_wings()
	_initialize_laser_beams()
	# RoomController e o dono exclusivo da conexao resolved e do RoomRuntime;
	# este sinal faz o core percorrer exatamente essa API existente.
	enemy_spawned.emit(_core)
	state = State.SETTLE
	state = State.READY
	state = State.ATTACK_HANDOFF
	_start_electric_combat_loop()
	_finish_spawns()
	return true

func stop() -> void:
	if _torn_down:
		return
	_torn_down = true
	_stop_electric_combat_loop()
	_clear_encounter_children()
	_clear_electric_lifecycle()

func _physics_process(delta: float) -> void:
	if _torn_down or not _has_host_authority() or not is_instance_valid(_core): return
	_explosive_transition_just_started = false
	_advance_electric_combat_loop(delta)
	_advance_explosive_cycle(delta)
	_advance_laser_cycle(delta)
	if _explosive_cycle == ExplosiveCycle.INACTIVE and _laser_cycle == LaserCycle.INACTIVE:
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
	_stop_electric_combat_loop()
	_torn_down = true
	_clear_encounter_children()
	_clear_electric_lifecycle()
	state = State.VICTORY

func _exit_tree() -> void:
	stop()

func _clear_encounter_children() -> void:
	_release_laser_beams()
	_release_explosive_cocoons()
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

func _initialize_explosive_wings() -> void:
	if not is_instance_valid(_core) or not _has_host_authority():
		return
	_release_explosive_cocoons()
	var cocoons: Array = []
	for index in range(WING_OFFSETS.size()):
		var cocoon := CASULO_EXPLOSIVO.new() as CasuloExplosivo
		add_child(cocoon)
		_explosive_cocoons.append(cocoon)
		cocoon.set_slot_id(index + 1)
		cocoon.set_slot_position(_core.global_position + WING_OFFSETS[index])
		cocoon.configure_damage(EXPLOSIVE_DAMAGE_HEALTH_UNITS, _core, [&"explosive", &"wing"], cocoon.global_position)
		cocoons.append(cocoon)
	_explosive_formation = FORMACAO_ASAS_CONTROLLER.new() as FormacaoAsasController
	if not _explosive_formation.configure(cocoons):
		push_warning("Regente explosive wings could not configure canonical cocoon IDs.")
		_release_explosive_cocoons()

func _initialize_laser_beams(pattern := LaserPattern.SHIELD) -> void:
	_release_laser_beams()
	if not is_instance_valid(_core) or not _has_host_authority():
		return
	var offsets := _laser_offsets_for(pattern)
	var emitter_indices := _laser_emitter_indices_for(pattern)
	for index in emitter_indices:
		var offset: Vector2 = offsets[index]
		var beam := LASER_BEAM_2D.new() as LaserBeam2D
		add_child(beam)
		beam.beam_width_px = LASER_BEAM_WIDTH_PX
		beam.hit_tick_seconds = LASER_HIT_TICK_SECONDS
		beam.turn_rate_radians = LASER_TURN_RATE_RADIANS
		beam.configure(_core.global_position + offset, LASER_DAMAGE_HEALTH_UNITS, _core, _laser_damage_tags_for(pattern), LASER_COLLISION_MASK)
		_laser_beams.append(beam)

func _update_electric_slot_positions() -> void:
	var updates: Dictionary = {}
	for slot in _electric_slots:
		if bool(slot.get("occupied", false)) and int(slot.get("drone_id", -1)) > 0:
			updates[int(slot.drone_id)] = {"position": _core.global_position + _electric_slot_offset(slot), "formation_open": _electric_formation_is_open(slot)}
	if not updates.is_empty(): _core.update_electric_drone_positions(updates)

func _settle_electric_transitions() -> void:
	if _combat_formation_is_open():
		return
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

func _start_electric_combat_loop() -> void:
	if _torn_down or state != State.ATTACK_HANDOFF or not _has_host_authority():
		return
	_combat_cycle = CombatCycle.COOLDOWN
	_combat_cycle_elapsed = 0.0
	_combat_loop_active = true
	_core.set_encounter_movement_locked(false)

func _advance_electric_combat_loop(delta: float) -> void:
	if not _combat_loop_active or state != State.ATTACK_HANDOFF:
		return
	_combat_cycle_elapsed += maxf(0.0, delta)
	var transitions := 0
	while transitions < CombatCycle.size() and _combat_cycle_elapsed >= _combat_cycle_duration():
		_combat_cycle_elapsed -= _combat_cycle_duration()
		match _combat_cycle:
			CombatCycle.COOLDOWN:
				_enter_electric_combat_cycle(CombatCycle.TELEGRAPH)
			CombatCycle.TELEGRAPH:
				_enter_electric_combat_cycle(CombatCycle.ATTACK_PULSE)
			CombatCycle.ATTACK_PULSE:
				_enter_electric_combat_cycle(CombatCycle.SETTLE)
			CombatCycle.SETTLE:
				_electric_laps_completed += 1
				if _electric_laps_completed >= 1 and _begin_explosive_cycle():
					_electric_laps_completed = 0
				else:
					_enter_electric_combat_cycle(CombatCycle.COOLDOWN)
		transitions += 1

func _enter_electric_combat_cycle(next_cycle: CombatCycle) -> void:
	_combat_cycle = next_cycle
	# Telegraph and pulse freeze the root while the existing electric grid is
	# opened. SETTLE closes every slot together through the normal grid update.
	_core.set_encounter_movement_locked(_combat_formation_is_open())
	if _combat_cycle == CombatCycle.SETTLE:
		_settle_all_electric_slots()

func _combat_cycle_duration() -> float:
	match _combat_cycle:
		CombatCycle.COOLDOWN: return ELECTRIC_COOLDOWN_SECONDS
		CombatCycle.TELEGRAPH: return ELECTRIC_TELEGRAPH_SECONDS
		CombatCycle.ATTACK_PULSE: return ELECTRIC_ATTACK_PULSE_SECONDS
		CombatCycle.SETTLE: return ELECTRIC_SETTLE_SECONDS
	return ELECTRIC_COOLDOWN_SECONDS

func _combat_formation_is_open() -> bool:
	return _combat_loop_active and (_combat_cycle == CombatCycle.TELEGRAPH or _combat_cycle == CombatCycle.ATTACK_PULSE)

func _electric_formation_is_open(slot: Dictionary) -> bool:
	return _combat_formation_is_open() or bool(slot.get("transition", false))

func _electric_slot_offset(slot: Dictionary) -> Vector2:
	var base_offset := Vector2(slot.get("offset", Vector2.ZERO))
	return base_offset * ELECTRIC_OPEN_OFFSET_SCALE if _combat_formation_is_open() else base_offset

func _settle_all_electric_slots() -> void:
	if not is_instance_valid(_core) or not _has_host_authority():
		return
	var updates: Dictionary = {}
	var settling_slots: Array[Dictionary] = []
	for slot in _electric_slots:
		if not bool(slot.get("occupied", false)) or int(slot.get("drone_id", -1)) < 1:
			continue
		updates[int(slot.drone_id)] = {"position": _core.global_position + Vector2(slot.offset), "formation_open": false}
		if bool(slot.get("transition", false)):
			settling_slots.append(slot)
	if not updates.is_empty():
		_core.update_electric_drone_positions(updates)
	for slot in settling_slots:
		slot.transition = false

func _stop_electric_combat_loop() -> void:
	_combat_loop_active = false
	_combat_cycle_elapsed = 0.0
	_combat_cycle = CombatCycle.COOLDOWN
	if not is_instance_valid(_core):
		return
	_core.set_encounter_movement_locked(false)
	# Restore flags before grid teardown; no post-teardown updates are possible.
	_settle_all_electric_slots()

func _begin_explosive_cycle() -> bool:
	if _torn_down or not is_instance_valid(_core) or _explosive_formation == null or not _all_explosive_slots_available():
		return false
	_combat_loop_active = false
	_combat_cycle_elapsed = 0.0
	_combat_cycle = CombatCycle.COOLDOWN
	_explosive_cycle = ExplosiveCycle.TRANSITION
	_explosive_elapsed = 0.0
	_explosive_bank_index = 0
	_explosive_tracking_origins.clear()
	_explosive_transition_just_started = true
	_core.set_encounter_movement_locked(true)
	return true

func _advance_explosive_cycle(delta: float) -> void:
	if _explosive_cycle == ExplosiveCycle.INACTIVE:
		return
	if _explosive_transition_just_started:
		return
	if _torn_down or not is_instance_valid(_core) or not _all_explosive_slots_available():
		_abort_explosive_cycle()
		return
	_explosive_elapsed += maxf(0.0, delta)
	var transitions := 0
	while _explosive_cycle != ExplosiveCycle.INACTIVE and transitions < 8 and _explosive_elapsed >= _explosive_cycle_duration():
		_explosive_elapsed -= _explosive_cycle_duration()
		match _explosive_cycle:
			ExplosiveCycle.TRANSITION:
				_start_explosive_tracking()
			ExplosiveCycle.TRACKING:
				_lock_explosive_bank()
			ExplosiveCycle.LOCKED:
				_detonate_explosive_bank()
			ExplosiveCycle.DETONATION:
				_explosive_cycle = ExplosiveCycle.BANK_INTERVAL if _explosive_bank_index < FormacaoAsasController.BANK_ORDER.size() - 1 else ExplosiveCycle.RECONSTITUTE
			ExplosiveCycle.BANK_INTERVAL:
				_explosive_bank_index += 1
				_start_explosive_tracking()
			ExplosiveCycle.RECONSTITUTE:
				_finish_explosive_cycle()
		transitions += 1
	if _explosive_cycle == ExplosiveCycle.TRACKING:
		_update_explosive_tracking()

func _explosive_cycle_duration() -> float:
	match _explosive_cycle:
		ExplosiveCycle.TRANSITION: return EXPLOSIVE_TRANSITION_SECONDS
		ExplosiveCycle.TRACKING: return EXPLOSIVE_TRACKING_SECONDS
		ExplosiveCycle.LOCKED: return EXPLOSIVE_LOCKED_SECONDS
		ExplosiveCycle.DETONATION: return EXPLOSIVE_DETONATION_SECONDS
		ExplosiveCycle.BANK_INTERVAL: return EXPLOSIVE_BANK_INTERVAL_SECONDS
		ExplosiveCycle.RECONSTITUTE: return EXPLOSIVE_RECONSTITUTE_SECONDS
	return 0.0

func _start_explosive_tracking() -> void:
	if _explosive_bank_index >= FormacaoAsasController.BANK_ORDER.size():
		_abort_explosive_cycle()
		return
	var bank: StringName = FormacaoAsasController.BANK_ORDER[_explosive_bank_index]
	var positions := _explosive_bank_slot_positions(bank)
	_explosive_tracking_origins = positions.duplicate(true)
	if not _explosive_formation.begin_tracking_bank(bank, positions):
		_abort_explosive_cycle()
		return
	_explosive_cycle = ExplosiveCycle.TRACKING

func _update_explosive_tracking() -> void:
	var bank: StringName = FormacaoAsasController.BANK_ORDER[_explosive_bank_index]
	var target := _player_target_position()
	var weight := clampf(_explosive_elapsed / EXPLOSIVE_TRACKING_SECONDS, 0.0, 1.0)
	var positions: Dictionary = {}
	for cocoon_id in FormacaoAsasController.BANKS[bank]:
		var origin: Vector2 = _explosive_tracking_origins.get(cocoon_id, _core.global_position)
		# Target is sampled on the host; origin + normalized phase makes the path deterministic.
		positions[cocoon_id] = origin.lerp(target, weight)
	if not _explosive_formation.update_tracking_bank(bank, positions):
		_abort_explosive_cycle()

func _lock_explosive_bank() -> void:
	var bank: StringName = FormacaoAsasController.BANK_ORDER[_explosive_bank_index]
	# Consume the complete tracking phase before freezing: a zero-remainder
	# physics frame still locks at the host's last sampled player position.
	var terminal_positions: Dictionary = {}
	var terminal_target := _player_target_position()
	for cocoon_id in FormacaoAsasController.BANKS[bank]:
		terminal_positions[cocoon_id] = terminal_target
	if not _explosive_formation.update_tracking_bank(bank, terminal_positions):
		_abort_explosive_cycle()
		return
	var positions: Dictionary = {}
	for cocoon_id in FormacaoAsasController.BANKS[bank]:
		var cocoon := _explosive_formation.get_cocoon(cocoon_id) as CasuloExplosivo
		if cocoon == null:
			_abort_explosive_cycle()
			return
		positions[cocoon_id] = cocoon.global_position
	if not _explosive_formation.lock_bank(bank, positions):
		_abort_explosive_cycle()
		return
	_explosive_cycle = ExplosiveCycle.LOCKED

func _detonate_explosive_bank() -> void:
	var bank: StringName = FormacaoAsasController.BANK_ORDER[_explosive_bank_index]
	var overlaps: Dictionary = {}
	for cocoon_id in FormacaoAsasController.BANKS[bank]:
		var cocoon := _explosive_formation.get_cocoon(cocoon_id) as CasuloExplosivo
		if cocoon == null:
			_abort_explosive_cycle()
			return
		cocoon.configure_damage(EXPLOSIVE_DAMAGE_HEALTH_UNITS, _core, [&"explosive", &"wing"], cocoon.locked_position)
		overlaps[cocoon_id] = _query_explosive_targets(cocoon.locked_position)
	if not _explosive_formation.fire_bank(bank, overlaps):
		_abort_explosive_cycle()
		return
	_explosive_cycle = ExplosiveCycle.DETONATION

func _query_explosive_targets(position: Vector2) -> Array[Node]:
	if _torn_down or not is_instance_valid(_core):
		return []
	var shape := CircleShape2D.new()
	shape.radius = EXPLOSIVE_RADIUS_PX
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, position)
	query.collision_mask = EXPLOSIVE_COLLISION_MASK
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var targets: Array[Node] = []
	for result in _core.get_world_2d().direct_space_state.intersect_shape(query):
		var collider := result.get("collider") as Node
		if _is_explosive_damage_target(collider):
			targets.append(collider)
	return targets

func _is_explosive_damage_target(target: Node) -> bool:
	if target == null or not is_instance_valid(target) or target.is_queued_for_deletion():
		return false
	if not (target.is_in_group(&"player") or target.is_in_group(&"enemies")) or not target.has_method(&"take_damage"):
		return false
	return target.get("health") is HealthComponent or target.get_node_or_null("HealthComponent") is HealthComponent

func _player_target_position() -> Vector2:
	var player := _player_target_node()
	if player != null:
		return player.global_position
	return _core.global_position

func _player_target_node() -> Node2D:
	for player in get_tree().get_nodes_in_group(&"player"):
		if player is Node2D and is_instance_valid(player) and not player.is_queued_for_deletion():
			return player as Node2D
	return null

func _explosive_bank_slot_positions(bank: StringName) -> Dictionary:
	var positions: Dictionary = {}
	for cocoon_id in FormacaoAsasController.BANKS[bank]:
		var slot_index := int(cocoon_id) - 1
		positions[cocoon_id] = _core.global_position + WING_OFFSETS[slot_index]
		var cocoon := _explosive_formation.get_cocoon(cocoon_id) as CasuloExplosivo
		if cocoon != null:
			cocoon.set_slot_position(positions[cocoon_id])
	return positions

func _all_explosive_slots_available() -> bool:
	if _electric_slots.size() != WING_OFFSETS.size() or not is_instance_valid(_core):
		return false
	var active_ids: Dictionary = {}
	for drone_id in _core.electric_drone_ids():
		active_ids[drone_id] = true
	for slot in _electric_slots:
		if not bool(slot.get("occupied", false)) or not active_ids.has(int(slot.get("drone_id", -1))):
			return false
	return true

func _abort_explosive_cycle() -> void:
	if _explosive_formation != null:
		_explosive_formation.cancel_sequence()
	_explosive_cycle = ExplosiveCycle.INACTIVE
	_explosive_elapsed = 0.0
	_explosive_bank_index = 0
	_explosive_tracking_origins.clear()
	_explosive_transition_just_started = false
	if is_instance_valid(_core):
		_core.set_encounter_movement_locked(false)
	# Missing external drones remain owned by the existing global replacement flow.
	if not _torn_down:
		_start_electric_combat_loop()

func _finish_explosive_cycle() -> void:
	if _explosive_formation == null or not _explosive_formation.reconstitute_all():
		_abort_explosive_cycle()
		return
	_explosive_cycle = ExplosiveCycle.INACTIVE
	_explosive_elapsed = 0.0
	_explosive_bank_index = 0
	_explosive_tracking_origins.clear()
	_explosive_transition_just_started = false
	_restore_explosive_slot_positions()
	_settle_all_electric_slots()
	# Combined-loop order is deterministic: Shield, then Bow, with an electric
	# lap between attacks. No RNG or phase gate participates in this slice.
	if not _begin_laser_cycle():
		_start_electric_combat_loop()

func _begin_laser_cycle() -> bool:
	if _torn_down or not is_instance_valid(_core) or not _all_explosive_slots_available():
		return false
	_laser_pattern = _next_laser_pattern
	_initialize_laser_beams(_laser_pattern)
	if _laser_beams.size() != _laser_emitter_indices_for(_laser_pattern).size():
		return false
	_combat_loop_active = false
	_combat_cycle_elapsed = 0.0
	_laser_cycle = LaserCycle.TRANSITION
	_laser_elapsed = 0.0
	_laser_bank_index = 0
	_set_laser_pattern_positions()
	_core.set_encounter_movement_locked(true)
	return true

func _advance_laser_cycle(delta: float) -> void:
	if _laser_cycle == LaserCycle.INACTIVE:
		return
	if _torn_down or not is_instance_valid(_core) or not _all_explosive_slots_available():
		_abort_laser_cycle()
		return
	_set_laser_tracking_target()
	_laser_elapsed += maxf(0.0, delta)
	var transitions := 0
	while _laser_cycle != LaserCycle.INACTIVE and transitions < 5 and _laser_elapsed >= _laser_cycle_duration():
		_laser_elapsed -= _laser_cycle_duration()
		match _laser_cycle:
			LaserCycle.TRANSITION: _start_laser_telegraph()
			LaserCycle.TELEGRAPH: _start_laser_firing()
			LaserCycle.FIRING: _stop_laser_firing()
			LaserCycle.RECOVERY: _finish_laser_cycle()
		transitions += 1

func _laser_cycle_duration() -> float:
	match _laser_cycle:
		LaserCycle.TRANSITION: return LASER_TRANSITION_SECONDS
		LaserCycle.TELEGRAPH: return LASER_WINGS_BANK_TELEGRAPH_SECONDS if _laser_pattern == LaserPattern.WINGS else LASER_TELEGRAPH_SECONDS
		LaserCycle.FIRING: return LASER_WINGS_BANK_FIRE_SECONDS if _laser_pattern == LaserPattern.WINGS else LASER_FIRE_SECONDS
		LaserCycle.RECOVERY: return LASER_RECOVERY_SECONDS
	return 0.0

func _start_laser_telegraph() -> void:
	for beam in _active_laser_beams():
		if not is_instance_valid(beam) or not beam.start_telegraph():
			_abort_laser_cycle()
			return
	_laser_cycle = LaserCycle.TELEGRAPH

func _start_laser_firing() -> void:
	for beam in _active_laser_beams():
		if not is_instance_valid(beam):
			_abort_laser_cycle()
			return
		# WINGS captures the aim after its own telegraph. Unlike SHIELD/BOW,
		# each bank must remain fixed throughout its damage window.
		if _laser_pattern == LaserPattern.WINGS:
			beam.freeze_tracking()
		if not beam.start_firing():
			_abort_laser_cycle()
			return
	_laser_cycle = LaserCycle.FIRING

func _stop_laser_firing() -> void:
	for beam in _active_laser_beams():
		if is_instance_valid(beam): beam.stop()
	if _laser_pattern == LaserPattern.WINGS and _laser_bank_index < 2:
		_laser_bank_index += 1
		_start_laser_telegraph()
		return
	_laser_cycle = LaserCycle.RECOVERY

func _finish_laser_cycle() -> void:
	_laser_cycle = LaserCycle.INACTIVE
	_laser_elapsed = 0.0
	_laser_bank_index = 0
	_next_laser_pattern = LaserPattern.BOW if _laser_pattern == LaserPattern.SHIELD else LaserPattern.SHIELD
	_restore_explosive_slot_positions()
	_settle_all_electric_slots()
	if is_instance_valid(_core): _core.set_encounter_movement_locked(false)
	_start_electric_combat_loop()

func _abort_laser_cycle() -> void:
	for beam in _laser_beams:
		if is_instance_valid(beam): beam.stop()
	_laser_cycle = LaserCycle.INACTIVE
	_laser_elapsed = 0.0
	_laser_bank_index = 0
	if is_instance_valid(_core): _core.set_encounter_movement_locked(false)
	if not _torn_down: _start_electric_combat_loop()

func _set_laser_shield_positions() -> void:
	_set_laser_positions(LASER_SHIELD_OFFSETS)

func _set_laser_pattern_positions() -> void:
	_set_laser_positions(_laser_offsets_for(_laser_pattern))

func _set_laser_positions(offsets: Array[Vector2]) -> void:
	var updates: Dictionary = {}
	for index in range(offsets.size()):
		var slot := _electric_slots[index]
		if bool(slot.get("occupied", false)):
			updates[int(slot.get("drone_id", -1))] = {"position": _core.global_position + offsets[index], "formation_open": false}
	if not updates.is_empty(): _core.update_electric_drone_positions(updates)

func _laser_offsets_for(pattern: LaserPattern) -> Array[Vector2]:
	if pattern == LaserPattern.BOW:
		return LASER_BOW_OFFSETS
	if pattern == LaserPattern.WINGS:
		return WING_OFFSETS
	return LASER_SHIELD_OFFSETS

func _laser_emitter_indices_for(pattern: LaserPattern) -> Array[int]:
	var indices: Array[int] = []
	if pattern == LaserPattern.BOW:
		indices.append(LASER_BOW_EMITTER_INDEX)
		return indices
	if pattern == LaserPattern.WINGS:
		for index in range(WING_OFFSETS.size()):
			indices.append(index)
		return indices
	for index in range(LASER_SHIELD_OFFSETS.size()):
		indices.append(index)
	return indices

func _laser_damage_tags_for(pattern: LaserPattern) -> Array[StringName]:
	var tags: Array[StringName] = [&"laser"]
	tags.append(&"bow" if pattern == LaserPattern.BOW else (&"wings" if pattern == LaserPattern.WINGS else &"shield"))
	return tags

func _set_laser_tracking_target() -> void:
	if _laser_pattern == LaserPattern.WINGS and _laser_cycle == LaserCycle.FIRING:
		return
	var target := _player_target_node()
	for beam in _laser_beams:
		if is_instance_valid(beam): beam.set_tracking_target(target)

func _active_laser_beams() -> Array[LaserBeam2D]:
	if _laser_pattern != LaserPattern.WINGS:
		return _laser_beams
	var active: Array[LaserBeam2D] = []
	for index in _laser_wings_bank_indices():
		if index >= 0 and index < _laser_beams.size():
			active.append(_laser_beams[index])
	return active

## Observation hook: the active WINGS bank is always one disjoint group of four.
func _laser_wings_bank_indices() -> Array[int]:
	match _laser_bank_index:
		0: return LASER_WINGS_BANK_A
		1: return LASER_WINGS_BANK_B
		2: return LASER_WINGS_BANK_F
	return []

func _restore_explosive_slot_positions() -> void:
	if _explosive_formation == null or not is_instance_valid(_core):
		return
	for index in range(WING_OFFSETS.size()):
		var cocoon := _explosive_formation.get_cocoon(index + 1) as CasuloExplosivo
		if cocoon != null:
			cocoon.set_slot_position(_core.global_position + WING_OFFSETS[index])

## Observation-only contract for runtime tests; no renderer or replication is added.
func explosive_runtime_snapshot() -> Dictionary:
	return {"cycle": _explosive_cycle, "elapsed": _explosive_elapsed, "bank_index": _explosive_bank_index, "formation": _explosive_formation.runtime_snapshot() if _explosive_formation != null else {}}

## Observation-only hook for the first laser slice; no renderer/RPC is added.
func laser_runtime_snapshot() -> Dictionary:
	var beams: Array[Dictionary] = []
	for beam in _laser_beams:
		if is_instance_valid(beam):
			beams.append(beam.runtime_snapshot())
	return {"cycle": _laser_cycle, "elapsed": _laser_elapsed, "pattern": _laser_pattern, "next_pattern": _next_laser_pattern, "bank_index": _laser_bank_index, "active_emitter_indices": _laser_wings_bank_indices() if _laser_pattern == LaserPattern.WINGS else _laser_emitter_indices_for(_laser_pattern), "beams": beams}

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
	_electric_laps_completed = 0
	_explosive_elapsed = 0.0
	_explosive_bank_index = 0
	_explosive_tracking_origins.clear()
	_explosive_cycle = ExplosiveCycle.INACTIVE
	_explosive_transition_just_started = false
	_laser_cycle = LaserCycle.INACTIVE
	_laser_elapsed = 0.0
	_laser_bank_index = 0
	_laser_pattern = LaserPattern.SHIELD
	_next_laser_pattern = LaserPattern.SHIELD
	_release_explosive_cocoons()
	_release_laser_beams()

func _release_explosive_cocoons() -> void:
	if _explosive_formation != null:
		_explosive_formation.cancel_sequence()
	_explosive_formation = null
	for cocoon in _explosive_cocoons:
		if is_instance_valid(cocoon) and not cocoon.is_queued_for_deletion():
			cocoon.queue_free()
	_explosive_cocoons.clear()

func _release_laser_beams() -> void:
	for beam in _laser_beams:
		if is_instance_valid(beam):
			beam.cleanup()
			if not beam.is_queued_for_deletion(): beam.queue_free()
	_laser_beams.clear()

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
