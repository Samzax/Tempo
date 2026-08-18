extends GutTest

const ORCHESTRATOR := preload("res://scripts/enemies/bosses/regente_encounter_orchestrator.gd")
const LASER := preload("res://scripts/enemies/bosses/wings/laser_beam_2d.gd")

func _fixture(host := true) -> Dictionary:
	var o = ORCHESTRATOR.new()
	var enemies := Node2D.new()
	add_child_autofree(o); add_child_autofree(enemies)
	o.set_enemy_container(enemies)
	return {"o": o, "enemies": enemies}

func _start_whip(o) -> void:
	assert_true(o.start(0))
	o._next_laser_pattern = o.LaserPattern.WHIP
	assert_true(o._begin_laser_cycle())

func _to_whip_firing(o) -> void:
	o._advance_laser_cycle(o.LASER_TRANSITION_SECONDS)
	assert_eq(o._laser_cycle, o.LaserCycle.TELEGRAPH)
	o._advance_laser_cycle(o.LASER_TELEGRAPH_SECONDS)
	assert_eq(o._laser_cycle, o.LaserCycle.FIRING)
	assert_eq(o.whip_runtime_snapshot().phase, o.WhipPhase.STROKE)

func test_whip_is_open_12_slot_chain_with_root_tip_and_no_chord() -> void:
	var f := _fixture(); var o = f.o
	assert_eq(o.LaserPattern.WHIP, 4)
	assert_eq(o.LASER_WHIP_OFFSETS.size(), 12)
	assert_eq(o.LASER_WHIP_TERMINAL_INDEX, 11)
	assert_eq(o._laser_emitter_indices_for(o.LaserPattern.WHIP).size(), 0)
	assert_eq(o.whip_runtime_snapshot().link_count, 11)
	assert_ne(o.LASER_WHIP_OFFSETS[0], o.LASER_WHIP_OFFSETS[11])
	for i in 11: assert_ne(o.LASER_WHIP_OFFSETS[i], o.LASER_WHIP_OFFSETS[i + 1])
	_start_whip(o)
	assert_eq(o._electric_slots.size(), 12)
	assert_eq(o._whip_current_offsets.size(), 12)
	assert_eq(o._whip_current_offsets[0], o.LASER_WHIP_OFFSETS[0])
	assert_ne(o._whip_current_offsets[11], o._electric_slots[11].offset)
	assert_eq(o._laser_beams.size(), 0)

func test_whip_schedule_is_rift_to_whip_to_electric_then_shield() -> void:
	var f := _fixture(); var o = f.o
	assert_eq(o._scheduled_laser_pattern_after(o.LaserPattern.RIFT), o.LaserPattern.WHIP)
	assert_eq(o._scheduled_laser_pattern_after(o.LaserPattern.WHIP), o.LaserPattern.SHIELD)
	_start_whip(o)
	o._advance_laser_cycle(o.LASER_TRANSITION_SECONDS + o.LASER_TELEGRAPH_SECONDS + o.LASER_WHIP_STROKE_SECONDS + o.LASER_WHIP_CRACK_SECONDS + o.LASER_RECOVERY_SECONDS)
	assert_eq(o._laser_cycle, o.LaserCycle.INACTIVE)
	assert_true(o._combat_loop_active)
	assert_eq(o._next_laser_pattern, o.LaserPattern.SHIELD)

func test_whip_windup_and_telegraph_are_damaging_beam_free() -> void:
	var f := _fixture(); var o = f.o
	_start_whip(o)
	o._advance_laser_cycle(0.4)
	assert_eq(o._laser_cycle, o.LaserCycle.TRANSITION)
	assert_eq(o.whip_runtime_snapshot().hit_keys, 0)
	assert_eq(o._laser_beams.size(), 0)
	o._advance_laser_cycle(0.4)
	assert_eq(o._laser_cycle, o.LaserCycle.TELEGRAPH)
	assert_eq(o.whip_runtime_snapshot().hit_keys, 0)
	assert_eq(o._laser_beams.size(), 0)

