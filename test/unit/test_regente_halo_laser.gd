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

func _start_halo(o: RegenteEncounterOrchestrator) -> void:
	assert_true(o.start(0))
	o._next_laser_pattern = o.LaserPattern.HALO
	assert_true(o._begin_laser_cycle())

func _to_halo_telegraph(o: RegenteEncounterOrchestrator) -> void:
	o._advance_laser_cycle(o.LASER_TRANSITION_SECONDS)
	assert_eq(o._laser_cycle, o.LaserCycle.TELEGRAPH)

func _to_halo_firing(o: RegenteEncounterOrchestrator) -> void:
	if o._laser_cycle != o.LaserCycle.TELEGRAPH:
		_to_halo_telegraph(o)
	o._advance_laser_cycle(o.LASER_HALO_TELEGRAPH_SECONDS)
	assert_eq(o._laser_cycle, o.LaserCycle.FIRING)

func test_halo_is_six_diameter_rotor_with_twelve_opposite_orbital_offsets() -> void:
	var f := _fixture(); var o: RegenteEncounterOrchestrator = f.o
	assert_eq(o.LaserPattern.HALO, 5)
	assert_eq(o.LASER_HALO_OFFSETS.size(), 12)
	assert_eq(o.LASER_HALO_DIAMETER_COUNT, 6)
	assert_eq(o._laser_emitter_indices_for(o.LaserPattern.HALO), [0, 1, 2, 3, 4, 5])
	for i in 6:
		assert_almost_eq(o.LASER_HALO_OFFSETS[i].length(), o.LASER_HALO_RADIUS_PX, 0.01)
		assert_almost_eq((o.LASER_HALO_OFFSETS[i + 6] + o.LASER_HALO_OFFSETS[i]).length(), 0.0, 0.01)
	_start_halo(o)
	assert_eq(o._laser_beams.size(), 6)
	assert_eq(o._electric_slots.size(), 12)
	assert_eq(o.halo_runtime_snapshot().beam_count, 6)

func test_halo_telegraph_and_firing_are_simultaneous_with_six_beams_and_twelve_co_emitters() -> void:
	var f := _fixture(); var o: RegenteEncounterOrchestrator = f.o
	_start_halo(o); _to_halo_telegraph(o)
	assert_eq(o._laser_beams.size(), 6)
	for beam in o._laser_beams: assert_eq(beam.state, LASER.State.TELEGRAPH)
	assert_eq(o._electric_slots.size(), 12)
	_to_halo_firing(o)
	assert_eq(o._laser_beams.size(), 6)
	for beam in o._laser_beams: assert_eq(beam.state, LASER.State.FIRING)
	assert_eq(o.halo_runtime_snapshot().endpoints.size(), 6)

func test_halo_uses_one_phi_omega_alpha_for_all_endpoints_without_banks_snap_or_inversion() -> void:
	var f := _fixture(); var o: RegenteEncounterOrchestrator = f.o
	o.LASER_HALO_PHI_RADIANS = 0.25; o.LASER_HALO_OMEGA_RADIANS = 1.5; o.LASER_HALO_ALPHA_RADIANS = 0.4
	_start_halo(o); _to_halo_firing(o)
	var before := o.halo_runtime_snapshot()
	o._advance_laser_cycle(0.2)
	var after := o.halo_runtime_snapshot()
	assert_almost_eq(after.phi, before.phi + before.omega * 0.2 + 0.5 * before.alpha * 0.2 * 0.2, 0.001)
	assert_almost_eq(after.omega, before.omega + before.alpha * 0.2, 0.001)
	for i in 6:
		var origin: Vector2 = after.endpoints[i].origin
		var endpoint: Vector2 = after.endpoints[i].endpoint
		assert_almost_eq(origin.distance_to(o._core.global_position), endpoint.distance_to(o._core.global_position), 0.01)
		assert_eq(o._laser_beams[i].tracking_target, null)
	assert_false(o.has_method("_laser_halo_bank_a")); assert_false(o.has_method("_laser_halo_bank_b")); assert_false(o.has_method("_laser_halo_bank_c"))

func test_halo_damage_is_cumulative_per_beam_locally_deduped_and_uses_mask6_authority() -> void:
	var f := _fixture(); var o: RegenteEncounterOrchestrator = f.o
	_start_halo(o)
	for beam in o._laser_beams:
		assert_eq(beam.damage_amount, o.LASER_DAMAGE_HEALTH_UNITS)
		assert_eq(beam.collision_mask, 6)
		assert_eq(beam.hit_tick_seconds, o.LASER_HIT_TICK_SECONDS)
		assert_eq(beam.damage_tags, [&"laser", &"halo"])
		assert_eq(beam.runtime_snapshot().hit_targets, 0)
	var remote := _fixture(false); var remote_o: RegenteEncounterOrchestrator = remote.o
	assert_true(remote_o.start(0)); remote_o._next_laser_pattern = remote_o.LaserPattern.HALO
	assert_false(remote_o._begin_laser_cycle()); assert_eq(remote_o._laser_beams.size(), 0)

func test_halo_schedule_is_whip_to_halo_to_shield_and_recovery_releases_slots() -> void:
	var f := _fixture(); var o: RegenteEncounterOrchestrator = f.o
	assert_eq(o._scheduled_laser_pattern_after(o.LaserPattern.WHIP), o.LaserPattern.HALO)
	assert_eq(o._scheduled_laser_pattern_after(o.LaserPattern.HALO), o.LaserPattern.SHIELD)
	_start_halo(o)
	o._advance_laser_cycle(o.LASER_TRANSITION_SECONDS + o.LASER_HALO_TELEGRAPH_SECONDS + o.LASER_HALO_FIRE_SECONDS + o.LASER_RECOVERY_SECONDS)
	assert_eq(o._laser_cycle, o.LaserCycle.INACTIVE)
	assert_eq(o._next_laser_pattern, o.LaserPattern.SHIELD)
	assert_true(o._combat_loop_active)
	assert_eq(o._laser_beams.size(), 0)
	assert_eq(o.halo_runtime_snapshot().endpoints.size(), 0)

func test_halo_preserves_shield_bow_wings_rift_whip_electric_and_explosive_regressions() -> void:
	var f := _fixture(); var o: RegenteEncounterOrchestrator = f.o
	assert_eq(o._scheduled_laser_pattern_after(o.LaserPattern.SHIELD), o.LaserPattern.BOW)
	assert_eq(o._scheduled_laser_pattern_after(o.LaserPattern.BOW), o.LaserPattern.WINGS)
	assert_eq(o._scheduled_laser_pattern_after(o.LaserPattern.WINGS), o.LaserPattern.RIFT)
	assert_eq(o._scheduled_laser_pattern_after(o.LaserPattern.RIFT), o.LaserPattern.WHIP)
	assert_eq(o.EXPLOSIVE_COLLISION_MASK, 6)
	assert_eq(o.ELECTRIC_ATTACK_PULSE_SECONDS, 0.5)
	assert_eq(o.LASER_COLLISION_MASK, 6)
	assert_eq(o.LASER_HALO_FIRE_SECONDS, 1.5)
