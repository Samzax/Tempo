extends GutTest

const ORCHESTRATOR := preload("res://scripts/enemies/bosses/regente_encounter_orchestrator.gd")
const LASER := preload("res://scripts/enemies/bosses/wings/laser_beam_2d.gd")

class NonAuthority extends RegenteEncounterOrchestrator:
	func _has_host_authority() -> bool: return false

func _fixture(host := true) -> Dictionary:
	var o := ORCHESTRATOR.new() if host else NonAuthority.new()
	var enemies := Node2D.new()
	add_child_autofree(o); add_child_autofree(enemies)
	o.set_enemy_container(enemies)
	return {"o": o, "enemies": enemies}

func _start_wings(o: RegenteEncounterOrchestrator) -> void:
	assert_true(o.start(0))
	o._next_laser_pattern = o.LaserPattern.WINGS
	assert_true(o._begin_laser_cycle())

func _advance_to_firing(o: RegenteEncounterOrchestrator, initial_bank := false) -> void:
	if initial_bank:
		o._advance_laser_cycle(o.LASER_TRANSITION_SECONDS)
	o._advance_laser_cycle(o.LASER_WINGS_BANK_TELEGRAPH_SECONDS)
	assert_eq(o._laser_cycle, o.LaserCycle.FIRING)

func test_wings_pattern_has_canonical_offsets_and_three_disjoint_four_beam_banks() -> void:
	var f := _fixture(); var o: RegenteEncounterOrchestrator = f.o
	_start_wings(o)
	assert_eq(o.LaserPattern.WINGS, 2)
	assert_eq(o.WING_OFFSETS.size(), 12)
	assert_eq(o._laser_beams.size(), 12)
	assert_eq(o._laser_offsets_for(o.LaserPattern.WINGS), o.WING_OFFSETS)
	var all_slots: Array[int] = []
	for i in 12: all_slots.append(i)
	assert_eq(o._laser_emitter_indices_for(o.LaserPattern.WINGS), all_slots)
	var banks := [o.LASER_WINGS_BANK_A, o.LASER_WINGS_BANK_B, o.LASER_WINGS_BANK_F]
	var used := {}
	for bank in banks:
		assert_eq(bank.size(), 4)
		for index in bank:
			assert_false(used.has(index))
			used[index] = true
	assert_eq(used.size(), 12)
	for i in 12:
		assert_eq(o._electric_slots[i].offset, o.WING_OFFSETS[i])
		assert_eq(o._laser_beams[i].fixed_origin, o._core.global_position + o.WING_OFFSETS[i])

func test_wings_activates_a_then_b_then_f_with_only_four_active_and_no_reuse() -> void:
	var f := _fixture(); var o: RegenteEncounterOrchestrator = f.o
	_start_wings(o)
	var expected := [o.LASER_WINGS_BANK_A, o.LASER_WINGS_BANK_B, o.LASER_WINGS_BANK_F]
	for bank_index in expected.size():
		var bank = expected[bank_index]
		_advance_to_firing(o, bank_index == 0)
		assert_eq(o.laser_runtime_snapshot().active_emitter_indices, bank)
		var active := []
		for i in 12:
			if o._laser_beams[i].state != LASER.State.INACTIVE: active.append(i)
		assert_eq(active, bank)
		o._advance_laser_cycle(o.LASER_WINGS_BANK_FIRE_SECONDS)
		for i in bank: assert_eq(o._laser_beams[i].state, LASER.State.INACTIVE)
		if bank != o.LASER_WINGS_BANK_F: assert_eq(o._laser_cycle, o.LaserCycle.TELEGRAPH)
	assert_eq(o._laser_cycle, o.LaserCycle.RECOVERY)
	for beam in o._laser_beams: assert_eq(beam.state, LASER.State.INACTIVE)

func test_wings_freezes_each_bank_snapshot_but_shield_and_bow_keep_tracking_contract() -> void:
	var f := _fixture(); var o: RegenteEncounterOrchestrator = f.o
	var target := Node2D.new(); target.add_to_group(&"player"); add_child_autofree(target)
	_start_wings(o); o._set_laser_tracking_target()
	_advance_to_firing(o, true)
	var beam := o._laser_beams[o.LASER_WINGS_BANK_A[0]]
	var frozen_rotation := beam.global_rotation
	target.global_position = o._core.global_position + Vector2(0, 300)
	o._set_laser_tracking_target(); beam._physics_process(0.1)
	assert_eq(beam.global_rotation, frozen_rotation)
	assert_eq(o._laser_pattern, o.LaserPattern.WINGS)
	# Existing SHIELD/BOW tests exercise tracking; this assertion guards selection.
	o._abort_laser_cycle(); o._next_laser_pattern = o.LaserPattern.SHIELD
	assert_true(o._begin_laser_cycle()); assert_eq(o._laser_pattern, o.LaserPattern.SHIELD)
	o._abort_laser_cycle(); o._next_laser_pattern = o.LaserPattern.BOW
	assert_true(o._begin_laser_cycle()); assert_eq(o._laser_pattern, o.LaserPattern.BOW)

func test_wings_damage_contract_is_25_health_units_local_dedupe_host_authority_and_mask_6() -> void:
	var f := _fixture(); var o: RegenteEncounterOrchestrator = f.o
	_start_wings(o)
	for beam in o._laser_beams:
		assert_eq(beam.damage_amount, 25)
		assert_eq(beam.collision_mask, 6)
	assert_eq(o.LASER_DAMAGE_HEALTH_UNITS, 25)
	var remote := _fixture(false); var remote_o: RegenteEncounterOrchestrator = remote.o
	assert_true(remote_o.start(0)); remote_o._next_laser_pattern = remote_o.LaserPattern.WINGS
	assert_false(remote_o._begin_laser_cycle())

func test_wings_aborts_on_incomplete_slots_and_cleanup_releases_all_beams() -> void:
	var f := _fixture(); var o: RegenteEncounterOrchestrator = f.o
	_start_wings(o); o._electric_slots[4].occupied = false
	o._advance_laser_cycle(0.1)
	assert_eq(o._laser_cycle, o.LaserCycle.INACTIVE)
	o.stop(); await get_tree().process_frame
	assert_eq(o._laser_beams.size(), 0)
	for child in o.get_children(): assert_false(child is LASER)

func test_wings_recovery_returns_to_electric_loop() -> void:
	var f := _fixture(); var o: RegenteEncounterOrchestrator = f.o
	_start_wings(o)
	for bank_index in 3:
		_advance_to_firing(o, bank_index == 0)
		o._advance_laser_cycle(o.LASER_WINGS_BANK_FIRE_SECONDS)
	o._advance_laser_cycle(o.LASER_RECOVERY_SECONDS)
	assert_eq(o._laser_cycle, o.LaserCycle.INACTIVE)
	assert_true(o._combat_loop_active)
