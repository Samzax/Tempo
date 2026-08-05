extends Node2D
## Ponto de entrada da cena principal.
## A montagem de mundo, jogador e diretores acontece nas tarefas seguintes.

@onready var _world: Node = $World
@onready var _session: Session = $Session
@onready var _hud: Control = $UI/HUD
@onready var _dev_sandbox: SandboxUI = $DevSandbox/Overlay
@onready var _main_menu: MainMenu = $MainMenu

var _gameplay_started := false

func _ready() -> void:
	_world.process_mode = Node.PROCESS_MODE_DISABLED
	_world.hide()
	_hud.hide()
	_dev_sandbox.set_enabled(false)
	_main_menu.start_game_requested.connect(_on_start_game_requested)

func _on_start_game_requested() -> void:
	if _gameplay_started:
		return
	_gameplay_started = true
	_world.show()
	_world.process_mode = Node.PROCESS_MODE_INHERIT
	_hud.show()
	_dev_sandbox.set_enabled(true)
	_session.start_new_run(RunManager.DEFAULT_SEED)
