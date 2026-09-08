extends Node
## Entrada solo, preferencias e prompts. A interface nao substitui este bloqueio:
## marcar um evento como tratado nao impede consultas ao estado global de Input.

signal prompts_changed
signal safety_pause_requested(reason: String)
signal settings_error(message: String)

const BINDINGS := preload("res://scripts/input/control_bindings.gd")
const SETTINGS_PATH := "user://controls.cfg"
const NO_DEVICE := 2147483000
const MOUSE_INTENT_DISTANCE := 2.0
const UI_ACTIONS: Array[StringName] = [&"ui_up", &"ui_down", &"ui_left", &"ui_right", &"ui_accept", &"ui_cancel", &"ui_focus_next", &"ui_focus_prev", &"reward_confirm"]

var active_device := -1
var prompt_family := BINDINGS.KEYBOARD
var prompt_style := "auto"
var move_deadzone := 0.2
var aim_deadzone := 0.2
var application_focused := true
var last_error := ""
var _defaults: Dictionary = {}
var _bindings: Dictionary = {}
var _ui_defaults: Dictionary = {}
var _modals: Dictionary = {}
var _rewards: Dictionary = {}
var _suppressed: Dictionary = {}
var _pad_axes: Dictionary = {}
var _pad_buttons: Dictionary = {}
var _axis_rearm: Dictionary = {}
var _button_rearm: Dictionary = {}
var _navigation_times: Dictionary = {}
var _keys_down: Dictionary = {}
var _mouse_down: Dictionary = {}
var _key_rearm: Dictionary = {}
var _mouse_rearm: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_capture_defaults()
	_bindings = _defaults.duplicate(true)
	var connected := Input.get_connected_joypads()
	if not connected.is_empty():
		active_device = connected[0]
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	load_settings()
	_apply_bindings()

func _capture_defaults() -> void:
	for action in BINDINGS.ACTIONS:
		var entries: Array = []
		for event in InputMap.action_get_events(action):
			var binding: Dictionary = BINDINGS.from_event(event)
			if BINDINGS.valid(binding):
				entries.append(binding)
		_defaults[action] = entries
	for action in UI_ACTIONS:
		_ui_defaults[action] = InputMap.action_get_events(action).duplicate(true)
	# Confirmar e voltar precisam funcionar mesmo sem defaults de controle do motor.
	for action in [&"ui_accept", &"ui_cancel"]:
		var button: int = JOY_BUTTON_A if action == &"ui_accept" else JOY_BUTTON_B
		var has_button := false
		for event in _ui_defaults[action]:
			if event is InputEventJoypadButton and event.button_index == button:
				has_button = true
		if not has_button:
			_ui_defaults[action].append(BINDINGS.to_event(BINDINGS.button(button)))

func _apply_bindings() -> void:
	var device := active_device if active_device >= 0 else NO_DEVICE
	for action in BINDINGS.ACTIONS:
		InputMap.action_erase_events(action)
		for binding in _bindings[action]:
			var event: InputEvent = BINDINGS.to_event(binding, device)
			if not _event_waits_for_release(event):
				InputMap.action_add_event(action, event)
		if str(action).begins_with("move_"):
			InputMap.action_set_deadzone(action, move_deadzone)
		elif str(action).begins_with("aim_"):
			InputMap.action_set_deadzone(action, aim_deadzone)
	for action in UI_ACTIONS:
		InputMap.action_erase_events(action)
		for original in _ui_defaults[action]:
			var event: InputEvent = original.duplicate()
			if event is InputEventJoypadButton or event is InputEventJoypadMotion:
				event.device = device
			if not _event_waits_for_release(event):
				InputMap.action_add_event(action, event)
	prompts_changed.emit()

func _process(_delta: float) -> void:
	_prune_owners(_modals)
	_prune_owners(_rewards)
	for action in _suppressed.keys():
		if not Input.is_action_pressed(action):
			_suppressed.erase(action)

func _prune_owners(owners: Dictionary) -> void:
	for id in owners.keys():
		if owners[id].get_ref() == null:
			owners.erase(id)

func _input(event: InputEvent) -> void:
	if not observe_event(event):
		get_viewport().set_input_as_handled()
		return
	# Protege tambem Buttons nativos contra a tecla usada para abrir/fechar telas.
	for action in UI_ACTIONS:
		if _suppressed.has(action) and event.is_action_pressed(action):
			get_viewport().set_input_as_handled()
			return

