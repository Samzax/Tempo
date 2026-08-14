class_name Sector3CorePresentation
extends Node2D

## Apresentacao local do climax do upper S3. Nenhum dos elementos abaixo toca
## camera, limites ou fisica; todos pertencem a Room e desaparecem com ela.
signal offer_requested(offer: RewardOffer, player: Node)
signal sequence_completed

const P1 := preload("res://assets/backgrounds/sector3_upper/p1.png")
const P2 := preload("res://assets/backgrounds/sector3_upper/p2.png")
const P3 := preload("res://assets/backgrounds/sector3_upper/p3.png")
const STATES := preload("res://assets/world/sector3_upper/core_states.png")
const PROGRESS := preload("res://assets/world/sector3_upper/core_progress.png")
const RELEASE := preload("res://assets/world/sector3_upper/core_release.png")
const CORE_POSITION := Vector2(360.0, 108.0)
const INTERACTION_RADIUS := 70.0
const CHANNEL_STEPS := 12
const CHANNEL_STEP_DURATION := 0.083
const RELEASE_FRAMES := 10
const RELEASE_FRAME_DURATION := 0.05
const EJECTION_STEPS := 6
const EJECTION_STEP_DURATION := 0.08
const EJECTION_DISTANCE := 190.0

enum State { PROTECTED, ACTIVATABLE, CHANNELING, OFFER_PENDING, RELEASING, FINISHED }

var _state: State = State.PROTECTED
var _kills := 0
var _chest: RewardChest
var _player: Node2D
var _completed_on_entry := false
var _generation := 0
var _state_sprite: Sprite2D
var _progress_sprite: Sprite2D
var _release_sprite: Sprite2D
var _prompt: Label
var _planes: Array[Sprite2D] = []
var _plane_ejection_offsets := [0.0, 0.0, 0.0]
var _afterimages: Array[Node2D] = []
var _player_physics_was_active := false
var _player_collision_layer := 0
var _player_collision_mask := 0
var _player_hurtbox_layer := 0
var _player_hurtbox_mask := 0

func configure(chest: RewardChest, player: Node2D, completed_on_entry: bool = false) -> void:
	_chest = chest
	_player = player
	_completed_on_entry = completed_on_entry

func _ready() -> void:
	_build_planes()
	_build_core()
	_restore_completed_entry()
	set_process(true)

func _restore_completed_entry() -> void:
	if not _completed_on_entry:
		return
	var offer := _chest.current_offer() if is_instance_valid(_chest) else null
	if offer != null and not offer.claimed:
		_state = State.OFFER_PENDING
		_state_sprite.frame = 3
		_progress_sprite.hide()
		_prompt.hide()
		_chest.unlock_for_core()
		_chest.open_offer()
		return
	_state = State.FINISHED
	_state_sprite.hide()
	_progress_sprite.hide()
	_release_sprite.hide()
	_prompt.hide()

func _build_planes() -> void:
	for entry in [[P1, Vector2(360, 202.5), 0.07], [P2, Vector2(360, 202.5), 0.14], [P3, Vector2(360, 202.5), 0.24]]:
		var plane := Sprite2D.new()
		plane.texture = entry[0]
		plane.position = entry[1]
		plane.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		plane.z_index = -3 + _planes.size()
		plane.set_meta(&"drift", entry[2])
		add_child(plane)
		_planes.append(plane)

func _build_core() -> void:
	_state_sprite = _sprite(STATES, 5, 1, -1)
	_progress_sprite = _sprite(PROGRESS, 9, 1, 0)
	_release_sprite = _sprite(RELEASE, 5, 2, 2)
	_release_sprite.hide()
	_prompt = Label.new()
	_prompt.position = CORE_POSITION + Vector2(-42, 96)
	_prompt.size = Vector2(84, 18)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 10)
	_prompt.modulate = Color(1.0, 0.72, 0.62)
	_prompt.hide()
	add_child(_prompt)
	_refresh_core()

func _sprite(texture: Texture2D, columns: int, rows: int, z: int) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.hframes = columns
	sprite.vframes = rows
	sprite.position = CORE_POSITION
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.z_index = z
	add_child(sprite)
	return sprite

func _process(delta: float) -> void:
	var phase := Time.get_ticks_msec() * 0.001
	for index in _planes.size():
		var plane := _planes[index]
		plane.position.x = 360.0 + sin(phase * float(plane.get_meta(&"drift"))) * 3.0 + _plane_ejection_offsets[index]
		plane.position.y = 202.5 + cos(phase * float(plane.get_meta(&"drift")) * 0.7) * 2.0
	if _state == State.ACTIVATABLE:
		_prompt.text = "ATIVAR  [Enter]"
		_prompt.visible = _is_player_nearby()
	elif _state == State.OFFER_PENDING:
		_prompt.text = "ATIVAR  [Enter]"
		_prompt.visible = _is_player_nearby()

func record_enemy_resolved(reason: int) -> void:
	if _state != State.PROTECTED or reason != Enemy.ResolveReason.DIED:
		return
	_kills = mini(8, _kills + 1)
	_refresh_core()

func activate() -> void:
	if _state != State.PROTECTED:
		return
	_state = State.ACTIVATABLE
	_prompt.show()
	_refresh_core()

func _input(event: InputEvent) -> void:
	if (_state != State.ACTIVATABLE and _state != State.OFFER_PENDING) or not _is_player_nearby():
		return
	if event.is_action_pressed(&"interact") or (event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER)):
		if _state == State.ACTIVATABLE:
			_begin_channel()
		elif is_instance_valid(_chest):
			_chest.open_offer()
		get_viewport().set_input_as_handled()

func _is_player_nearby() -> bool:
	return is_instance_valid(_player) and _player.global_position.distance_to(CORE_POSITION) <= INTERACTION_RADIUS

