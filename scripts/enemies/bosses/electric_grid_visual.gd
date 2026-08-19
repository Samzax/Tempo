## Presentation-only renderer for the current ElectricGridController snapshot.
class_name ElectricGridVisual
extends Node2D

const BASE_TEXTURE := preload("res://assets/sprites/enemies/regente-dos-ecos/drones/regente-drone-electric-base.png")
const PULSE_TEXTURE := preload("res://assets/sprites/enemies/regente-dos-ecos/drones/regente-drone-electric-pulse.png")
const AURA_TEXTURE := preload("res://assets/sprites/enemies/regente-dos-ecos/drones/regente-drone-electric-aura.png")

var _controller: ElectricGridController
var _snapshot: Dictionary = {}
var _drone_sprites: Dictionary = {}
var _pulse_time := 0.0

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_find_sibling_controller()

## Explicit binding is preferred when this visual is instantiated by a scene.
func bind_controller(controller: ElectricGridController) -> void:
	_controller = controller

func _process(delta: float) -> void:
	if not _has_active_controller():
		_find_sibling_controller()
	if _has_active_controller():
		_snapshot = _controller.active_snapshot()
	else:
		_clear_visuals()
	_pulse_time += maxf(delta, 0.0)
	_sync_drones()
	queue_redraw()

func _find_sibling_controller() -> void:
	var parent := get_parent()
	if parent == null:
		return
	for child in parent.get_children():
		if child is ElectricGridController:
			var controller := child as ElectricGridController
			if not controller.is_queued_for_deletion():
				_controller = controller
				return

func _has_active_controller() -> bool:
	return is_instance_valid(_controller) and not _controller.is_queued_for_deletion()

func _clear_visuals() -> void:
	_snapshot = {}
	for sprites_value in _drone_sprites.values():
		_free_drone_sprites(sprites_value as Array)
	_drone_sprites.clear()

func _sync_drones() -> void:
	var alive: Dictionary = {}
	var drones: Array = _snapshot.get("drones", [])
	for drone_value in drones:
		if not drone_value is Dictionary:
			continue
		var drone: Dictionary = drone_value
		var raw_position: Variant = drone.get("position", null)
		if not raw_position is Vector2:
			continue
		var drone_id := int(drone.get("id", -1))
		if drone_id < 0:
			continue
		alive[drone_id] = true
		var sprites: Array = _drone_sprites.get(drone_id, [])
		if sprites.is_empty():
			sprites = _create_drone_sprites()
			_drone_sprites[drone_id] = sprites
		var local_position := _controller_position_to_local(raw_position)
		for sprite_value in sprites:
			var sprite := sprite_value as Sprite2D
			if sprite != null:
				sprite.position = local_position
				sprite.visible = true
		var pulse := sprites[2] as Sprite2D
		if pulse != null:
			var beat := 0.92 + sin(_pulse_time * 7.0 + float(drone_id)) * 0.08
			pulse.scale = Vector2.ONE * beat
			pulse.modulate.a = 0.65 + sin(_pulse_time * 7.0 + float(drone_id)) * 0.20
	var retired_drone_ids: Array = []
	for drone_id in _drone_sprites.keys():
		if alive.has(drone_id):
			continue
		retired_drone_ids.append(drone_id)
	for drone_id in retired_drone_ids:
		_free_drone_sprites(_drone_sprites[drone_id])
		_drone_sprites.erase(drone_id)

func _free_drone_sprites(sprites: Array) -> void:
	for sprite_value in sprites:
		var sprite := sprite_value as Sprite2D
		if is_instance_valid(sprite):
			sprite.visible = false
			sprite.queue_free()
	sprites.clear()

func _create_drone_sprites() -> Array:
	var aura := _make_sprite(AURA_TEXTURE, Color(0.60, 0.40, 1.0, 0.76))
	var base := _make_sprite(BASE_TEXTURE, Color.WHITE)
	var pulse := _make_sprite(PULSE_TEXTURE, Color(0.80, 0.92, 1.0, 0.82))
	return [aura, base, pulse]

func _make_sprite(next_texture: Texture2D, tint: Color) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = next_texture
	sprite.modulate = tint
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	return sprite

func _controller_position_to_local(controller_position: Vector2) -> Vector2:
	if not _has_active_controller():
		return controller_position
	return to_local(_controller.to_global(controller_position))

func _draw() -> void:
	if not _has_active_controller():
		return
	var drone_positions: Dictionary = {}
	for drone_value in _snapshot.get("drones", []):
		if drone_value is Dictionary and drone_value.get("position", null) is Vector2:
			drone_positions[int(drone_value.get("id", -1))] = _controller_position_to_local(drone_value.position)
	for subnet_value in _snapshot.get("subnets", []):
		if not subnet_value is Dictionary:
			continue
		for edge_value in subnet_value.get("edges", []):
			if not edge_value is Dictionary:
				continue
			var left_id := int(edge_value.get("a", -1))
			var right_id := int(edge_value.get("b", -1))
			if not drone_positions.has(left_id) or not drone_positions.has(right_id):
				continue
			_draw_electric_edge(drone_positions[left_id], drone_positions[right_id], left_id, right_id)

func _draw_electric_edge(start: Vector2, finish: Vector2, left_id: int, right_id: int) -> void:
	var direction := finish - start
	if direction.length_squared() <= 0.001:
		return
	var normal := direction.normalized().rotated(PI * 0.5)
	var points := PackedVector2Array([start])
	var seed := left_id * 31 + right_id * 17
	for index in range(1, 4):
		var fraction := float(index) / 4.0
		var offset := float((seed + index * 11) % 7 - 3) * 1.35
		points.append((start.lerp(finish, fraction) + normal * offset).round())
	points.append(finish)
	draw_polyline(points, Color(0.31, 0.10, 0.74, 0.42), 4.0, true)
	draw_polyline(points, Color(0.54, 0.84, 1.0, 0.95), 1.0, true)

func runtime_snapshot() -> Dictionary:
	var drone_count := 0
	for drone_value in _snapshot.get("drones", []):
		if drone_value is Dictionary:
			drone_count += 1
	var edge_count := 0
	var subnet_count := 0
	for subnet_value in _snapshot.get("subnets", []):
		if subnet_value is Dictionary:
			subnet_count += 1
			edge_count += (subnet_value.get("edges", []) as Array).size()
	return {
		"controller_bound": _has_active_controller(),
		"drone_count": drone_count,
		"edge_count": edge_count,
		"subnet_count": subnet_count,
		"visual_node_count": _drone_sprites.size(),
		"base_texture_loaded": BASE_TEXTURE != null,
		"pulse_texture_loaded": PULSE_TEXTURE != null,
		"aura_texture_loaded": AURA_TEXTURE != null,
	}
