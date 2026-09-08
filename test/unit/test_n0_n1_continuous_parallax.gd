extends GutTest

const PLAYER_SCRIPT := preload("res://scripts/backgrounds/n0_n1_v27_player.gd")

class CadenceSpy extends N0N1V27Player:
	var committed_source_frames: Array[int] = []

	func show_frame(frame: int) -> bool:
		var clamped := clampi(frame, 0, FRAME_COUNT - 1)
		current_frame = clamped
		committed_source_frames.append(clamped)
		return true

func _wait_for_frame(player: N0N1V27Player, frame: int, max_frames := 120) -> void:
	for _index: int in range(max_frames):
		if player.show_frame(frame) or player.current_frame == frame:
			return
		await get_tree().process_frame
	assert_eq(player.current_frame, frame, "frame %d must be loaded before it is observed" % frame)

func _image_hash(image: Image) -> int:
	# Hash a sparse sample, keeping failure output small while still proving
	# that the rendered target changed.
	var hash_value := 0
	for y: int in range(0, image.get_height(), 16):
		for x: int in range(0, image.get_width(), 16):
			hash_value = hash_value * 31 + image.get_pixel(x, y).to_rgba32()
	return hash_value

func _image_nonblank(image: Image) -> bool:
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.01:
				return true
	return false

func _player() -> N0N1V27Player:
	var player: N0N1V27Player = PLAYER_SCRIPT.new()
	add_child_autofree(player)
	await get_tree().process_frame
	return player

func _reset_visual_tick_guard(player: N0N1V27Player) -> void:
	# Each direct call below represents a distinct simulated visual tick. The
	# runtime guard intentionally permits only one tick per real engine frame.
	player._last_visual_tick_frame = -1

func test_unchanged_combat_milestone_advances_clock_and_independent_layer_offsets() -> void:
	var player: N0N1V27Player = await _player()
	var before: Dictionary = player.diagnostics()
	player.tick_parallax(1.0)
	var after: Dictionary = player.diagnostics()
	assert_gt(float(after.visual_clock_seconds), float(before.visual_clock_seconds))
	assert_gt(float(after.layer_transforms.star_offset_native_px), float(before.layer_transforms.star_offset_native_px))
	assert_gt(float(after.layer_transforms.planet_offset_native_px), float(before.layer_transforms.planet_offset_native_px))
	assert_ne(float(after.layer_transforms.star_offset_native_px), float(after.layer_transforms.planet_offset_native_px))

func test_multiple_ticks_in_one_engine_frame_advance_once() -> void:
	var player: N0N1V27Player = await _player()
	_reset_visual_tick_guard(player)
	player.tick_parallax(1.0 / 30.0)
	var once: float = player.visual_time
	player.tick_parallax(1.0 / 30.0)
	assert_eq(player.visual_time, once)

func test_pause_freezes_and_resume_preserves_phase() -> void:
	var player: N0N1V27Player = await _player()
	_reset_visual_tick_guard(player)
	player.tick_parallax(1.0)
	var phase: float = player.visual_time
	get_tree().paused = true
	_reset_visual_tick_guard(player)
	player.tick_parallax(1.0)
	assert_eq(player.visual_time, phase)
	get_tree().paused = false
	_reset_visual_tick_guard(player)
	player.tick_parallax(1.0 / 30.0)
	assert_gt(player.visual_time, phase)

func test_async_milestone_load_commits_and_retains_bounded_native_cache() -> void:
	var player: N0N1V27Player = await _player()
	await _wait_for_frame(player, 3)
	var clock: float = player.visual_time
	await _wait_for_frame(player, 20)
	assert_gte(player.visual_time, clock)
	assert_eq(PLAYER_SCRIPT.MAX_NATIVE_FRAME_CACHE, 4)
	var state: Dictionary = player.diagnostics()
	assert_lte(state.resident_frames.size(), PLAYER_SCRIPT.MAX_NATIVE_FRAME_CACHE)
	assert_true(state.resident_frames.has(20))

