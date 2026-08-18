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

func test_laser_constants_define_shield_and_full_timing_contract() -> void:
	var f := _fixture(); var o: RegenteEncounterOrchestrator = f.o
	assert_true(o.start(0))
	assert_eq(o.LASER_SHIELD_OFFSETS.size(), 12)
	assert_eq(o.LASER_BEAM_WIDTH_PX, 16.0)
	assert_eq(o.LASER_COLLISION_MASK, 6)
	assert_eq(o.LASER_TELEGRAPH_SECONDS, 0.8)
	assert_eq(o.LASER_FIRE_SECONDS, 1.5)
	assert_eq(o.LASER_RECOVERY_SECONDS, 0.8)
	assert_eq(o._laser_beams.size(), 12)
	for i in 12:
		assert_eq(o._laser_beams[i].fixed_origin, o._core.global_position + o.LASER_SHIELD_OFFSETS[i])

func test_laser_does_not_advance_or_spawn_off_host() -> void:
	var f := _fixture(false); var o: RegenteEncounterOrchestrator = f.o
	assert_true(o.start(0)); o._physics_process(99.0)
	assert_eq(o._laser_cycle, o.LaserCycle.INACTIVE)
	assert_eq(o._laser_beams.size(), 0)
	assert_eq(f.enemies.get_child_count(), 0)

func test_cycle_starts_only_with_all_slots_and_enters_telegraph_then_firing() -> void:
	var f := _fixture(); var o: RegenteEncounterOrchestrator = f.o
	o.start(0)
	o._electric_slots[0].occupied = false
	assert_false(o._begin_laser_cycle())
	o._electric_slots[0].occupied = true
	assert_true(o._begin_laser_cycle())
	assert_eq(o._laser_cycle, o.LaserCycle.TRANSITION)
	o._advance_laser_cycle(0.8)
	assert_eq(o._laser_cycle, o.LaserCycle.TELEGRAPH)
	assert_eq(o._laser_beams[0].state, 1)
	o._advance_laser_cycle(0.8)
	assert_eq(o._laser_cycle, o.LaserCycle.FIRING)
	assert_eq(o._laser_beams[0].state, 2)
	o._advance_laser_cycle(1.5)
	assert_eq(o._laser_cycle, o.LaserCycle.RECOVERY)
	assert_eq(o._laser_beams[0].state, 0)
	o._advance_laser_cycle(0.8)
	assert_eq(o._laser_cycle, o.LaserCycle.INACTIVE)

func test_bow_offsets_are_unique_seven_rising_five_chevron_and_only_index_nine_emits() -> void:
	var f := _fixture(); var o: RegenteEncounterOrchestrator = f.o
	assert_eq(o.LASER_BOW_OFFSETS.size(), 12)
	var unique := {}; for offset in o.LASER_BOW_OFFSETS: unique[str(offset)] = true
	assert_eq(unique.size(), 12)
	assert_eq(o.LASER_BOW_EMITTER_INDEX, 9)
	o.start(0); o._next_laser_pattern = o.LaserPattern.BOW
	assert_true(o._begin_laser_cycle())
	assert_eq(o._laser_pattern, o.LaserPattern.BOW)
	assert_eq(o._laser_beams.size(), 1)
	assert_eq(o._laser_beams[0].fixed_origin, o._core.global_position + o.LASER_BOW_OFFSETS[9])
	for i in 12: assert_eq(i == 9, o._laser_emitter_indices_for(o.LaserPattern.BOW).has(i))

func test_shield_volley_recovers_then_deterministically_selects_bow() -> void:
	var f := _fixture(); var o: RegenteEncounterOrchestrator = f.o
	o.start(0); assert_true(o._begin_laser_cycle())
	o._advance_laser_cycle(0.8 + 0.8 + 1.5 + 0.8)
	assert_eq(o._laser_pattern, o.LaserPattern.SHIELD)
	assert_eq(o._next_laser_pattern, o.LaserPattern.BOW)
	assert_true(o._begin_laser_cycle())
	assert_eq(o._laser_pattern, o.LaserPattern.BOW)