## Chamado tambem por telas que consomem eventos antes do autoload.
func observe_event(event: InputEvent) -> bool:
	if not application_focused:
		return false
	var joy := event is InputEventJoypadButton or event is InputEventJoypadMotion
	if joy:
		if active_device < 0:
			if not _meaningful_pad_event(event):
				return false
			claim_device(event.device)
		if event.device != active_device:
			return false
		if event is InputEventJoypadMotion:
			_pad_axes[event.axis] = event.axis_value
			if _axis_rearm.has(event.axis):
				if absf(event.axis_value) <= minf(move_deadzone, aim_deadzone):
					_axis_rearm.erase(event.axis)
					_apply_bindings()
				else:
					return false
		else:
			_pad_buttons[event.button_index] = event.pressed
			if _button_rearm.has(event.button_index):
				if not event.pressed:
					_button_rearm.erase(event.button_index)
					_apply_bindings()
				else:
					return false
		if _meaningful_pad_event(event):
			_set_prompt_family(BINDINGS.CONTROLLER)
	elif event is InputEventMouseMotion:
		if meaningful_mouse_motion(event):
			_set_prompt_family(BINDINGS.KEYBOARD)
	elif event is InputEventKey:
		var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		_keys_down[code] = event.pressed
		if _key_rearm.has(code):
			if event.pressed:
				return false
			_key_rearm.erase(code)
			_apply_bindings()
		if event.pressed and not event.echo:
			_set_prompt_family(BINDINGS.KEYBOARD)
	elif event is InputEventMouseButton:
		_mouse_down[event.button_index] = event.pressed
		if _mouse_rearm.has(event.button_index):
			if event.pressed:
				return false
			_mouse_rearm.erase(event.button_index)
			_apply_bindings()
		if event.pressed:
			_set_prompt_family(BINDINGS.KEYBOARD)
	return true

func _meaningful_pad_event(event: InputEvent) -> bool:
	if event is InputEventJoypadButton:
		return event.pressed
	if event is InputEventJoypadMotion:
		return absf(event.axis_value) > maxf(0.25, maxf(move_deadzone, aim_deadzone))
	return false

func meaningful_mouse_motion(event: InputEventMouseMotion) -> bool:
	return event.relative.is_finite() and event.relative.length() >= MOUSE_INTENT_DISTANCE

func _set_prompt_family(value: int) -> void:
	if prompt_family == value:
		return
	prompt_family = value
	prompts_changed.emit()

func claim_device(device: int) -> void:
	if device < 0 or device == active_device:
		return
	suppress_held()
	active_device = device
	_pad_axes.clear()
	_pad_buttons.clear()
	_axis_rearm.clear()
	_button_rearm.clear()
	# Um controle conectado com gatilho/botao segurado precisa voltar ao neutro.
	if Input.get_connected_joypads().has(device):
		for axis in range(JOY_AXIS_MAX):
			var value := Input.get_joy_axis(device, axis)
			_pad_axes[axis] = value
			if absf(value) > minf(move_deadzone, aim_deadzone):
				_axis_rearm[axis] = true
		for button in range(JOY_BUTTON_MAX):
			if Input.is_joy_button_pressed(device, button):
				_pad_buttons[button] = true
				_button_rearm[button] = true
	_apply_bindings()

func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		if active_device < 0:
			claim_device(device)
		return
	if device != active_device:
		return
	suppress_held()
	active_device = -1
	_pad_axes.clear()
	_pad_buttons.clear()
	_axis_rearm.clear()
	_button_rearm.clear()
	for action in BINDINGS.ACTIONS + UI_ACTIONS:
		Input.action_release(action)
	_apply_bindings()
	_set_prompt_family(BINDINGS.KEYBOARD)
	safety_pause_requested.emit("Controle desconectado. Reconecte ou use o teclado.")

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		set_application_focus(false)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		set_application_focus(true)

func set_application_focus(focused: bool) -> void:
	if application_focused == focused:
		return
	application_focused = focused
	suppress_held()
	if not focused:
		rearm_held_inputs()
		safety_pause_requested.emit("Jogo pausado ao perder o foco.")

func set_modal(owner: Object, enabled: bool) -> void:
	_set_context(_modals, owner, enabled)

func set_reward_context(owner: Object, enabled: bool) -> void:
	_set_context(_rewards, owner, enabled, false)

