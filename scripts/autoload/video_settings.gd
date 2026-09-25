extends Node
## Gerenciador de configuracoes de video e tamanho de janela.

signal settings_changed(resolution: Vector2i, fullscreen: bool)
signal settings_error(message: String)

const SETTINGS_PATH := "user://video.cfg"
const DOCUMENT_VERSION := 1
const LADDER: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]
const WIDESCREEN_LIMIT := 1.85
const MIN_WINDOW := Vector2i(640, 360)

var last_error := ""
var fullscreen := false
var resolution := Vector2i(1280, 720)
var saved := false

func _ready() -> void:
	load_settings()
	apply_display(resolution, fullscreen)

## Retorna true se o processo estiver executando a suíte de testes automatizada (GUT).
## Execuções automatizadas não devem alterar nem assumir o controle da exibição da tela.
func is_automated_run() -> bool:
	for arg in OS.get_cmdline_args():
		if "addons/gut" in arg:
			return true
	return false

func screen_size() -> Vector2i:
	var sz := DisplayServer.screen_get_size()
	if sz.x <= 0 or sz.y <= 0:
		var override_w := int(ProjectSettings.get_setting("display/window/size/window_width_override", 1440))
		var override_h := int(ProjectSettings.get_setting("display/window/size/window_height_override", 810))
		return Vector2i(override_w, override_h)
	return sz

func usable_rect() -> Rect2i:
	var rect := DisplayServer.screen_get_usable_rect()
	if rect.size.x <= 0 or rect.size.y <= 0:
		return Rect2i(Vector2i.ZERO, screen_size())
	return rect

func screen_aspect() -> float:
	return screen_size().x / float(maxi(1, screen_size().y))

func native_resolution() -> Vector2i:
	return screen_size()

func default_fullscreen() -> bool:
	return screen_aspect() > WIDESCREEN_LIMIT

func resolution_candidates() -> Array[Vector2i]:
	var usable := usable_rect().size
	var result: Array[Vector2i] = []
	for step in LADDER:
		if step.x <= usable.x and step.y <= usable.y:
			result.append(step)
	var native := native_resolution()
	if not result.has(native):
		result.append(native)
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a.x * a.y) < (b.x * b.y)
	)
	if result.is_empty():
		result.append(LADDER[0])
	return result

func default_resolution() -> Vector2i:
	var usable := usable_rect().size
	for i in range(LADDER.size() - 1, -1, -1):
		var step := LADDER[i]
		if step.x <= usable.x and step.y <= usable.y:
			return step
	var screen := screen_size()
	for i in range(LADDER.size() - 1, -1, -1):
		var step := LADDER[i]
		if step.x <= screen.x and step.y <= screen.y:
			return step
	return LADDER[0]

func settings_snapshot() -> Dictionary:
	return {
		"version": DOCUMENT_VERSION,
		"saved": saved,
		"fullscreen": fullscreen,
		"width": resolution.x,
		"height": resolution.y
	}

func validate_snapshot(document: Dictionary) -> String:
	if not document is Dictionary or document.size() != 5:
		var err := "Formato de vídeo inválido."
		_report_error(err)
		return err
	if not document.get("version") is int or int(document.version) != DOCUMENT_VERSION:
		var err := "Versão de vídeo inválida."
		_report_error(err)
		return err
	if not document.get("saved") is bool or not document.get("fullscreen") is bool:
		var err := "Campos de vídeo inválidos."
		_report_error(err)
		return err
	if not document.get("width") is int or not document.get("height") is int:
		var err := "Dimensões de vídeo inválidas."
		_report_error(err)
		return err
	var w := int(document.width)
	var h := int(document.height)
	var screen := screen_size()
	if w < MIN_WINDOW.x or h < MIN_WINDOW.y or w > screen.x or h > screen.y:
		var err := "Resolução fora dos limites da tela."
		_report_error(err)
		return err
	return ""

func apply_display(next_resolution: Vector2i, next_fullscreen: bool) -> void:
	if is_automated_run():
		return
	if next_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		var usable := usable_rect()
		var target := Vector2i(
			mini(next_resolution.x, usable.size.x),
			mini(next_resolution.y, usable.size.y)
		)
		target.x = maxi(target.x, MIN_WINDOW.x)
		target.y = maxi(target.y, MIN_WINDOW.y)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(target)
		DisplayServer.window_set_position(usable.position + (usable.size - target) / 2)

func apply_settings(next_resolution: Vector2i, next_fullscreen: bool) -> void:
	resolution = next_resolution
	fullscreen = next_fullscreen
	saved = true
	apply_display(next_resolution, next_fullscreen)
	last_error = ""
	settings_changed.emit(resolution, fullscreen)

func apply_snapshot(document: Dictionary) -> Error:
	var msg := validate_snapshot(document)
	if not msg.is_empty():
		return ERR_INVALID_DATA
	saved = bool(document.saved)
	fullscreen = bool(document.fullscreen)
	resolution = Vector2i(int(document.width), int(document.height))
	apply_display(resolution, fullscreen)
	last_error = ""
	settings_changed.emit(resolution, fullscreen)
	return OK

func reset_to_default() -> void:
	saved = false
	fullscreen = default_fullscreen()
	resolution = default_resolution()
	apply_display(resolution, fullscreen)
	settings_changed.emit(resolution, fullscreen)

func save_settings(path: String = SETTINGS_PATH) -> Error:
	var file := ConfigFile.new()
	file.set_value("display", "data", settings_snapshot())
	var temporary := path + ".tmp"
	var error := file.save(temporary)
	if error == OK:
		error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path))
	if error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		_report_error("Não foi possível salvar as configurações de vídeo: %s." % error_string(error))
	else:
		last_error = ""
	return error

func load_settings(path: String = SETTINGS_PATH) -> Error:
	if not FileAccess.file_exists(path):
		if not saved:
			fullscreen = default_fullscreen()
			resolution = default_resolution()
		return OK
	var file := ConfigFile.new()
	var error := file.load(path)
	if error != OK:
		_report_error("Arquivo de vídeo ilegível; configurações atuais preservadas.")
		return error
	var document: Variant = file.get_value("display", "data", null)
	if not document is Dictionary:
		_report_error("Arquivo de vídeo inválido; configurações atuais preservadas.")
		return ERR_INVALID_DATA
	var msg := validate_snapshot(document)
	if not msg.is_empty():
		return ERR_INVALID_DATA
	saved = bool(document.saved)
	fullscreen = bool(document.fullscreen)
	resolution = Vector2i(int(document.width), int(document.height))
	last_error = ""
	settings_changed.emit(resolution, fullscreen)
	return OK

func _report_error(message: String) -> void:
	last_error = message
	settings_error.emit(message)
