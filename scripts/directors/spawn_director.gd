extends Node

const ENEMY := preload("res://scenes/enemies/enemy.tscn")
const HUNTER := preload("res://scenes/enemies/hunter.tscn")
const ATIRADOR := preload("res://scenes/enemies/atirador_de_fresta.tscn")
const KAMIKAZE := preload("res://scenes/enemies/kamikaze_fraturado.tscn")
const ENTRY_WARNING_DURATION := 0.45
const WAVE_BREATHER_DURATION := 3.0
const PAIR_MEMBER_DELAY := 0.35
const HUNTER_PAIR_MEMBER_DELAY := 0.25
const HUNTER_MIN_PAIR_DISTANCE := 240.0
const EDGE_MARGIN := 24.0
const OUTSIDE_OFFSET := 16.0

signal enemy_spawned(enemy: Enemy)
signal spawns_finished
signal spawns_failed(reason: String)
signal wave_started(wave_index: int)
signal spawn_warning_started(wave_index: int, spawn_index: int)

enum State { IDLE, RUNNING, FINISHED }
enum EntryEdge { TOP, BOTTOM, LEFT, RIGHT }

@export var interval := 1.1
@export_range(1, 100, 1) var hunter_spawn_every := 5

var _t := 0.0
var _container: Node
var _spawn_index := 0
var _regular_spawn_index := 0
var _spawn_limit := 0
var _spawns_emitted := 0
var _finished_emitted := false
var _state: State = State.IDLE
var _room_bounds := Rect2(Vector2.ZERO, Vector2(720, 405))

# A agenda e imutavel depois de montada; cada item representa uma emissao,
# enquanto _events representa o inicio que define a cadencia aprovada.
var _agenda: Array[Dictionary] = []
var _events: Array[Dictionary] = []
var _event_cursor := 0
var _pending_warnings: Array[Dictionary] = []
var _pending_emissions: Array[Dictionary] = []
var _active_enemies: Dictionary = {}
var _reserved_slots := 0
var _using_waves := false
var _current_wave := -1
var _next_warning_at := 0.0
var _waiting_for_wave_clear := false
var _breather_remaining := -1.0

func _ready() -> void:
	_container = get_tree().get_first_node_in_group("enemies_container")
	set_physics_process(false)

## Compatibilidade para salas e testes legados.
func start(spawn_limit: int) -> bool:
	if _state != State.IDLE:
		push_warning("SpawnDirector.start() ignored after its first invocation.")
		return false
	_using_waves = false
	_spawn_limit = spawn_limit
	if spawn_limit > 0 and not _prepare_container():
		return false
	_state = State.RUNNING
	_reset_runtime()
	if _spawn_limit <= 0:
		_finish_spawns()
		return true
	set_physics_process(true)
	return true

func start_waves(waves: Array[RoomDef.WaveSpec]) -> bool:
	if _state != State.IDLE:
		push_warning("SpawnDirector.start_waves() ignored after its first invocation.")
		return false
	_using_waves = true
	if not _prepare_container():
		return false
	_agenda = build_spawn_agenda(waves)
	_events = _build_wave_events(_agenda)
	_state = State.RUNNING
	_reset_runtime()
	if _events.is_empty():
		_finish_spawns()
		return true
	set_physics_process(true)
	return true

func stop() -> void:
	set_physics_process(false)

func set_room_bounds(bounds: Rect2) -> void:
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		push_error("SpawnDirector requires positive room bounds.")
		return
	_room_bounds = bounds

## Superficie de observacao para o test-author: permite testar execucao,
## pausas por max_active e ordem dos sinais sem inspecionar temporizadores.
func get_wave_execution_state() -> Dictionary:
	return {
		"agenda": _agenda.duplicate(true),
		"event_cursor": _event_cursor,
		"pending_warnings": _pending_warnings.duplicate(true),
		"pending_emissions": _pending_emissions.duplicate(true),
		"active_count": _active_enemies.size(),
		"reserved_slots": _reserved_slots,
		"wave_index": _current_wave,
		"waiting_for_wave_clear": _waiting_for_wave_clear,
		"breather_remaining": _breather_remaining,
		"spawns_emitted": _spawns_emitted,
		"finished": _finished_emitted,
	}

