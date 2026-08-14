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
const AFTERIMAGE_STEP_INTERVAL := 2
const AFTERIMAGE_LIFETIME := 0.16
# Os spawns dos passos 2/4/6 ficam separados por 160 ms; cada rastro dura 160
# ms como eco legivel, ainda discreto (max. 1), sem sobreposicao visual nem "beam".
const MAX_AFTERIMAGES := 1

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
var _afterimage_tweens: Dictionary = {}
var _ejection_player: Node2D
var _ejection_hurtbox: CollisionObject2D
var _ejection_restore_pending := false
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
	_refresh_prompt()

func _refresh_prompt() -> void:
	if not is_instance_valid(_prompt):
		return
	if _state == State.ACTIVATABLE:
		_prompt.text = "ATIVAR  [Enter]"
		_prompt.visible = _is_player_nearby()
	elif _state == State.OFFER_PENDING and _is_player_nearby() and not _is_offer_ui_visible():
		_prompt.text = "OFERTA  [Enter]"
		_prompt.show()
	else:
		_prompt.hide()

func _is_offer_ui_visible() -> bool:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return false
	return _has_visible_offer_ui(tree.root)

func _has_visible_offer_ui(node: Node) -> bool:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return false
	if node is ItemChoice:
		var choice := node as Control
		if choice == null or not choice.is_visible_in_tree():
			return false
		var ancestor: Node = choice
		while ancestor != null:
			if ancestor is CanvasLayer and not (ancestor as CanvasLayer).visible:
				return false
			ancestor = ancestor.get_parent()
		return true
	for child in node.get_children():
		if _has_visible_offer_ui(child):
			return true
	return false

func record_enemy_resolved(reason: int) -> void:
	if _state != State.PROTECTED or reason != Enemy.ResolveReason.DIED:
		return
	_kills = mini(8, _kills + 1)
	_refresh_core()

func activate() -> void:
	if _state != State.PROTECTED:
		return
	_state = State.ACTIVATABLE
	_refresh_prompt()
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
	_refresh_prompt()
	_generation += 1
	var token := _generation
	for step in range(1, CHANNEL_STEPS + 1):
		# Os nove frames aprovados progridem de forma monotona ao longo dos 12
		# ticks; escala/modulacao mantem cada tick perceptivel sem asset novo.
		_progress_sprite.visible = true
		_progress_sprite.frame = mini(8, int(float(step) * 9.0 / CHANNEL_STEPS))
		_state_sprite.frame = 2 if step < CHANNEL_STEPS else 3
		_state_sprite.scale = Vector2.ONE * (1.0 + 0.012 * float(step % 3))
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
	_refresh_prompt()
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
	var ejection_player := _ejection_player
	var start := ejection_player.global_position if is_instance_valid(ejection_player) else Vector2.ZERO
	for step in range(1, EJECTION_STEPS + 1):
		if not is_inside_tree() or token != _generation or _state != State.RELEASING:
			_restore_player_after_ejection(ejection_player)
			return
		var progress := float(step) / EJECTION_STEPS
		if is_instance_valid(ejection_player):
			ejection_player.global_position = start + Vector2(EJECTION_DISTANCE * progress, sin(progress * PI) * 1.0)
			if step % AFTERIMAGE_STEP_INTERVAL == 0:
				_spawn_afterimage(ejection_player)
		# P1/P2/P3 acumulam offsets diferenciais e _process os compoe ao drift.
		_plane_ejection_offsets[0] = -2.0 * progress
		_plane_ejection_offsets[1] = -8.0 * progress
		_plane_ejection_offsets[2] = -18.0 * progress
		await get_tree().create_timer(EJECTION_STEP_DURATION).timeout
		if not is_inside_tree() or token != _generation or _state != State.RELEASING:
			_restore_player_after_ejection(ejection_player)
			return
	_restore_player_after_ejection(ejection_player)

func _lock_player_for_ejection() -> void:
	_restore_player_after_ejection()
	if not is_instance_valid(_player):
		return
	_ejection_player = _player
	_ejection_restore_pending = true
	_player_physics_was_active = _ejection_player.is_physics_processing()
	_ejection_player.set_physics_process(false)
	var collision_player := _ejection_player as CollisionObject2D
	if collision_player != null:
		_player_collision_layer = collision_player.collision_layer
		_player_collision_mask = collision_player.collision_mask
		collision_player.collision_layer = 0
		collision_player.collision_mask = 0
	_ejection_hurtbox = _ejection_player.get_node_or_null("Hurtbox") as CollisionObject2D
	if _ejection_hurtbox != null:
		_player_hurtbox_layer = _ejection_hurtbox.collision_layer
		_player_hurtbox_mask = _ejection_hurtbox.collision_mask
		_ejection_hurtbox.collision_layer = 0
		_ejection_hurtbox.collision_mask = 0