func test_n1_frame_988_continues_clock_and_motion() -> void:
	var player: N0N1V27Player = await _player()
	await _wait_for_frame(player, 988)
	_reset_visual_tick_guard(player)
	player.tick_parallax(1.0)
	var first: float = player.visual_time
	_reset_visual_tick_guard(player)
	player.tick_parallax(1.0)
	assert_gt(player.visual_time, first)

func test_handoff_and_continuation_never_reverse_planet_offset() -> void:
	var player: N0N1V27Player = await _player()
	_reset_visual_tick_guard(player)
	player.tick_parallax(1.0)
	var before: float = player.diagnostics().layer_transforms.planet_offset_native_px
	player.begin_handoff_approach()
	_reset_visual_tick_guard(player)
	player.tick_parallax(1.0 / 30.0)
	var handoff: float = player.diagnostics().layer_transforms.planet_offset_native_px
	player.begin_continuation_drift()
	_reset_visual_tick_guard(player)
	player.tick_parallax(1.0 / 30.0)
	var continuation: float = player.diagnostics().layer_transforms.planet_offset_native_px
	assert_gt(handoff, before)
	assert_gt(continuation, handoff)

func test_advance_toward_samples_at_30hz_at_30_and_60_render_callbacks() -> void:
	var at_30 := CadenceSpy.new()
	var at_60 := CadenceSpy.new()
	add_child_autofree(at_30)
	add_child_autofree(at_60)
	await get_tree().process_frame
	assert_eq(at_30.committed_source_frames.size(), 0)
	at_60.advance_toward(60, 1.0 / 60.0, 2.0)
	assert_eq(at_60.committed_source_frames.size(), 0)
	at_60.advance_toward(60, 1.0 / 60.0, 2.0)
	assert_eq(at_60.committed_source_frames.size(), 1)
	for _tick: int in range(30):
		at_30.advance_toward(60, 1.0 / 30.0, 2.0)
	for _tick: int in range(60):
		at_60.advance_toward(60, 1.0 / 60.0, 2.0)
	assert_eq(at_30.current_frame, at_60.current_frame)
	assert_eq(at_30.current_frame, 60)
	assert_eq(at_30.committed_source_frames.size(), at_60.committed_source_frames.size())

func test_new_n0_run_reset_contract_restores_the_fresh_n0_state() -> void:
	var player: N0N1V27Player = await _player()
	player.visual_time = 12.0
	player.current_frame = 20
	player.begin_continuation_drift()
	assert_true(player.has_method("reset_for_new_run"))
	if not player.has_method("reset_for_new_run"):
		return
	player.reset_for_new_run()
	assert_eq(player.visual_time, 0.0)
	assert_eq(player.current_frame, 0)
	var state: Dictionary = player.diagnostics()
	assert_eq(state.frame, 0)
	assert_eq(state.visual_clock_seconds, 0.0)
	assert_eq(state.layer_transforms.planet_offset_native_px, 0.0)
	assert_false(state.stable_continuation)
	assert_lte(state.resident_frames.size(), PLAYER_SCRIPT.MAX_NATIVE_FRAME_CACHE)

func test_planet_subviewport_pixels_change_at_visual_time_60_and_61() -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(640, 360)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.transparent_bg = true
	add_child_autofree(viewport)
	var player: N0N1V27Player = PLAYER_SCRIPT.new()
	viewport.add_child(player)
	# Render only the planet layer. The probe owns the clock and actual planet
	# offset, so autonomous processing must not advance it between captures.
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player._space.hide()
	await get_tree().process_frame
	await _wait_for_frame(player, 0)
	_reset_visual_tick_guard(player)
	player.tick_parallax(60.0)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var first: Image = viewport.get_texture().get_image()
	_reset_visual_tick_guard(player)
	player.tick_parallax(1.0)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var second: Image = viewport.get_texture().get_image()
	assert_true(_image_nonblank(first), "rendered planet must be nonblank at t=60")
	assert_true(_image_nonblank(second), "rendered planet must be nonblank at t=61")
	assert_ne(_image_hash(first), _image_hash(second), "rendered planet must change at t=60 vs t=61")