func _begin_channel() -> void:
	if _state != State.ACTIVATABLE:
		return
	_state = State.CHANNELING
	_generation += 1
	var token := _generation
	_prompt.text = "CANAL"
	_prompt.show()
	for step in range(1, CHANNEL_STEPS + 1):
		# Os nove frames aprovados progridem de forma monotona ao longo dos 12
		# ticks; escala/modulacao mantem cada tick perceptivel sem asset novo.
		_progress_sprite.visible = true
		_progress_sprite.frame = mini(8, int(float(step) * 9.0 / CHANNEL_STEPS))
		_state_sprite.frame = 2 if step < CHANNEL_STEPS else 3
		_state_sprite.scale = Vector2.ONE * (1.0 + 0.012 * float(step % 3))
		_prompt.text = "CANAL  %02d/12" % step
		await get_tree().create_timer(CHANNEL_STEP_DURATION).timeout
		if not is_inside_tree() or token != _generation or _state != State.CHANNELING:
			return
	_state = State.OFFER_PENDING
	_prompt.hide()
	_progress_sprite.hide()
	_state_sprite.scale = Vector2.ONE
	_state_sprite.frame = 3
	if is_instance_valid(_chest):
		_chest.unlock_for_core()
		_chest.open_offer()

func offer_resolved(offer: RewardOffer) -> void:
	if _state != State.OFFER_PENDING or not is_instance_valid(_chest) or _chest.current_offer() != offer:
		return
	_state = State.RELEASING
	_generation += 1
	var token := _generation
	_state_sprite.hide()
	_progress_sprite.hide()
	_release_sprite.show()
	for frame in RELEASE_FRAMES:
		_release_sprite.frame = frame
		await get_tree().create_timer(RELEASE_FRAME_DURATION).timeout
		if not is_inside_tree() or token != _generation or _state != State.RELEASING:
			return
	await _run_ejection(token)
	if is_inside_tree() and token == _generation and _state == State.RELEASING:
		_state = State.FINISHED
		sequence_completed.emit()

func _run_ejection(token: int) -> void:
	_lock_player_for_ejection()
	var start := _player.global_position if is_instance_valid(_player) else Vector2.ZERO
	for step in range(1, EJECTION_STEPS + 1):
		if not is_inside_tree() or token != _generation or _state != State.RELEASING:
			_restore_player_after_ejection()
			return
		var progress := float(step) / EJECTION_STEPS
		if is_instance_valid(_player):
			_player.global_position = start + Vector2(EJECTION_DISTANCE * progress, sin(progress * PI) * 1.0)
			_spawn_afterimage()
		# P1/P2/P3 acumulam offsets diferenciais e _process os compoe ao drift.
		_plane_ejection_offsets[0] = -2.0 * progress
		_plane_ejection_offsets[1] = -8.0 * progress
		_plane_ejection_offsets[2] = -18.0 * progress
		await get_tree().create_timer(EJECTION_STEP_DURATION).timeout
	_restore_player_after_ejection()

func _lock_player_for_ejection() -> void:
	if not is_instance_valid(_player):
		return
	_player_physics_was_active = _player.is_physics_processing()
	_player.set_physics_process(false)
	var collision_player := _player as CollisionObject2D
	if collision_player != null:
		_player_collision_layer = collision_player.collision_layer
		_player_collision_mask = collision_player.collision_mask
		collision_player.collision_layer = 0
		collision_player.collision_mask = 0
	var hurtbox := _player.get_node_or_null("Hurtbox") as CollisionObject2D
	if hurtbox != null:
		_player_hurtbox_layer = hurtbox.collision_layer
		_player_hurtbox_mask = hurtbox.collision_mask
		hurtbox.collision_layer = 0
		hurtbox.collision_mask = 0

func _restore_player_after_ejection() -> void:
	if not is_instance_valid(_player):
		return
	_player.set_physics_process(_player_physics_was_active)
	var collision_player := _player as CollisionObject2D
	if collision_player != null:
		collision_player.collision_layer = _player_collision_layer
		collision_player.collision_mask = _player_collision_mask
	var hurtbox := _player.get_node_or_null("Hurtbox") as CollisionObject2D
	if hurtbox != null:
		hurtbox.collision_layer = _player_hurtbox_layer
		hurtbox.collision_mask = _player_hurtbox_mask

func _spawn_afterimage() -> void:
	if not is_instance_valid(_player):
		return
	var visual := _player.get_node_or_null("VisualRoot/AnimatedSprite2D") as AnimatedSprite2D
	if visual == null:
		return
	var afterimage := AnimatedSprite2D.new()
	afterimage.sprite_frames = visual.sprite_frames
	afterimage.animation = visual.animation
	afterimage.frame = visual.frame
	afterimage.global_position = _player.global_position - Vector2(16.0, 0.0)
	afterimage.rotation = _player.rotation
	afterimage.modulate = Color(1.0, 0.55, 0.45, 0.20)
	afterimage.z_index = 1
	add_child(afterimage)
	_afterimages.append(afterimage)

func _exit_tree() -> void:
	_generation += 1
	_restore_player_after_ejection()
	for afterimage in _afterimages:
		if is_instance_valid(afterimage):
			afterimage.queue_free()
	_afterimages.clear()

func _refresh_core() -> void:
	if not is_instance_valid(_state_sprite) or not is_instance_valid(_progress_sprite):
		return
	_progress_sprite.frame = _kills
	_progress_sprite.visible = _state == State.PROTECTED
	if _state == State.PROTECTED:
		_state_sprite.frame = 0 if _kills <= 2 else 1
	elif _state == State.ACTIVATABLE:
		_state_sprite.frame = 2