func _set_context(owners: Dictionary, owner: Object, enabled: bool, block_gameplay: bool = true) -> void:
	if not is_instance_valid(owner):
		return
	var id := owner.get_instance_id()
	if owners.has(id) == enabled:
		return
	if enabled:
		owners[id] = weakref(owner)
	else:
		owners.erase(id)
	if block_gameplay:
		suppress_held()
		if not enabled:
			rearm_held_inputs()
	else:
		# A oferta nao interrompe propulsao, tiro ou mira que ja estejam ativos.
		suppress_held([&"interact", &"reward_confirm", &"ui_accept", &"ui_cancel"])

func suppress_held(actions: Array = []) -> void:
	var targets: Array = BINDINGS.ACTIONS + UI_ACTIONS if actions.is_empty() else actions
	for action in targets:
		if Input.is_action_pressed(action):
			_suppressed[action] = true

func block_gameplay_event(event: InputEvent) -> void:
	for action in BINDINGS.ACTIONS:
		if event.is_action(action):
			_suppressed[action] = true

func consume_ui_event(event: InputEvent) -> void:
	block_gameplay_event(event)
	get_viewport().set_input_as_handled()

func ui_pressed(event: InputEvent, action: StringName) -> bool:
	return observe_event(event) and not _suppressed.has(action) and event.is_action_pressed(action) and not event.is_echo()

func navigation_pressed(event: InputEvent, action: StringName) -> bool:
	if not ui_pressed(event, action):
		return false
	if event is InputEventJoypadMotion:
		var now := Time.get_ticks_msec()
		if now - int(_navigation_times.get(action, -1000)) < 180:
			return false
		_navigation_times[action] = now
	return true

func gameplay_allowed(action: StringName = &"") -> bool:
	_prune_owners(_modals)
	_prune_owners(_rewards)
	if not application_focused or not _modals.is_empty() or get_tree().paused or _suppressed.has(action):
		return false
	return action != &"interact" or _rewards.is_empty()

func pressed(action: StringName) -> bool:
	return gameplay_allowed(action) and Input.is_action_pressed(action)

func just_pressed(action: StringName) -> bool:
	return gameplay_allowed(action) and Input.is_action_just_pressed(action)

func _event_waits_for_release(event: InputEvent) -> bool:
	if event is InputEventJoypadMotion:
		return _axis_rearm.has(event.axis)
	if event is InputEventJoypadButton:
		return _button_rearm.has(event.button_index)
	if event is InputEventKey:
		var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		return _key_rearm.has(code)
	if event is InputEventMouseButton:
		return _mouse_rearm.has(event.button_index)
	return false

## Retira somente os eventos fisicos ainda segurados. Outros dispositivos e
## bindings da mesma acao continuam disponiveis para recuperar o controle.
func rearm_held_inputs() -> void:
	for axis in _pad_axes:
		if absf(_pad_axes[axis]) > minf(move_deadzone, aim_deadzone):
			_axis_rearm[axis] = true
	for button in _pad_buttons:
		if _pad_buttons[button]:
			_button_rearm[button] = true
	for key in _keys_down:
		if _keys_down[key]:
			_key_rearm[key] = true
	for button in _mouse_down:
		if _mouse_down[button]:
			_mouse_rearm[button] = true
	for action in BINDINGS.ACTIONS + UI_ACTIONS:
		Input.action_release(action)
	if not _bindings.is_empty():
		_apply_bindings()

func interaction_pressed(event: InputEvent) -> bool:
	return observe_event(event) and gameplay_allowed(&"interact") and event.is_action_pressed(&"interact") and not event.is_echo()

func movement_vector() -> Vector2:
	return _vector(&"move_left", &"move_right", &"move_up", &"move_down", move_deadzone)

func aim_vector() -> Vector2:
	return _vector(&"aim_left", &"aim_right", &"aim_up", &"aim_down", aim_deadzone)

func _vector(left: StringName, right: StringName, up: StringName, down: StringName, deadzone: float) -> Vector2:
	if not gameplay_allowed():
		return Vector2.ZERO
	var raw := Vector2(_strength(right) - _strength(left), _strength(down) - _strength(up))
	return BINDINGS.radial(raw, deadzone)

func _strength(action: StringName) -> float:
	if _suppressed.has(action):
		return 0.0
	return Input.get_action_raw_strength(action)

func controller_move_vector() -> Vector2:
	if active_device < 0 or not gameplay_allowed():
		return Vector2.ZERO
	var raw := Vector2(_pad_strength(&"move_right") - _pad_strength(&"move_left"), _pad_strength(&"move_down") - _pad_strength(&"move_up"))
	return BINDINGS.radial(raw, move_deadzone)

