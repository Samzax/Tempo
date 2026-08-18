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

func _start_rift(o: RegenteEncounterOrchestrator) -> void:
	assert_true(o.start(0))
	o._next_laser_pattern = o.LaserPattern.RIFT
	assert_true(o._begin_laser_cycle())

func _to_rift_firing(o: RegenteEncounterOrchestrator) -> void:
	o._advance_laser_cycle(o.LASER_TRANSITION_SECONDS)
	assert_eq(o._laser_cycle, o.LaserCycle.TELEGRAPH)
	o._advance_laser_cycle(o.LASER_TELEGRAPH_SECONDS)
	assert_eq(o._laser_cycle, o.LaserCycle.FIRING)

func _active_beams(o: RegenteEncounterOrchestrator) -> Array:
	var result := []
	for beam in o._laser_beams:
		if is_instance_valid(beam) and beam.state != LASER.State.INACTIVE: result.append(beam)
	return result

func _advance_until_laser_starts(o: RegenteEncounterOrchestrator) -> void:
	for _step in 80:
		o._physics_process(1.0)
		if o._laser_cycle != o.LaserCycle.INACTIVE: return
	assert_true(false, "automatic scheduler did not reach a laser cycle")

func _advance_laser_to_electric(o: RegenteEncounterOrchestrator) -> void:
	for _step in 80:
		o._physics_process(1.0)
		if o._laser_cycle == o.LaserCycle.INACTIVE and o._combat_loop_active: return
	assert_true(false, "laser cycle did not return to electric combat")

func test_rift_has_twelve_slots_curve_and_broken_edge() -> void:
	var f := _fixture(); var o: RegenteEncounterOrchestrator = f.o
	assert_eq(o.LaserPattern.RIFT, 3)
	assert_eq(o.LASER_RIFT_OFFSETS.size(), 12)
	assert_eq(o.LASER_RIFT_ZIPPER_LINKS, [Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3), Vector2i(3, 4), Vector2i(4, 5), Vector2i(5, 6)])
	assert_eq(o.LASER_RIFT_FINAL_LINKS, [Vector2i(0, 7), Vector2i(7, 8), Vector2i(8, 9)])
	assert_eq(o._laser_offsets_for(o.LaserPattern.RIFT), o.LASER_RIFT_OFFSETS)

func test_rift_requires_all_slots_and_host_authority() -> void:
	var f := _fixture(); var o: RegenteEncounterOrchestrator = f.o
	o.start(0); o._next_laser_pattern = o.LaserPattern.RIFT; o._electric_slots[11].occupied = false
	assert_false(o._begin_laser_cycle())
	var remote := _fixture(false); var remote_o: RegenteEncounterOrchestrator = remote.o
	assert_true(remote_o.start(0)); remote_o._next_laser_pattern = remote_o.LaserPattern.RIFT
	assert_false(remote_o._begin_laser_cycle())
	assert_eq(remote_o._laser_beams.size(), 0)

func test_rift_zipper_is_two_adjacent_links_root_to_apex_without_overlap() -> void:
	var f := _fixture(); var o: RegenteEncounterOrchestrator = f.o
	_start_rift(o); _to_rift_firing(o)
	for step in 5:
		assert_eq(o.rift_runtime_snapshot().active_beam_count, 2)
		assert_eq(o._laser_beams[0].fixed_origin, o._core.global_position + o.LASER_RIFT_OFFSETS[step])
		assert_eq(o._laser_beams[1].fixed_origin, o._core.global_position + o.LASER_RIFT_OFFSETS[step + 1])
		assert_eq(o._laser_beams[0].beam_length_px, (o.LASER_RIFT_OFFSETS[step + 1] - o.LASER_RIFT_OFFSETS[step]).length())
		o._advance_laser_cycle(o.LASER_RIFT_ZIPPER_STEP_SECONDS + o.LASER_RIFT_ZIPPER_HOLD_SECONDS)
	assert_eq(o._rift_phase, o.RiftPhase.FLUSH)
	assert_eq(o._laser_beams.size(), 0)

