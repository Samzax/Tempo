extends GutTest

## Testes unitarios das configuracoes de video (VideoSettings).

const TEST_CONFIG_PATH := "user://test_video_settings_temp.cfg"

class StubVideoSettings extends "res://scripts/autoload/video_settings.gd":
	var stub_screen_size := Vector2i(1920, 1080)
	var stub_usable_rect := Rect2i(0, 0, 1920, 1080)

	func screen_size() -> Vector2i:
		return stub_screen_size

	func usable_rect() -> Rect2i:
		return stub_usable_rect

var _before_snapshot: Dictionary = {}

func before_each() -> void:
	_before_snapshot = VideoSettings.settings_snapshot()
	_remove_temp_config()

func after_each() -> void:
	VideoSettings.apply_snapshot(_before_snapshot)
	_remove_temp_config()

func _remove_temp_config() -> void:
	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CONFIG_PATH))

func test_resolution_candidates_contains_standard_resolutions_and_native_sorted_without_duplicates() -> void:
	var stub := StubVideoSettings.new()
	stub.stub_screen_size = Vector2i(1920, 1080)
	stub.stub_usable_rect = Rect2i(0, 0, 1920, 1080)

	var candidates := stub.resolution_candidates()
	assert_true(candidates.has(Vector2i(1280, 720)))
	assert_true(candidates.has(Vector2i(1600, 900)))
	assert_true(candidates.has(stub.native_resolution()))

	for i in range(candidates.size() - 1):
		var area_a := candidates[i].x * candidates[i].y
		var area_b := candidates[i + 1].x * candidates[i + 1].y
		assert_true(area_a <= area_b)

	var unique_set: Array[Vector2i] = []
	for res in candidates:
		assert_false(unique_set.has(res))
		unique_set.append(res)

	stub.free()

func test_resolution_candidates_never_empty_even_with_degenerated_usable_area() -> void:
	var stub := StubVideoSettings.new()
	stub.stub_screen_size = Vector2i(1920, 1080)
	stub.stub_usable_rect = Rect2i(0, 0, 100, 100)

	var candidates := stub.resolution_candidates()
	assert_gt(candidates.size(), 0)

	stub.stub_usable_rect = Rect2i(0, 0, 0, 0)
	var candidates_zero := stub.resolution_candidates()
	assert_gt(candidates_zero.size(), 0)

	stub.free()

func test_default_fullscreen_rule_based_on_aspect_ratio() -> void:
	var stub_wide := StubVideoSettings.new()
	stub_wide.stub_screen_size = Vector2i(2560, 1080)
	assert_true(stub_wide.default_fullscreen())
	stub_wide.free()

	var stub_169 := StubVideoSettings.new()
	stub_169.stub_screen_size = Vector2i(1920, 1080)
	assert_false(stub_169.default_fullscreen())
	stub_169.free()

func test_default_window_resolution_chooses_largest_fitting_169() -> void:
	var stub := StubVideoSettings.new()
	stub.stub_screen_size = Vector2i(1920, 1080)
	stub.stub_usable_rect = Rect2i(0, 0, 1700, 950)

	var def_res := stub.default_resolution()
	assert_eq(def_res, Vector2i(1600, 900))
	assert_true(def_res.x <= 1700)
	assert_true(def_res.y <= 950)

	stub.free()

func test_persistence_round_trip_saves_and_loads_snapshot() -> void:
	var target_res := Vector2i(1600, 900)
	VideoSettings.apply_settings(target_res, true)
	var err_save := VideoSettings.save_settings(TEST_CONFIG_PATH)
	assert_eq(err_save, OK)
	assert_true(FileAccess.file_exists(TEST_CONFIG_PATH))

	VideoSettings.resolution = Vector2i(1280, 720)
	VideoSettings.fullscreen = false
	VideoSettings.saved = false

	var err_load := VideoSettings.load_settings(TEST_CONFIG_PATH)
	assert_eq(err_load, OK)
	var loaded_snapshot := VideoSettings.settings_snapshot()
	assert_eq(loaded_snapshot.width, 1600)
	assert_eq(loaded_snapshot.height, 900)
	assert_eq(loaded_snapshot.fullscreen, true)
	assert_eq(loaded_snapshot.saved, true)

func test_apply_snapshot_with_invalid_data_returns_error_and_preserves_state() -> void:
	VideoSettings.apply_settings(Vector2i(1280, 720), false)
	var before := VideoSettings.settings_snapshot()
	watch_signals(VideoSettings)

	var invalid_doc := {
		"version": 99,
		"saved": true,
		"fullscreen": true,
		"width": 1920,
		"height": 1080
	}

	var result := VideoSettings.apply_snapshot(invalid_doc)
	assert_eq(result, ERR_INVALID_DATA)
	assert_signal_emitted(VideoSettings, &"settings_error")
	assert_eq(VideoSettings.settings_snapshot(), before)

func test_reset_to_default_restores_derived_values_and_marks_unsaved() -> void:
	VideoSettings.apply_settings(Vector2i(1600, 900), true)
	VideoSettings.reset_to_default()

	assert_false(VideoSettings.saved)
	assert_eq(VideoSettings.fullscreen, VideoSettings.default_fullscreen())
	assert_eq(VideoSettings.resolution, VideoSettings.default_resolution())

func test_apply_settings_emits_settings_changed_once() -> void:
	watch_signals(VideoSettings)
	var target_res := Vector2i(1280, 720)
	VideoSettings.apply_settings(target_res, false)

	assert_signal_emit_count(VideoSettings, &"settings_changed", 1)
	assert_signal_emitted_with_parameters(VideoSettings, &"settings_changed", [target_res, false])

func test_apply_display_windowed_sets_window_size_and_position() -> void:
	var target_res := Vector2i(1280, 720)
	VideoSettings.apply_settings(target_res, false)

	assert_eq(VideoSettings.resolution, target_res)
	assert_false(VideoSettings.fullscreen)