func _pad_strength(action: StringName) -> float:
	if _suppressed.has(action):
		return 0.0
	var strength := 0.0
	for binding in _bindings.get(action, []):
		if binding.kind == "axis" and not _axis_rearm.has(binding.code):
			var value: float = _pad_axes.get(binding.code, Input.get_joy_axis(active_device, binding.code))
			strength = maxf(strength, maxf(0.0, value * binding.sign))
		elif binding.kind == "button" and not _button_rearm.has(binding.code) and _pad_buttons.get(binding.code, Input.is_joy_button_pressed(active_device, binding.code)):
			strength = 1.0
	return strength

func selected_style() -> String:
	if prompt_style != "auto":
		return prompt_style
	var name := Input.get_joy_name(active_device).to_lower() if active_device >= 0 else ""
	if "xbox" in name or "xinput" in name:
		return "xbox"
	if "playstation" in name or "dualshock" in name or "dualsense" in name or "ps4" in name or "ps5" in name:
		return "playstation"
	if "nintendo" in name or "switch" in name or "joy-con" in name:
		return "nintendo"
	return "generic"

func prompt(action: StringName, family: int = -1, compact: bool = false) -> String:
	var target_family := prompt_family if family < 0 else family
	var entries: Array = bindings_for(action, target_family)
	if entries.is_empty():
		return "Mouse" if str(action).begins_with("aim_") and target_family == BINDINGS.KEYBOARD else "—"
	return BINDINGS.label(entries[0], selected_style(), compact)

func bindings_for(action: StringName, family: int) -> Array:
	var entries: Array = _bindings.get(action, [])
	if _ui_defaults.has(action):
		entries = []
		for event in _ui_defaults[action]:
			var binding: Dictionary = BINDINGS.from_event(event)
			if BINDINGS.valid(binding):
				entries.append(binding)
	var result: Array = []
	for binding in entries:
		if BINDINGS.family(binding) == family:
			result.append(binding.duplicate())
	return result

## Documento portavel: somente dados primitivos, sem caminho ou dispositivo local.
func settings_snapshot() -> Dictionary:
	return {"version": BINDINGS.VERSION, "bindings": _bindings.duplicate(true), "move_deadzone": move_deadzone, "aim_deadzone": aim_deadzone, "prompt_style": prompt_style}

func validate_snapshot(document: Dictionary) -> String:
	if document.size() != 5 or not document.get("version") is int or document.version != BINDINGS.VERSION:
		return "Versão ou formato de controles inválido."
	if not BINDINGS.valid_deadzone(document.get("move_deadzone")) or not BINDINGS.valid_deadzone(document.get("aim_deadzone")):
		return "Zona morta inválida."
	if not document.get("prompt_style") is String or document.prompt_style not in BINDINGS.STYLES:
		return "Estilo de controle inválido."
	var candidate: Variant = document.get("bindings")
	if not candidate is Dictionary or candidate.size() != BINDINGS.ACTIONS.size():
		return "Lista de ações inválida."
	for action in BINDINGS.ACTIONS:
		var entries: Variant = candidate.get(action)
		if not entries is Array or entries.is_empty() or entries.size() > 8:
			return "Ação sem entrada válida: %s." % action
		var seen: Dictionary = {}
		for binding in entries:
			if not BINDINGS.valid(binding):
				return "Entrada inválida em %s." % action
			var token: String = BINDINGS.identity(binding)
			if seen.has(token):
				return "Entrada duplicada em %s." % action
			seen[token] = true
			var conflict := binding_conflict(action, binding, candidate)
			if not conflict.is_empty():
				return conflict
	return ""

func binding_conflict(action: StringName, binding: Dictionary, candidate: Dictionary = {}) -> String:
	if action not in BINDINGS.ACTIONS or not BINDINGS.valid(binding):
		return "Entrada ou ação inválida."
	var kind: String = binding.kind
	var code: int = binding.code
	if kind == "key":
		if code == KEY_F12:
			return "F12 é reservado para restaurar os controles."
		if code == KEY_ESCAPE and action != &"pause":
			return "Esc é reservado para voltar e pausar."
		if code in [KEY_ENTER, KEY_KP_ENTER] and action != &"interact":
			return "Enter é reservado para confirmar e interagir."
		for event in InputMap.action_get_events(&"dev_sandbox_toggle"):
			if event is InputEventKey and code == event.physical_keycode:
				return "Esta tecla é reservada para o painel de desenvolvimento."
	elif kind == "button":
		if code in [JOY_BUTTON_GUIDE, JOY_BUTTON_B, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]:
			return "Este botão é reservado para navegação ou para o sistema."
		if code == JOY_BUTTON_A and action != &"interact":
			return "O botão sul é reservado para confirmar e interagir."
		if code == JOY_BUTTON_START and action != &"pause":
			return "Start é reservado para pausar."
		if code == JOY_BUTTON_BACK and action != &"map_toggle":
			return "Select é reservado para o mapa."
	var source: Dictionary = _bindings if candidate.is_empty() else candidate
	for other_action in source:
		if other_action == action:
			continue
		for other in source[other_action]:
			if BINDINGS.valid(other) and BINDINGS.identity(other) == BINDINGS.identity(binding):
				return "Já usado por %s. Escolha outra entrada ou restaure os padrões." % BINDINGS.LABELS.get(str(other_action), str(other_action))
	return ""