func _restore_player_after_ejection(expected_player: Node2D = null) -> void:
	# A primeira restauracao consome os caches. Assim, um timer que acorde depois
	# do teardown nao consegue alterar o player ja entregue a outra sala.
	if not _ejection_restore_pending:
		return
	var locked_player := _ejection_player
	if expected_player != null and locked_player != expected_player:
		return
	_ejection_restore_pending = false
	_ejection_player = null
	var locked_hurtbox := _ejection_hurtbox
	_ejection_hurtbox = null
	var physics_was_active := _player_physics_was_active
	var collision_layer := _player_collision_layer
	var collision_mask := _player_collision_mask
	var hurtbox_layer := _player_hurtbox_layer
	var hurtbox_mask := _player_hurtbox_mask
	_player_physics_was_active = false
	_player_collision_layer = 0
	_player_collision_mask = 0
	_player_hurtbox_layer = 0
	_player_hurtbox_mask = 0
	if not is_instance_valid(locked_player) or locked_player.is_queued_for_deletion():
		return
	locked_player.set_physics_process(physics_was_active)
	var collision_player := locked_player as CollisionObject2D
	if collision_player != null:
		collision_player.collision_layer = collision_layer
		collision_player.collision_mask = collision_mask
	if is_instance_valid(locked_hurtbox) and not locked_hurtbox.is_queued_for_deletion():
		locked_hurtbox.collision_layer = hurtbox_layer
		locked_hurtbox.collision_mask = hurtbox_mask

func _spawn_afterimage(source_player: Node2D = null) -> void:
	var player := source_player if source_player != null else _player
	if not is_instance_valid(player):
		return
	while _afterimages.size() >= MAX_AFTERIMAGES:
		var oldest: Node2D = _afterimages.front()
		if is_instance_valid(oldest):
			_discard_afterimage(oldest.get_instance_id())
		else:
			_afterimages.pop_front()
	var visual := player.get_node_or_null("VisualRoot/AnimatedSprite2D") as AnimatedSprite2D
	if visual == null:
		return
	var afterimage := AnimatedSprite2D.new()
	afterimage.sprite_frames = visual.sprite_frames
	afterimage.animation = visual.animation
	afterimage.frame = visual.frame
	afterimage.frame_progress = visual.frame_progress
	afterimage.centered = visual.centered
	afterimage.offset = visual.offset
	afterimage.flip_h = visual.flip_h
	afterimage.flip_v = visual.flip_v
	afterimage.texture_filter = visual.texture_filter
	afterimage.modulate = visual.modulate * Color(1.0, 1.0, 1.0, 0.45)
	afterimage.self_modulate = visual.self_modulate
	afterimage.z_index = visual.z_index
	afterimage.z_as_relative = visual.z_as_relative
	afterimage.show_behind_parent = visual.show_behind_parent
	add_child(afterimage)
	# O filho da sala nao pode herdar novamente o VisualRoot/player. Capturar a
	# transformacao global do sprite preserva escala, rotacao, skew e alinhamento.
	afterimage.global_transform = visual.global_transform
	_afterimages.append(afterimage)
	var afterimage_id := afterimage.get_instance_id()
	afterimage.tree_exiting.connect(_on_afterimage_tree_exiting.bind(afterimage_id), CONNECT_ONE_SHOT)
	_fade_afterimage(afterimage_id)

func _fade_afterimage(afterimage_id: int) -> void:
	var afterimage := instance_from_id(afterimage_id) as AnimatedSprite2D
	if not is_instance_valid(afterimage):
		return
	var tween := create_tween()
	_afterimage_tweens[afterimage_id] = tween
	tween.tween_property(afterimage, "modulate:a", 0.0, AFTERIMAGE_LIFETIME)
	tween.tween_callback(_expire_afterimage.bind(afterimage_id))

func _expire_afterimage(afterimage_id: int) -> void:
	_discard_afterimage(afterimage_id)

func _discard_afterimage(afterimage_id: int) -> void:
	if _afterimage_tweens.has(afterimage_id):
		var tween := _afterimage_tweens[afterimage_id] as Tween
		if is_instance_valid(tween):
			tween.kill()
		_afterimage_tweens.erase(afterimage_id)
	_remove_afterimage_reference(afterimage_id)
	var afterimage := instance_from_id(afterimage_id) as Node2D
	if is_instance_valid(afterimage):
		afterimage.hide()
		afterimage.queue_free()

func _on_afterimage_tree_exiting(afterimage_id: int) -> void:
	if _afterimage_tweens.has(afterimage_id):
		var tween := _afterimage_tweens[afterimage_id] as Tween
		if is_instance_valid(tween):
			tween.kill()
		_afterimage_tweens.erase(afterimage_id)
	_remove_afterimage_reference(afterimage_id)

func _remove_afterimage_reference(afterimage_id: int) -> void:
	for index in range(_afterimages.size() - 1, -1, -1):
		var afterimage: Node2D = _afterimages[index]
		if not is_instance_valid(afterimage) or afterimage.get_instance_id() == afterimage_id:
			_afterimages.remove_at(index)

func _exit_tree() -> void:
	_generation += 1
	_refresh_prompt()
	_restore_player_after_ejection()
	while not _afterimages.is_empty():
		var afterimage: Node2D = _afterimages.front()
		if is_instance_valid(afterimage):
			_discard_afterimage(afterimage.get_instance_id())
		else:
			_afterimages.pop_front()
	_afterimage_tweens.clear()

func _refresh_core() -> void:
	if not is_instance_valid(_state_sprite) or not is_instance_valid(_progress_sprite):
		return
	_progress_sprite.frame = _kills
	_progress_sprite.visible = _state == State.PROTECTED
	if _state == State.PROTECTED:
		_state_sprite.frame = 0 if _kills <= 2 else 1
	elif _state == State.ACTIVATABLE:
		_state_sprite.frame = 2
