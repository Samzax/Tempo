class_name N0N1V27Player
extends CanvasLayer

## Milestones select approved transparent planet renders; visual_time moves
## that planet and the V27 star field independently.
const FRAME_COUNT := 989
## The active, requested and catch-up look-ahead set is the complete native
## residency contract.  Keep this explicit so callers and tests share it.
const MAX_NATIVE_FRAME_CACHE := 4
const PAGE_ROOT := "res://assets/backgrounds/continuous_n0_n1_v1/"
const SPACE_SHADER := preload("res://scripts/backgrounds/n0_n1_v27_stable_space.gdshader")
const PLANET_SHADER := preload("res://scripts/backgrounds/n0_n1_v27_array.gdshader")
const SPACE_FIELD := preload("res://assets/backgrounds/continuous_n0_n1_v1/n0_n1_v27_space_field.png")
const FIRST_PLANET := preload("res://assets/backgrounds/continuous_n0_n1_v1/planet-0000.png")
const FPS := 30.0
const STAR_NATIVE_PIXELS_PER_SECOND := 1.25
const PLANET_NATIVE_PIXELS_PER_SECOND := 3.5
const STAR_LOOP_NATIVE_PIXELS := 1288.0

var current_frame := 0
var visual_time := 0.0
var _planet_frames: Dictionary = {}
var _requested: Dictionary = {}
var _space: ColorRect
var _planet: ColorRect
var _space_material: ShaderMaterial
var _planet_material: ShaderMaterial
var _stable := false
var _stall_count := 0
var _stall_started_usec := 0
var _stall_duration_usec := 0
var _last_visual_tick_frame := -1
var _desired_frame := 0
var _planet_offset_native_px := 0.0
var _planet_phase_origin_seconds := 0.0
var _planet_phase_origin_offset_native_px := 0.0
var _continuation_drift := false
var _advance_accumulator := 0.0
var _applied_star_offset_native_px := 0.0
var _applied_planet_offset_native_px := 0.0
var _legacy_visibility: Dictionary = {}

static func ensure_for_viewport(viewport: Viewport) -> N0N1V27Player:
	var existing := viewport.get_node_or_null("N0N1V27Player") as N0N1V27Player
	if existing != null:
		return existing
	var node := N0N1V27Player.new()
	node.name = &"N0N1V27Player"
	viewport.add_child(node)
	return node

func _ready() -> void:
	layer = -5
	_space = ColorRect.new()
	_space.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_space_material = ShaderMaterial.new()
	_space_material.shader = SPACE_SHADER
	_space_material.set_shader_parameter("space_field", SPACE_FIELD)
	_space.material = _space_material
	add_child(_space)
	_planet = ColorRect.new()
	_planet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_planet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_planet_material = ShaderMaterial.new()
	_planet_material.shader = PLANET_SHADER
	_planet_material.set_shader_parameter("planet_frame", FIRST_PLANET)
	_planet.material = _planet_material
	add_child(_planet)
	_planet_frames[0] = FIRST_PLANET
	_request_frame(1)
	_request_frame(2)
	_apply_layer_transforms()

## The player belongs to the viewport rather than an individual room, so it
## survives a completed run.  Only Session's fresh-N0 entry invokes this; the
## N0 -> N1 handoff deliberately keeps its clock, pose and pending work.
func reset_for_new_run() -> void:
	_hide_legacy_phase_background()
	current_frame = 0
	visual_time = 0.0
	_desired_frame = 0
	_planet_offset_native_px = 0.0
	_planet_phase_origin_seconds = 0.0
	_planet_phase_origin_offset_native_px = 0.0
	_continuation_drift = false
	_advance_accumulator = 0.0
	_stable = false
	_stall_count = 0
	_stall_started_usec = 0
	_stall_duration_usec = 0
	_last_visual_tick_frame = -1
	_planet_frames.clear()
	_planet_frames[0] = FIRST_PLANET
	if _planet_material != null:
		_planet_material.set_shader_parameter("planet_frame", FIRST_PLANET)
	_apply_layer_transforms()
	set_process(true)
	show()

## A viewport-owned layer otherwise keeps processing after its room is gone.
## Keep polling outstanding threaded loads while hidden. Godot owns those
## requests; forgetting them can turn a subsequent CACHE_MODE_IGNORE request
## into ERR_BUSY forever.
func suspend_for_inactive_profile() -> void:
	hide()
	_restore_legacy_phase_background()
	set_process(true)

func _process(delta: float) -> void:
	_collect_requested()
	if not visible:
		return
	# Own the handoff/loading gap as well. Room presentations also call this
	# method, but the frame guard keeps exactly one unpaused visual tick.
	tick_parallax(delta)

func tick_parallax(delta: float) -> void:
	if get_tree().paused:
		return
	var process_frame := Engine.get_process_frames()
	if process_frame == _last_visual_tick_frame:
		return
	_last_visual_tick_frame = process_frame
	var elapsed := maxf(0.0, delta)
	visual_time += elapsed
	_planet_offset_native_px += PLANET_NATIVE_PIXELS_PER_SECOND * elapsed
	_apply_layer_transforms()

func show_progress(progress: float) -> void:
	show_frame(clampi(int(floor(progress / 92.9 * 718.0)), 0, 718))

func advance_toward(target: int, delta: float, speed: float) -> bool:
	_advance_accumulator += maxf(0.0, delta)
	var committed := false
	while _advance_accumulator >= 1.0 / FPS and current_frame < target:
		_advance_accumulator -= 1.0 / FPS
		# `speed` is the source-path catch-up step, while this loop remains
		# sampled at the approved 30 Hz regardless of render callback rate.
		var step := maxi(1, roundi(speed))
		if not show_frame(mini(target, current_frame + step)):
			_advance_accumulator += 1.0 / FPS
			break
		committed = true
	return committed or current_frame >= target