func test_rift_final_is_exactly_three_edge_links_and_apex_tangent_max_four() -> void:
	var f := _fixture(); var o: RegenteEncounterOrchestrator = f.o
	_start_rift(o); _to_rift_firing(o)
	o._advance_laser_cycle((o.LASER_RIFT_ZIPPER_STEP_SECONDS + o.LASER_RIFT_ZIPPER_HOLD_SECONDS) * 5)
	assert_eq(o._rift_phase, o.RiftPhase.FLUSH); assert_eq(o._laser_beams.size(), 0)
	o._advance_laser_cycle(o.LASER_RIFT_FLUSH_SECONDS)
	assert_eq(o._rift_phase, o.RiftPhase.FINAL); assert_eq(o._laser_beams.size(), 4)
	var expected := o.LASER_RIFT_FINAL_LINKS
	for i in 3:
		assert_eq(o._laser_beams[i].fixed_origin, o._core.global_position + o.LASER_RIFT_OFFSETS[expected[i].x])
		assert_eq(o._laser_beams[i].beam_length_px, (o.LASER_RIFT_OFFSETS[expected[i].y] - o.LASER_RIFT_OFFSETS[expected[i].x]).length())
	var tangent := o._laser_beams[3]
	assert_eq(tangent.fixed_origin, o._core.global_position + o.LASER_RIFT_OFFSETS[6])
	assert_eq(tangent.global_rotation, (o.LASER_RIFT_OFFSETS[6] - o.LASER_RIFT_OFFSETS[5]).angle())
	assert_eq(_active_beams(o).size(), 4)

func test_rift_beams_preserve_damage_mask_dedupe_turn_rate_and_snapshot() -> void:
	var f := _fixture(); var o: RegenteEncounterOrchestrator = f.o
	_start_rift(o); _to_rift_firing(o)
	for beam in o._laser_beams:
		assert_eq(beam.damage_amount, o.LASER_DAMAGE_HEALTH_UNITS); assert_eq(beam.collision_mask, 6)
		assert_eq(beam.hit_tick_seconds, o.LASER_HIT_TICK_SECONDS); assert_eq(beam.turn_rate_radians, o.LASER_TURN_RATE_RADIANS)
	assert_eq(o.laser_runtime_snapshot().rift_phase, o.RiftPhase.ZIPPER)

func test_rift_final_rotates_inertia_then_recovers_to_electric_and_cleans_up() -> void:
	var f := _fixture(); var o: RegenteEncounterOrchestrator = f.o
	_start_rift(o); _to_rift_firing(o)
	for step in 5: o._advance_laser_cycle(o.LASER_RIFT_ZIPPER_STEP_SECONDS + o.LASER_RIFT_ZIPPER_HOLD_SECONDS)
	assert_eq(o._rift_phase, o.RiftPhase.FLUSH)
	o._advance_laser_cycle(o.LASER_RIFT_FLUSH_SECONDS)
	var beam := o._laser_beams[3]; var rotation := beam.global_rotation
	o._physics_process(0.05)
	assert_eq(beam.global_rotation, rotation)
	o._advance_laser_cycle(o.LASER_RIFT_FINAL_SECONDS)
	assert_eq(o._laser_cycle, o.LaserCycle.RECOVERY); assert_eq(o._laser_beams.size(), 0)
	o._advance_laser_cycle(o.LASER_RECOVERY_SECONDS)
	assert_eq(o._laser_cycle, o.LaserCycle.INACTIVE); assert_true(o._combat_loop_active)
	o.stop(); await get_tree().process_frame
	for child in o.get_children(): assert_false(child is LASER)

func test_rift_selection_does_not_regress_shield_bow_wings_electric_or_explosive_contracts() -> void:
	var f := _fixture(); var o: RegenteEncounterOrchestrator = f.o
	o.start(0)
	var expected := [o.LaserPattern.SHIELD, o.LaserPattern.BOW, o.LaserPattern.WINGS, o.LaserPattern.RIFT]
	for pattern in expected:
		_advance_until_laser_starts(o)
		assert_eq(o._laser_pattern, pattern)
		_advance_laser_to_electric(o)
	assert_true(o._combat_loop_active)
	assert_eq(o._next_laser_pattern, o.LaserPattern.SHIELD)
	assert_eq(o.EXPLOSIVE_COLLISION_MASK, 6); assert_eq(o.ELECTRIC_ATTACK_PULSE_SECONDS, 0.5)