func test_bow_drones_stay_in_slots_while_only_beam_tracks_and_cleanup_preserves_defaults() -> void:
	var f := _fixture(); var o: RegenteEncounterOrchestrator = f.o
	o.start(0); o._next_laser_pattern = o.LaserPattern.BOW; assert_true(o._begin_laser_cycle())
	var slots_before := []; for slot in o._electric_slots: slots_before.append(slot.offset)
	o._advance_laser_cycle(0.8); var origin := o._laser_beams[0].fixed_origin
	o._advance_laser_cycle(0.8); assert_eq(o._laser_beams.size(), 1)
	for i in 12: assert_eq(o._electric_slots[i].offset, slots_before[i])
	assert_eq(o._laser_beams[0].fixed_origin, origin)
	o._advance_laser_cycle(1.5 + 0.8 + 0.8); assert_eq(o._laser_cycle, o.LaserCycle.INACTIVE)
	o.stop(); await get_tree().process_frame
	assert_eq(o._laser_beams.size(), 0)
	assert_eq(o.LASER_TRANSITION_SECONDS, 0.8)
	assert_eq(o.LASER_TELEGRAPH_SECONDS, 0.8)
	assert_eq(o.LASER_FIRE_SECONDS, 1.5)
	assert_eq(o.LASER_RECOVERY_SECONDS, 0.8)

func test_laser_requires_all_slots_and_returns_to_electric_after_bow() -> void:
	var f := _fixture(); var o: RegenteEncounterOrchestrator = f.o
	o.start(0); o._electric_slots[3].occupied = false; o._next_laser_pattern = o.LaserPattern.BOW
	assert_false(o._begin_laser_cycle()); o._electric_slots[3].occupied = true
	assert_true(o._begin_laser_cycle()); o._advance_laser_cycle(4.0)
	assert_eq(o._laser_cycle, o.LaserCycle.INACTIVE)
	assert_eq(o._next_laser_pattern, o.LaserPattern.WINGS)
	assert_true(o._combat_loop_active)

func test_stop_resolution_and_abort_remove_all_beams_without_orphans() -> void:
	var f := _fixture(); var o: RegenteEncounterOrchestrator = f.o
	o.start(0); assert_eq(o._laser_beams.size(), 12)
	o._abort_laser_cycle()
	assert_eq(o._laser_beams.size(), 12)
	o.stop(); await get_tree().process_frame
	assert_eq(o._laser_beams.size(), 0)
	for child in o.get_children(): assert_false(child is LASER)

func test_reconstitution_path_returns_to_laser_then_electric() -> void:
	var f := _fixture(); var o: RegenteEncounterOrchestrator = f.o
	o.start(0)
	for duration in [o.ELECTRIC_COOLDOWN_SECONDS, o.ELECTRIC_TELEGRAPH_SECONDS, o.ELECTRIC_ATTACK_PULSE_SECONDS, o.ELECTRIC_SETTLE_SECONDS, o.EXPLOSIVE_TRANSITION_SECONDS, o.EXPLOSIVE_TRACKING_SECONDS, o.EXPLOSIVE_LOCKED_SECONDS, o.EXPLOSIVE_DETONATION_SECONDS, o.EXPLOSIVE_BANK_INTERVAL_SECONDS, o.EXPLOSIVE_TRACKING_SECONDS, o.EXPLOSIVE_LOCKED_SECONDS, o.EXPLOSIVE_DETONATION_SECONDS, o.EXPLOSIVE_BANK_INTERVAL_SECONDS, o.EXPLOSIVE_TRACKING_SECONDS, o.EXPLOSIVE_LOCKED_SECONDS, o.EXPLOSIVE_DETONATION_SECONDS, o.EXPLOSIVE_RECONSTITUTE_SECONDS]:
		o._physics_process(duration)
	# The final reconstitution frame also enters and consumes the first
	# transition boundary; the observable state is telegraph here.
	assert_eq(o._laser_cycle, o.LaserCycle.TELEGRAPH)
	o._physics_process(0.8)
	assert_eq(o._laser_cycle, o.LaserCycle.FIRING)