func show_frame(frame: int) -> bool:
	_hide_legacy_phase_background()
	var clamped := clampi(frame, 0, FRAME_COUNT - 1)
	_desired_frame = clamped
	_request_frame(clamped)
	_request_frame(mini(FRAME_COUNT - 1, clamped + 1))
	_collect_requested()
	if not _planet_frames.has(clamped):
		if _stall_started_usec == 0:
			_stall_started_usec = Time.get_ticks_usec()
			_stall_count += 1
		return false
	if _stall_started_usec != 0:
		_stall_duration_usec += Time.get_ticks_usec() - _stall_started_usec
		_stall_started_usec = 0
	current_frame = clamped
	_planet_material.set_shader_parameter("planet_frame", _planet_frames[clamped])
	_prune_frame_cache()
	return true

func enter_stable_continuation() -> void:
	# Frame 988 is a milestone, not a terminal image.
	if show_frame(988):
		_stable = true

func begin_handoff_approach() -> void:
	# Compatibility hook for the N0 presentation. The global planet phase must
	# never recenter or reverse between combat clear and N1.
	pass

func begin_continuation_drift() -> void:
	if _continuation_drift:
		return
	# Preserve the N0 handoff pose and global clock; drift remains forward.
	_continuation_drift = true
	_planet_phase_origin_seconds = visual_time
	_planet_phase_origin_offset_native_px = _planet_offset_native_px

func diagnostics() -> Dictionary:
	return {"frame": current_frame, "visual_clock_seconds": visual_time, "star_native_pixels_per_second": STAR_NATIVE_PIXELS_PER_SECOND, "planet_native_pixels_per_second": PLANET_NATIVE_PIXELS_PER_SECOND, "layer_transforms": {"star_offset_native_px": _applied_star_offset_native_px, "planet_offset_native_px": _applied_planet_offset_native_px}, "stable_continuation": _stable, "resident_frames": _planet_frames.keys(), "requested_frames": _requested.keys(), "frame_stall_count": _stall_count, "frame_stall_usec": _stall_duration_usec + (Time.get_ticks_usec() - _stall_started_usec if _stall_started_usec != 0 else 0)}

func _apply_layer_transforms() -> void:
	_applied_star_offset_native_px = fposmod(visual_time * STAR_NATIVE_PIXELS_PER_SECOND, STAR_LOOP_NATIVE_PIXELS)
	_applied_planet_offset_native_px = _planet_offset_native_px
	_space_material.set_shader_parameter("source_offset_native_px", _applied_star_offset_native_px)
	_planet_material.set_shader_parameter("planet_offset_native_px", _applied_planet_offset_native_px)

func _frame_path(frame: int) -> String:
	return "%splanet-%04d.png" % [PAGE_ROOT, frame]

func _request_frame(frame: int) -> void:
	if _planet_frames.has(frame) or _requested.has(frame):
		return
	var path := _frame_path(frame)
	var request_result := ResourceLoader.load_threaded_request(path, "Texture2D", ResourceLoader.CACHE_MODE_IGNORE)
	# ERR_BUSY means this exact resource already has a live engine request.
	# Record and drain it instead of losing the only route to its completion.
	if request_result == OK or request_result == ERR_BUSY:
		_requested[frame] = path

func _collect_requested() -> void:
	for frame in _requested.keys().duplicate():
		var path: String = _requested[frame]
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var resource := ResourceLoader.load_threaded_get(path)
			if resource is Texture2D:
				_planet_frames[frame] = resource
			_requested.erase(frame)
		elif status == ResourceLoader.THREAD_LOAD_FAILED:
			_requested.erase(frame)
	# Failed or reset-era requests remain recoverable: keep the active target
	# and catch-up look-ahead scheduled until a later request succeeds.
	_request_frame(_desired_frame)
	_request_frame(mini(FRAME_COUNT - 1, _desired_frame + 1))
	_request_frame(mini(FRAME_COUNT - 1, _desired_frame + 2))
	# Retain current + desired + prefetch while a jump is awaiting commit.
	# Pruning never discards an uncommitted target.
	_prune_frame_cache()

func _prune_frame_cache() -> void:
	var protected := [current_frame, _desired_frame, mini(FRAME_COUNT - 1, _desired_frame + 1), mini(FRAME_COUNT - 1, _desired_frame + 2)]
	for frame in _planet_frames.keys().duplicate():
		if not protected.has(frame):
			_planet_frames.erase(frame)
	# The protected set is at most current, desired and two look-ahead frames.
	assert(_planet_frames.size() <= MAX_NATIVE_FRAME_CACHE)

func _hide_legacy_phase_background() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var legacy := scene.get_node_or_null("PhaseBackground") as CanvasItem
	if legacy != null:
		if not _legacy_visibility.has(legacy):
			_legacy_visibility[legacy] = legacy.visible
		legacy.hide()
	for extension in scene.find_children("UpperSpaceExtension", "CanvasItem", true, false):
		var item := extension as CanvasItem
		if not _legacy_visibility.has(item):
			_legacy_visibility[item] = item.visible
		item.hide()

func _restore_legacy_phase_background() -> void:
	for item in _legacy_visibility.keys():
		if is_instance_valid(item):
			(item as CanvasItem).visible = bool(_legacy_visibility[item])
	_legacy_visibility.clear()