func get_spawn_agenda() -> Array[Dictionary]:
	return _agenda.duplicate(true)

func build_spawn_agenda(waves: Array[RoomDef.WaveSpec]) -> Array[Dictionary]:
	return _build_wave_agenda(waves)

func _reset_runtime() -> void:
	_spawns_emitted = 0
	_spawn_index = 0
	_regular_spawn_index = 0
	_finished_emitted = false
	_t = 0.0
	_event_cursor = 0
	_pending_warnings.clear()
	_pending_emissions.clear()
	_active_enemies.clear()
	_reserved_slots = 0
	_current_wave = -1
	_next_warning_at = 0.0
	_waiting_for_wave_clear = false
	_breather_remaining = -1.0

func _physics_process(delta: float) -> void:
	if _using_waves:
		_process_wave_agenda(delta)
		return
	_process_legacy(delta)

func _process_legacy(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	var enemy := _spawn_legacy()
	if enemy != null:
		_spawns_emitted += 1
		enemy_spawned.emit(enemy)
		if _spawns_emitted >= _spawn_limit:
			_finish_spawns()
			return
	_t = interval

func _process_wave_agenda(delta: float) -> void:
	_t += delta
	_emit_due_warnings()
	_emit_due_members()
	if _state != State.RUNNING:
		return
	if _waiting_for_wave_clear:
		_process_wave_clearance(delta)
		return
	if _event_cursor >= _events.size():
		_waiting_for_wave_clear = true
		_process_wave_clearance(delta)
		return
	var event := _events[_event_cursor]
	if _current_wave != -1 and int(event.wave_index) != _current_wave:
		_waiting_for_wave_clear = true
		_process_wave_clearance(delta)
		return
	if _t < _next_warning_at:
		return
	var members: Array = event.members
	if _active_enemies.size() + _reserved_slots + members.size() > int(event.max_active):
		return
	_begin_event(event)

func _begin_event(event: Dictionary) -> void:
	var wave_index: int = event.wave_index
	if _current_wave != wave_index:
		_current_wave = wave_index
		wave_started.emit(wave_index)
	_reserved_slots += (event.members as Array).size()
	for member in event.members:
		var warning: Dictionary = member.duplicate(true)
		warning.warning_at = _t + float(member.member_delay)
		_pending_warnings.append(warning)
	_emit_due_warnings()
	# A cadencia e medida entre os inicios dos eventos. Para W3, o
	# primeiro Hunter abre o segundo aviso 0,25 s depois, sem somar o
	# atraso ao aviso de entrada de 0,45 s.
	_next_warning_at = _t + float(event.next_event_delay)
	_event_cursor += 1

func _emit_due_warnings() -> void:
	var emitted_any := true
	while emitted_any:
		emitted_any = false
		for pending_index in _pending_warnings.size():
			var warning := _pending_warnings[pending_index]
			if _t + 0.0001 < float(warning.warning_at):
				continue
			_pending_warnings.remove_at(pending_index)
			spawn_warning_started.emit(int(warning.wave_index), int(warning.spawn_index))
			warning.emit_at = float(warning.warning_at) + ENTRY_WARNING_DURATION
			_pending_emissions.append(warning)
			emitted_any = true
			break

func _emit_due_members() -> void:
	var emitted_any := true
	while emitted_any:
		emitted_any = false
		for pending_index in _pending_emissions.size():
			var entry := _pending_emissions[pending_index]
			if _t + 0.0001 < float(entry.emit_at):
				continue
			_pending_emissions.remove_at(pending_index)
			_reserved_slots -= 1
			var enemy := _spawn_agenda_entry(entry)
			if enemy != null:
				_spawns_emitted += 1
				enemy_spawned.emit(enemy)
			emitted_any = true
			break

func _process_wave_clearance(delta: float) -> void:
	if not _pending_warnings.is_empty() or not _pending_emissions.is_empty() or not _active_enemies.is_empty() or _reserved_slots > 0:
		return
	if _event_cursor >= _events.size():
		_finish_spawns()
		return
	if _breather_remaining < 0.0:
		_breather_remaining = WAVE_BREATHER_DURATION
	_breather_remaining -= delta
	if _breather_remaining > 0.0:
		return
	_breather_remaining = -1.0
	_waiting_for_wave_clear = false
	_current_wave = -1
	_next_warning_at = _t

func _build_wave_agenda(waves: Array[RoomDef.WaveSpec]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for wave_index in waves.size():
		var wave := waves[wave_index]
		if wave == null:
			continue
		var spawn_index := 0
		var event_index := 0
		if not wave.threat_types.is_empty():
			for threat_type in wave.threat_types:
				var edge := _random_edge()
				result.append(_entry(wave_index, event_index, spawn_index, false, edge, _point_for_edge(edge), wave.max_active, wave.cadence, 0.0, wave.cadence, threat_type))
				spawn_index += 1
				event_index += 1
		elif wave.paired_commons:
			for _pair_index in wave.common_count / 2:
				var edge := _random_edge()
				var point := _point_for_edge(edge)
				result.append(_entry(wave_index, event_index, spawn_index, false, edge, point, wave.max_active, wave.cadence, 0.0))
				spawn_index += 1
				result.append(_entry(wave_index, event_index, spawn_index, false, _opposite_edge(edge), _mirror_point(point), wave.max_active, wave.cadence, PAIR_MEMBER_DELAY))
				spawn_index += 1
				event_index += 1
		elif wave_index == 2 and wave.hunter_count == 2 and wave.common_count == 0:
			var first := _hunter_placement(Vector2.ZERO)
			var second := _hunter_placement(first.point)
			# W3 possui dois eventos independentes: cada Hunter recebe seu
			# proprio aviso e spawn, com o segundo aviso iniciado em t + 0,25.
			result.append(_entry(wave_index, event_index, spawn_index, true, first.edge, first.point, wave.max_active, wave.cadence, 0.0, HUNTER_PAIR_MEMBER_DELAY))
			spawn_index += 1
			event_index += 1
			result.append(_entry(wave_index, event_index, spawn_index, true, second.edge, second.point, wave.max_active, wave.cadence, 0.0, wave.cadence))
		else:
			_append_mixed_entries(result, wave, wave_index, spawn_index, event_index)
	return result

func _build_wave_events(agenda: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in agenda:
		var same_event := not result.is_empty() and int(result.back().wave_index) == int(entry.wave_index) and int(result.back().event_index) == int(entry.event_index)
		if not same_event:
			result.append({"wave_index": entry.wave_index, "event_index": entry.event_index, "spawn_index": entry.spawn_index, "max_active": entry.max_active, "cadence": entry.cadence, "next_event_delay": entry.next_event_delay, "members": []})
		result.back().members.append(entry)
	return result

func _entry(wave_index: int, event_index: int, spawn_index: int, hunter: bool, edge: int, point: Vector2, max_active: int, cadence: float, member_delay: float, next_event_delay: float = -1.0, threat_type: StringName = &"") -> Dictionary:
	if next_event_delay < 0.0:
		next_event_delay = cadence
	return {"wave_index": wave_index, "event_index": event_index, "wave_spawn_index": spawn_index, "spawn_index": spawn_index, "hunter": hunter, "threat_type": threat_type, "edge": edge, "point": point, "max_active": max_active, "cadence": cadence, "member_delay": member_delay, "next_event_delay": next_event_delay}

func _append_mixed_entries(result: Array[Dictionary], wave: RoomDef.WaveSpec, wave_index: int, first_spawn_index: int, first_event_index: int) -> void:
	var common_index := 0
	var hunter_index := 0
	var spawn_index := first_spawn_index
	var event_index := first_event_index
	var hunter_pair_origin := Vector2.ZERO
	while common_index < wave.common_count or hunter_index < wave.hunter_count:
		var total_emitted := common_index + hunter_index
		var should_spawn_hunter := hunter_index < wave.hunter_count and (common_index >= wave.common_count or total_emitted * wave.hunter_count / (wave.common_count + wave.hunter_count) > hunter_index)
		if should_spawn_hunter:
			var placement := _hunter_placement(hunter_pair_origin if hunter_index % 2 == 1 else Vector2.ZERO)
			if hunter_index % 2 == 0:
				hunter_pair_origin = placement.point
			result.append(_entry(wave_index, event_index, spawn_index, true, placement.edge, placement.point, wave.max_active, wave.cadence, 0.0))
			hunter_index += 1
		else:
			var edge := _random_edge()
			result.append(_entry(wave_index, event_index, spawn_index, false, edge, _point_for_edge(edge), wave.max_active, wave.cadence, 0.0))
			common_index += 1
		spawn_index += 1
		event_index += 1

func _spawn_agenda_entry(entry: Dictionary) -> Enemy:
	return _spawn_configured(bool(entry.hunter), int(entry.edge), entry.point, StringName(entry.get("threat_type", &"")))

func _spawn_legacy() -> Enemy:
	var is_hunter := hunter_spawn_every > 0 and (_spawn_index + 1) % hunter_spawn_every == 0
	return _spawn_configured(is_hunter, EntryEdge.TOP, Vector2(RunManager.rng.randf_range(_room_bounds.position.x + EDGE_MARGIN, _room_bounds.end.x - EDGE_MARGIN), _room_bounds.position.y - OUTSIDE_OFFSET))

func _spawn_configured(is_hunter: bool, edge: int, point: Vector2, threat_type: StringName = &"") -> Enemy:
	if not is_instance_valid(_container) or _container.is_queued_for_deletion():
		_fail_spawns("SpawnDirector lost its enemies_container.")
		return null
	var scene: PackedScene = HUNTER if is_hunter else ENEMY
	if threat_type == &"atirador":
		scene = ATIRADOR
	elif threat_type == &"kamikaze":
		scene = KAMIKAZE
	var enemy := scene.instantiate() as Enemy
	if enemy == null:
		return null
	# "common" e o tipo explicito da mesma familia regular. Ambos devem
	# passar pela rotacao deterministica de configuracoes.
	if not is_hunter and (threat_type == &"" or threat_type == &"common"):
		_configure_regular_enemy(enemy)
		_regular_spawn_index += 1
	_spawn_index += 1
	enemy.set_room_bounds(_room_bounds)
	enemy.set_entry_inward(_inward_for_edge(edge))
	enemy.global_position = point
	_container.add_child(enemy)
	_track_enemy(enemy)
	return enemy

func _track_enemy(enemy: Enemy) -> void:
	var instance_id := enemy.get_instance_id()
	_active_enemies[instance_id] = true
	enemy.resolved.connect(_on_enemy_resolved)
	enemy.tree_exited.connect(_on_enemy_tree_exited.bind(instance_id), CONNECT_ONE_SHOT)

func _on_enemy_resolved(enemy: Enemy, _reason: int) -> void:
	_active_enemies.erase(enemy.get_instance_id())

func _on_enemy_tree_exited(instance_id: int) -> void:
	_active_enemies.erase(instance_id)

func _configure_regular_enemy(enemy: Enemy) -> void:
	match _regular_spawn_index % 3:
		0:
			enemy.movement = Enemy.Movement.CHASE
			enemy.speed = 55.0
			enemy.max_health = 3
			enemy.tint = Color.WHITE
		1:
			enemy.movement = Enemy.Movement.DESCEND
			enemy.speed = 110.0
			enemy.max_health = 2
			enemy.tint = Color(1.0, 0.7, 0.4)
		2:
			enemy.movement = Enemy.Movement.SINE
			enemy.speed = 80.0
			enemy.max_health = 3
			enemy.tint = Color(0.75, 0.5, 1.0)

func _random_edge() -> int:
	return RunManager.rng.randi_range(EntryEdge.TOP, EntryEdge.RIGHT)

func _point_for_edge(edge: int) -> Vector2:
	match edge:
		EntryEdge.TOP: return Vector2(RunManager.rng.randf_range(_room_bounds.position.x + EDGE_MARGIN, _room_bounds.end.x - EDGE_MARGIN), _room_bounds.position.y - OUTSIDE_OFFSET)
		EntryEdge.BOTTOM: return Vector2(RunManager.rng.randf_range(_room_bounds.position.x + EDGE_MARGIN, _room_bounds.end.x - EDGE_MARGIN), _room_bounds.end.y + OUTSIDE_OFFSET)
		EntryEdge.LEFT: return Vector2(_room_bounds.position.x - OUTSIDE_OFFSET, RunManager.rng.randf_range(_room_bounds.position.y + EDGE_MARGIN, _room_bounds.end.y - EDGE_MARGIN))
		_: return Vector2(_room_bounds.end.x + OUTSIDE_OFFSET, RunManager.rng.randf_range(_room_bounds.position.y + EDGE_MARGIN, _room_bounds.end.y - EDGE_MARGIN))

func _hunter_placement(pair_origin: Vector2) -> Dictionary:
	for _attempt in 8:
		var edge := _random_edge()
		var point := _point_for_edge(edge)
		if pair_origin == Vector2.ZERO or point.distance_to(pair_origin) >= HUNTER_MIN_PAIR_DISTANCE:
			return {"edge": edge, "point": point}
	var fallback_edge := EntryEdge.BOTTOM if pair_origin == Vector2.ZERO else _opposite_edge(_edge_for_point(pair_origin))
	var fallback_point := _point_for_edge(fallback_edge) if pair_origin == Vector2.ZERO else _mirror_point(pair_origin)
	return {"edge": fallback_edge, "point": fallback_point}

func _edge_for_point(point: Vector2) -> int:
	if point.y < _room_bounds.position.y: return EntryEdge.TOP
	if point.y > _room_bounds.end.y: return EntryEdge.BOTTOM
	if point.x < _room_bounds.position.x: return EntryEdge.LEFT
	return EntryEdge.RIGHT

func _opposite_edge(edge: int) -> int:
	match edge:
		EntryEdge.TOP: return EntryEdge.BOTTOM
		EntryEdge.BOTTOM: return EntryEdge.TOP
		EntryEdge.LEFT: return EntryEdge.RIGHT
		_: return EntryEdge.LEFT

func _inward_for_edge(edge: int) -> Vector2:
	match edge:
		EntryEdge.TOP: return Vector2.DOWN
		EntryEdge.BOTTOM: return Vector2.UP
		EntryEdge.LEFT: return Vector2.RIGHT
		_: return Vector2.LEFT

func _mirror_point(point: Vector2) -> Vector2:
	return _room_bounds.get_center() * 2.0 - point

func _finish_spawns() -> void:
	if _finished_emitted:
		return
	_finished_emitted = true
	_state = State.FINISHED
	stop()
	spawns_finished.emit()

func _fail_spawns(reason: String) -> void:
	_state = State.FINISHED
	stop()
	push_warning(reason)
	spawns_failed.emit(reason)

func _prepare_container() -> bool:
	_container = _get_enemies_container()
	if _container == null:
		_fail_spawns("SpawnDirector requires an enemies_container.")
		return false
	if not _container.tree_exited.is_connected(_on_container_lost):
		_container.tree_exited.connect(_on_container_lost, CONNECT_ONE_SHOT)
	return true

func _on_container_lost() -> void:
	if _state == State.RUNNING and is_physics_processing():
		_fail_spawns("SpawnDirector lost its enemies_container.")

func _get_enemies_container() -> Node:
	return get_tree().get_first_node_in_group("enemies_container")