func test_whip_stroke_moves_chain_and_uses_11_physical_link_queries_not_beams() -> void:
	var f := _fixture(); var o = f.o
	_start_whip(o); _to_whip_firing(o)
	var before: Vector2 = o._whip_current_offsets[11]
	o._advance_laser_cycle(0.50)
	assert_eq(o.whip_runtime_snapshot().phase, o.WhipPhase.STROKE)
	assert_ne(o._whip_current_offsets[11], before)
	assert_eq(o.whip_runtime_snapshot().link_count, 11)
	assert_eq(o._laser_beams.size(), 0)
	assert_eq(o._laser_emitter_indices_for(o.LaserPattern.WHIP).size(), 0)

func test_whip_dedupe_key_is_link_plus_target_and_allows_distinct_links() -> void:
	var f := _fixture(); var o = f.o
	o._whip_hit_targets["0:77"] = 0.0
	o._whip_hit_targets["1:77"] = 0.0
	assert_true(o._whip_hit_targets.has("0:77"))
	assert_true(o._whip_hit_targets.has("1:77"))
	assert_eq(o._whip_hit_targets.size(), 2)
	o._laser_elapsed = 0.10
	assert_lt(o._laser_elapsed - o._whip_hit_targets["0:77"], o.LASER_HIT_TICK_SECONDS)
	o._laser_elapsed = 0.25
	assert_gte(o._laser_elapsed - o._whip_hit_targets["0:77"], o.LASER_HIT_TICK_SECONDS)

func test_whip_stroke_ends_in_exactly_one_terminal_tangent_beam_at_d12() -> void:
	var f := _fixture(); var o = f.o
	_start_whip(o); _to_whip_firing(o)
	o._advance_laser_cycle(o.LASER_WHIP_STROKE_SECONDS)
	assert_eq(o.whip_runtime_snapshot().phase, o.WhipPhase.CRACK)
	assert_eq(o._laser_beams.size(), 1)
	assert_eq(o.laser_runtime_snapshot().active_emitter_indices, [11])
	var beam: LaserBeam2D = o._laser_beams[0]
	assert_eq(beam.fixed_origin, o._core.global_position + o.LASER_WHIP_OFFSETS[11])
	assert_eq(beam.global_rotation, (o.LASER_WHIP_OFFSETS[11] - o.LASER_WHIP_OFFSETS[10]).angle())
	assert_eq(beam.collision_mask, 6)
	assert_eq(beam.damage_amount, o.LASER_DAMAGE_HEALTH_UNITS)

func test_whip_recovery_cleanup_authority_mask_and_regressions() -> void:
	var f := _fixture(); var o = f.o
	_start_whip(o); _to_whip_firing(o)
	o._advance_laser_cycle(o.LASER_WHIP_STROKE_SECONDS + o.LASER_WHIP_CRACK_SECONDS)
	assert_eq(o._laser_cycle, o.LaserCycle.RECOVERY)
	o._advance_laser_cycle(o.LASER_RECOVERY_SECONDS)
	assert_eq(o._laser_cycle, o.LaserCycle.INACTIVE)
	assert_eq(o._laser_beams.size(), 0)
	assert_eq(o.whip_runtime_snapshot().hit_keys, 0)
	assert_true(o._combat_loop_active)
	assert_eq(o.LASER_COLLISION_MASK, 6)
	assert_eq(o.EXPLOSIVE_COLLISION_MASK, 6)
	assert_eq(o.ELECTRIC_ATTACK_PULSE_SECONDS, 0.5)
	assert_true(o._has_host_authority())
	assert_eq(o._scheduled_laser_pattern_after(o.LaserPattern.WHIP), o.LaserPattern.SHIELD)
	o.stop(); await get_tree().process_frame
	for child in o.get_children(): assert_false(child is LASER)