func rebind_action(action: StringName, family: int, binding: Dictionary) -> String:
	if family not in [BINDINGS.KEYBOARD, BINDINGS.CONTROLLER] or not BINDINGS.valid(binding) or BINDINGS.family(binding) != family:
		return "Use uma entrada do dispositivo selecionado (sem acordes ou roda do mouse)."
	var conflict := binding_conflict(action, binding)
	if not conflict.is_empty():
		return conflict
	var candidate := settings_snapshot()
	var entries: Array = []
	for existing in _bindings[action]:
		if BINDINGS.family(existing) != family:
			entries.append(existing.duplicate())
	entries.append(binding.duplicate())
	candidate.bindings[action] = entries
	var error := apply_snapshot(candidate)
	return "" if error == OK else last_error

func reset_action(action: StringName, family: int) -> String:
	if action not in BINDINGS.ACTIONS or family not in [BINDINGS.KEYBOARD, BINDINGS.CONTROLLER]:
		return "Ação inválida."
	var candidate := settings_snapshot()
	var entries: Array = []
	for existing in _bindings[action]:
		if BINDINGS.family(existing) != family:
			entries.append(existing.duplicate())
	for original in _defaults[action]:
		if BINDINGS.family(original) == family:
			entries.append(original.duplicate())
	candidate.bindings[action] = entries
	var error := apply_snapshot(candidate)
	return "" if error == OK else last_error

func reset_defaults() -> void:
	apply_snapshot({"version": BINDINGS.VERSION, "bindings": _defaults.duplicate(true), "move_deadzone": 0.2, "aim_deadzone": 0.2, "prompt_style": "auto"})

func apply_snapshot(document: Dictionary) -> Error:
	var message := validate_snapshot(document)
	if not message.is_empty():
		_report_settings_error(message)
		return ERR_INVALID_DATA
	suppress_held()
	_bindings = document.bindings.duplicate(true)
	move_deadzone = float(document.move_deadzone)
	aim_deadzone = float(document.aim_deadzone)
	prompt_style = document.prompt_style
	# Uma acao nao pode continuar pressionada por um binding que foi removido.
	rearm_held_inputs()
	last_error = ""
	return OK

func set_preferences(movement: float, aiming: float, style: String) -> String:
	var candidate := settings_snapshot()
	candidate.move_deadzone = movement
	candidate.aim_deadzone = aiming
	candidate.prompt_style = style
	return "" if apply_snapshot(candidate) == OK else last_error

func save_settings(path: String = SETTINGS_PATH) -> Error:
	var file := ConfigFile.new()
	file.set_value("controls", "data", settings_snapshot())
	# Primeiro salva um arquivo completo ao lado do destino. Se falhar, nao
	# substitui a ultima configuracao valida por um arquivo parcial.
	var temporary := path + ".tmp"
	var error := file.save(temporary)
	if error == OK:
		error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path))
	if error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		_report_settings_error("Não foi possível salvar os controles: %s." % error_string(error))
	else:
		last_error = ""
	return error

func load_settings(path: String = SETTINGS_PATH) -> Error:
	if not FileAccess.file_exists(path):
		return OK
	var file := ConfigFile.new()
	var error := file.load(path)
	if error != OK:
		_report_settings_error("Arquivo de controles ilegível; controles atuais preservados.")
		return error
	var document: Variant = file.get_value("controls", "data", null)
	if not document is Dictionary:
		_report_settings_error("Arquivo de controles inválido; controles atuais preservados.")
		return ERR_INVALID_DATA
	return apply_snapshot(document)

func _report_settings_error(message: String) -> void:
	last_error = message
	settings_error.emit(message)
