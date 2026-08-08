extends Node2D
## Ponto de entrada da cena principal.
## A montagem de mundo, jogador e diretores acontece nas tarefas seguintes.

@onready var _world: Node = $World
@onready var _session: Session = $Session
@onready var _hud: Control = $UI/HUD
@onready var _item_choice: ItemChoice = $UI/ItemChoice
@onready var _hyperspace: HyperspaceUI = $Session/HyperspaceUI/Map
@onready var _pause_menu: PauseMenu = $PauseMenu
@onready var _dev_sandbox: SandboxUI = $DevSandbox/Overlay
@onready var _main_menu: MainMenu = $MainMenu

var _gameplay_started := false

func _ready() -> void:
	_world.process_mode = Node.PROCESS_MODE_DISABLED
	_world.hide()
	_hud.hide()
	_dev_sandbox.set_enabled(false)
	_main_menu.start_game_requested.connect(_on_start_game_requested)
	_pause_menu.resume_requested.connect(_on_pause_resume_requested)
	_pause_menu.back_to_title_requested.connect(_on_pause_back_to_title_requested)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo:
		return
	if not _gameplay_started or _pause_menu.visible or not event.is_action_pressed(&"ui_cancel"):
		return
	# Os overlays existentes consomem cancelamento antes da pausa; estes guards
	# tambem preservam a prioridade quando a chamada e exercitada diretamente.
	if _hyperspace.visible or _item_choice.visible or _dev_sandbox.visible:
		return
	_pause_menu.open()
	get_viewport().set_input_as_handled()

func _on_start_game_requested(ship_id: StringName, character_id: StringName) -> void:
	if _gameplay_started or not ShipCatalog.is_valid(ship_id):
		return
	var selected_ship := ShipCatalog.get_ship(ship_id)
	var player := _world.get_node_or_null("Player") as Player
	if selected_ship == null or player == null:
		return
	RunManager.select_character(character_id)
	if not player.configure_selection(selected_ship, RunManager.selected_character_id):
		return
	_reset_player_for_new_run(player)
	GameState.reset_for_new_run()
	_gameplay_started = true
	_world.show()
	_world.process_mode = Node.PROCESS_MODE_INHERIT
	_hud.show()
	_dev_sandbox.set_enabled(true)
	_session.start_new_run(RunManager.DEFAULT_SEED, RunManager.selected_character_id)

func _on_pause_resume_requested() -> void:
	_pause_menu.close()

func _on_pause_back_to_title_requested() -> void:
	_pause_menu.close()
	_session.reset_run()
	get_tree().paused = false
	_item_choice.hide()
	_clear_runtime_children($World/Projectiles)
	_clear_runtime_children($World/Effects)
	_gameplay_started = false
	_world.process_mode = Node.PROCESS_MODE_DISABLED
	_world.hide()
	_hud.hide()
	_reset_hud_for_new_run()
	_dev_sandbox.set_enabled(false)
	GameState.reset_for_new_run()
	_main_menu.reset_for_new_run()

func _clear_runtime_children(container: Node) -> void:
	for child in container.get_children():
		child.queue_free()

func _reset_player_for_new_run(player: Player) -> void:
	player.show()
	player.set_physics_process(true)
	player.velocity = Vector2.ZERO
	player.is_sandbox_invulnerable = false
	# configure_selection recompõe o loadout e o StatBlock; este reset defensivo
	# mantém o HP no máximo e impede que estado temporário da run anterior vaze.
	if is_instance_valid(player.health):
		player.health.reset()
	for property in [&"_fire_cooldown", &"_blink_cd", &"_blink_cd_duration", &"_ability_q_cd", &"_ability_q_cd_duration", &"_ability_e_cd", &"_ability_e_cd_duration", &"_invuln_timer"]:
		player.set(property, 0.0)

func _reset_hud_for_new_run() -> void:
	_hud.set(&"_over", false)
	var game_over: Variant = _hud.get(&"_game_over")
	if game_over is CanvasItem:
		game_over.hide()
