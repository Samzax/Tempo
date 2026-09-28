class_name ControlBindings
extends RefCounted
## Formato primitivo e validado: nunca serializa objetos nem IDs de dispositivos.

const VERSION := 1
const KEYBOARD := 0
const CONTROLLER := 1
const ACTIONS: Array[StringName] = [
	&"move_up", &"move_down", &"move_left", &"move_right",
	&"aim_up", &"aim_down", &"aim_left", &"aim_right",
	&"shoot", &"ability_q", &"ability_e", &"blink", &"interact",
	&"pause", &"map_toggle", &"loot_choice_1", &"loot_choice_2", &"loot_choice_3",
]
const LABELS := {
	"move_up": "Mover / propulsão: cima", "move_down": "Mover: baixo",
	"move_left": "Mover: esquerda", "move_right": "Mover: direita",
	"aim_up": "Mira: cima", "aim_down": "Mira: baixo",
	"aim_left": "Mira: esquerda", "aim_right": "Mira: direita",
	"shoot": "Atirar", "ability_q": "Habilidade da nave",
	"ability_e": "Habilidade do personagem", "blink": "Mobilidade / Shift",
	"interact": "Interagir", "pause": "Pausar", "map_toggle": "Mapa",
	"loot_choice_1": "Melhoria 1", "loot_choice_2": "Melhoria 2", "loot_choice_3": "Melhoria 3",
}
const STYLES := ["auto", "generic", "xbox", "playstation", "nintendo"]
const MIN_DEADZONE := 0.05
const MAX_DEADZONE := 0.6

static func key(code: int) -> Dictionary:
	return {"kind": "key", "code": code}

static func button(code: int) -> Dictionary:
	return {"kind": "button", "code": code}

static func axis(code: int, direction: int) -> Dictionary:
	return {"kind": "axis", "code": code, "sign": direction}

static func family(binding: Dictionary) -> int:
	return CONTROLLER if binding.get("kind", "") in ["button", "axis"] else KEYBOARD

static func valid(binding: Variant) -> bool:
	if not binding is Dictionary or not binding.get("kind") is String:
		return false
	var code: Variant = binding.get("code")
	if not code is int:
		return false
	match binding.kind:
		"key":
			return binding.size() == 2 and code > 0 and code < (1 << 23)
		"mouse":
			return binding.size() == 2 and code in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2]
		"button":
			return binding.size() == 2 and code >= 0 and code < JOY_BUTTON_MAX
		"axis":
			var direction: Variant = binding.get("sign")
			if binding.size() != 3 or not direction is int or direction not in [-1, 1] or code < 0 or code >= JOY_AXIS_MAX:
				return false
			return direction == 1 or code not in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]
	return false

static func from_event(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if event.echo or (event.alt_pressed and code != KEY_ALT) or (event.ctrl_pressed and code != KEY_CTRL) or (event.meta_pressed and code != KEY_META) or (event.shift_pressed and code != KEY_SHIFT):
			return {}
		return key(code)
	if event is InputEventMouseButton:
		return {"kind": "mouse", "code": event.button_index}
	if event is InputEventJoypadButton:
		return button(event.button_index)
	if event is InputEventJoypadMotion and absf(event.axis_value) >= 0.65:
		return axis(event.axis, 1 if event.axis_value > 0.0 else -1)
	return {}

static func to_event(binding: Dictionary, device: int = -1) -> InputEvent:
	if not valid(binding):
		return null
	match binding.kind:
		"key":
			var event := InputEventKey.new()
			event.physical_keycode = binding.code
			return event
		"mouse":
			var event := InputEventMouseButton.new()
			event.button_index = binding.code
			return event
		"button":
			var event := InputEventJoypadButton.new()
			event.device = device
			event.button_index = binding.code
			return event
		"axis":
			var event := InputEventJoypadMotion.new()
			event.device = device
			event.axis = binding.code
			event.axis_value = float(binding.sign)
			return event
	return null

static func identity(binding: Dictionary) -> String:
	return "%s:%d:%d" % [binding.get("kind", ""), binding.get("code", -1), binding.get("sign", 0)]

static func radial(raw: Vector2, deadzone: float) -> Vector2:
	if not raw.is_finite() or not is_finite(deadzone):
		return Vector2.ZERO
	var length := raw.length()
	var threshold := clampf(deadzone, MIN_DEADZONE, MAX_DEADZONE)
	if length <= threshold + 0.000001:
		return Vector2.ZERO
	return raw / length * minf(1.0, (length - threshold) / (1.0 - threshold))

static func valid_deadzone(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and value >= MIN_DEADZONE and value <= MAX_DEADZONE

static func label(binding: Dictionary, style: String = "generic", compact: bool = false) -> String:
	if not valid(binding):
		return "—"
	var code: int = binding.code
	match binding.kind:
		"key":
			# Converte posicao fisica para a legenda do layout atual do teclado.
			var logical := DisplayServer.keyboard_get_keycode_from_physical(code)
			return OS.get_keycode_string(logical if logical != 0 else code)
		"mouse":
			var names := {1: "Mouse 1", 2: "Mouse 2", 3: "Mouse 3", 8: "Mouse 4", 9: "Mouse 5"}
			return names.get(code, "Mouse %d" % code)
		"axis":
			if code == JOY_AXIS_TRIGGER_LEFT:
				return "L2" if style == "playstation" else ("ZL" if style == "nintendo" else "LT")
			if code == JOY_AXIS_TRIGGER_RIGHT:
				return "R2" if style == "playstation" else ("ZR" if style == "nintendo" else "RT")
			var axis_names := {0: "LE", 1: "LE", 2: "LD", 3: "LD"}
			var direction := ("←" if binding.sign < 0 else "→") if code % 2 == 0 else ("↑" if binding.sign < 0 else "↓")
			return "%s %s" % [axis_names.get(code, "Eixo %d" % code), direction]
		"button":
			var faces := ["Sul", "Leste", "Oeste", "Norte"]
			if style == "xbox":
				faces = ["A", "B", "X", "Y"]
			elif style == "playstation":
				faces = ["Cruz", "Círculo", "Quadrado", "Triângulo"]
			elif style == "nintendo":
				faces = ["B", "A", "Y", "X"]
			if code >= 0 and code < faces.size():
				if compact and style == "playstation":
					return ["Cruz", "Círc.", "Quad.", "Tri."][code]
				return faces[code]
			if code == JOY_BUTTON_LEFT_SHOULDER:
				return "L1" if style == "playstation" else ("L" if style == "nintendo" else "LB")
			if code == JOY_BUTTON_RIGHT_SHOULDER:
				return "R1" if style == "playstation" else ("R" if style == "nintendo" else "RB")
			var names := {JOY_BUTTON_BACK: "Select", JOY_BUTTON_START: "Start", JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3", JOY_BUTTON_DPAD_UP: "D ↑", JOY_BUTTON_DPAD_DOWN: "D ↓", JOY_BUTTON_DPAD_LEFT: "D ←", JOY_BUTTON_DPAD_RIGHT: "D →"}
			return names.get(code, "B%d" % (code + 1))
	return "—"
