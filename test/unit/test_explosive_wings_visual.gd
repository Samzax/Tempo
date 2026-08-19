extends GutTest

const CASULO_SCENE := preload("res://scenes/enemies/bosses/wings/casulo_explosivo.tscn")
const CASULO := preload("res://scripts/enemies/bosses/wings/casulo_explosivo.gd")
const CASULO_VISUAL := preload("res://scripts/enemies/bosses/wings/casulo_explosivo_visual.gd")
const GRID_CONTROLLER := preload("res://scripts/enemies/bosses/electric_grid_controller.gd")
const GRID_VISUAL := preload("res://scripts/enemies/bosses/electric_grid_visual.gd")

const ASSETS := [
	"res://assets/sprites/enemies/regente-dos-ecos/drones/regente-casulo-p2-f0.png",
	"res://assets/sprites/enemies/regente-dos-ecos/drones/regente-casulo-p2-f1.png",
	"res://assets/sprites/enemies/regente-dos-ecos/drones/regente-casulo-p2-f2.png",
	"res://assets/sprites/enemies/regente-dos-ecos/drones/regente-casulo-p2-f3.png",
	"res://assets/sprites/enemies/regente-dos-ecos/drones/regente-casulo-p2-spritesheet.png",
	"res://assets/sprites/enemies/regente-dos-ecos/drones/regente-drone-electric-aura.png",
	"res://assets/sprites/enemies/regente-dos-ecos/drones/regente-drone-electric-base.png",
	"res://assets/sprites/enemies/regente-dos-ecos/drones/regente-drone-electric-pulse.png",
]

func test_eight_visual_assets_load_with_expected_dimensions() -> void:
	var expected := [Vector2i(48, 48), Vector2i(48, 48), Vector2i(48, 48), Vector2i(48, 48), Vector2i(192, 48), Vector2i(32, 32), Vector2i(32, 32), Vector2i(32, 32)]
	for index in ASSETS.size():
		var texture := load(ASSETS[index]) as Texture2D
		assert_not_null(texture, ASSETS[index])
		assert_eq(Vector2i(texture.get_width(), texture.get_height()), expected[index], ASSETS[index])
	var casulo := CASULO_SCENE.instantiate()
	add_child_autofree(casulo)
	assert_not_null(casulo, "casulo_explosivo.tscn loads")

func test_casulo_scene_keeps_logic_root_and_visual_child() -> void:
	var root := CASULO_SCENE.instantiate()
	add_child_autofree(root)
	assert_true(root is CasuloExplosivo)
	assert_true(root.get_node("Visual") is CasuloExplosivoVisual)

func _make_casulo() -> Dictionary:
	var root := CASULO.new() as CasuloExplosivo
	add_child_autofree(root)
	assert_true(root.set_slot_id(1))
	var visual := CASULO_VISUAL.new() as CasuloExplosivoVisual
	root.add_child(visual)
	return {"root": root, "visual": visual}

func _present(root: CasuloExplosivo, visual: CasuloExplosivoVisual, delta := 0.0) -> Dictionary:
	visual._process(delta)
	return visual.runtime_snapshot()

func test_casulo_state_presentation_mapping_and_transition_holds() -> void:
	var fixture := _make_casulo()
	var root: CasuloExplosivo = fixture.root
	var visual: CasuloExplosivoVisual = fixture.visual
	assert_true(root.enter_slot())
	assert_eq(_present(root, visual).presentation, "idle")
	assert_eq(visual.texture.resource_path, "res://assets/sprites/enemies/regente-dos-ecos/drones/regente-casulo-p2-f0.png")
	assert_true(root.start_tracking(Vector2.ZERO))
	assert_eq(_present(root, visual).presentation, "tracking")
	assert_eq(visual.texture.resource_path, "res://assets/sprites/enemies/regente-dos-ecos/drones/regente-casulo-p2-f1.png")
	assert_true(root.lock_position(Vector2.ZERO))
	assert_eq(_present(root, visual).presentation, "tracking")
	assert_eq(_present(root, visual).state, CasuloExplosivo.State.LOCKED)
	assert_true(root.configure_damage(0, root, [], Vector2.ZERO))
	assert_eq(root.detonate([]), 0)
	assert_eq(root.state, CasuloExplosivo.State.EMPTY)
	var hold := _present(root, visual)
	assert_eq(hold.presentation, "detonate")
	assert_eq(visual.texture.resource_path, "res://assets/sprites/enemies/regente-dos-ecos/drones/regente-casulo-p2-f2.png")
	assert_true(hold.visible)
	assert_true(root.reset())
	var reset_hold := _present(root, visual)
	assert_eq(reset_hold.presentation, "detonate")
	assert_eq(visual.texture.resource_path, "res://assets/sprites/enemies/regente-dos-ecos/drones/regente-casulo-p2-f2.png")
	assert_eq(_present(root, visual, 0.16).presentation, "reset")
	assert_eq(visual.texture.resource_path, "res://assets/sprites/enemies/regente-dos-ecos/drones/regente-casulo-p2-f3.png")
	assert_true(_present(root, visual).visible)
	assert_eq(_present(root, visual, 0.12).presentation, "idle")
	assert_eq(visual.texture.resource_path, "res://assets/sprites/enemies/regente-dos-ecos/drones/regente-casulo-p2-f0.png")
	root.state = CasuloExplosivo.State.LOCKED
	assert_eq(root.detonate([]), 0)
	assert_eq(_present(root, visual, 0.16).presentation, "hidden")
	assert_true(root.reset())
	assert_eq(_present(root, visual).presentation, "reset")
	assert_eq(visual.texture.resource_path, "res://assets/sprites/enemies/regente-dos-ecos/drones/regente-casulo-p2-f3.png")
	root.destroy()
	assert_eq(_present(root, visual).presentation, "hidden")
	assert_false(visual.visible)

func test_casulo_visual_uses_parent_transform_for_local_position() -> void:
	var fixture := _make_casulo()
	var root: CasuloExplosivo = fixture.root
	var visual: CasuloExplosivoVisual = fixture.visual
	root.position = Vector2(100, 80)
	visual.position = Vector2(7, 9)
	_present(root, visual)
	assert_eq(visual.global_position, root.global_position + Vector2(7, 9))

func test_casulo_visual_without_controller_parent_is_hidden() -> void:
	var visual := CASULO_VISUAL.new() as CasuloExplosivoVisual
	add_child_autofree(visual)
	visual._process(0.0)
	assert_false(visual.visible)
	assert_false(visual.runtime_snapshot().parent_bound)

func test_casulo_visual_losing_logical_parent_clears_lifecycle_and_empty_rebind_is_hidden() -> void:
	var fixture := _make_casulo()
	var root: CasuloExplosivo = fixture.root
	var visual: CasuloExplosivoVisual = fixture.visual
	assert_true(root.enter_slot())
	assert_true(root.start_tracking(Vector2.ZERO))
	assert_true(root.lock_position(Vector2.ZERO))
	_present(root, visual)
	assert_true(root.configure_damage(0, root, [], Vector2.ZERO))
	assert_eq(root.detonate([]), 0)
	assert_eq(_present(root, visual).presentation, "detonate")
	root.remove_child(visual)
	_present(root, visual)
	var detached := visual.runtime_snapshot()
	assert_false(detached.visible)
	assert_eq(detached.state, -1)
	assert_eq(detached.hold_seconds, 0.0)
	assert_false(detached.reconstitution_pending)
	var empty_parent := CASULO.new() as CasuloExplosivo
	add_child_autofree(empty_parent)
	assert_true(empty_parent.set_slot_id(2))
	assert_true(empty_parent.enter_slot())
	empty_parent.state = CASULO.State.EMPTY
	empty_parent.add_child(visual)
	_present(empty_parent, visual)
	var rebound := visual.runtime_snapshot()
	assert_false(rebound.visible)
	assert_eq(rebound.presentation, "hidden")
	assert_eq(rebound.state, CASULO.State.EMPTY)
	assert_eq(rebound.hold_seconds, 0.0)
	assert_false(rebound.reconstitution_pending)

func test_casulo_visual_parent_queued_clears_lifecycle_immediately() -> void:
	var fixture := _make_casulo()
	var root: CasuloExplosivo = fixture.root
	var visual: CasuloExplosivoVisual = fixture.visual
	assert_true(root.enter_slot())
	assert_true(root.start_tracking(Vector2.ZERO))
	_present(root, visual)
	root.queue_free()
	_present(root, visual)
	var snapshot := visual.runtime_snapshot()
	assert_false(snapshot.visible)
	assert_eq(snapshot.state, -1)
	assert_eq(snapshot.hold_seconds, 0.0)
	assert_false(snapshot.reconstitution_pending)

func test_electric_visual_without_controller_is_safe_and_does_not_mutate() -> void:
	var visual := GRID_VISUAL.new() as ElectricGridVisual
	add_child_autofree(visual)
	var before_children := visual.get_child_count()
	var before_position := visual.position
	var before_scale := visual.scale
	visual._process(0.016)
	var snapshot := visual.runtime_snapshot()
	assert_false(snapshot.controller_bound)
	assert_eq(snapshot.drone_count, 0)
	assert_eq(snapshot.edge_count, 0)
	assert_eq(snapshot.subnet_count, 0)
	assert_eq(snapshot.visual_node_count, 0)
	assert_eq(visual.get_child_count(), before_children)
	assert_eq(visual.position, before_position)
	assert_eq(visual.scale, before_scale)
	assert_true(visual._snapshot.is_empty())
	assert_true(visual._drone_sprites.is_empty())

func test_electric_visual_renders_snapshot_without_mutating_controller() -> void:
	var controller := GRID_CONTROLLER.new() as ElectricGridController
	add_child_autofree(controller)
	assert_true(controller.configure_drones({1: {"position": Vector2.ZERO}, 2: {"position": Vector2(20, 0)}, 3: {"position": Vector2(100, 0)}}))
	var before: Dictionary = controller.active_snapshot()
	var visual := GRID_VISUAL.new() as ElectricGridVisual
	add_child_autofree(visual)
	visual.bind_controller(controller)
	visual._process(0.016)
	var rendered := visual.runtime_snapshot()
	assert_true(rendered.controller_bound)
	assert_eq(rendered.drone_count, 3)
	assert_gt(rendered.edge_count, 0)
	assert_gt(rendered.subnet_count, 0)
	assert_eq(rendered.visual_node_count, 3)
	assert_eq(visual.get_child_count(), 9)
	assert_true(rendered.base_texture_loaded)
	assert_true(rendered.pulse_texture_loaded)
	assert_true(rendered.aura_texture_loaded)
	assert_eq(controller.active_snapshot(), before)
	assert_true(controller.destroy_drone(2))
	visual._process(0.016)
	var after_destroy := visual.runtime_snapshot()
	assert_eq(after_destroy.drone_count, 2)
	assert_eq(after_destroy.visual_node_count, 2)
	assert_false(visual._drone_sprites.has(2))
	assert_eq(visual.get_child_count(), 9)
	var queued_count := 0
	for sprite_value in visual.get_children():
		if (sprite_value as Sprite2D).is_queued_for_deletion():
			queued_count += 1
	assert_eq(queued_count, 3)
	await get_tree().process_frame
	assert_eq(visual.get_child_count(), 6)
	assert_eq(controller.active_snapshot().drones.size(), 2)

func test_electric_visual_controller_queue_free_clears_snapshot_and_sprites_same_cycle() -> void:
	var controller := GRID_CONTROLLER.new() as ElectricGridController
	add_child_autofree(controller)
	assert_true(controller.configure_drones({1: {"position": Vector2.ZERO}, 2: {"position": Vector2(20, 0)}}))
	var before := controller.active_snapshot()
	var visual := GRID_VISUAL.new() as ElectricGridVisual
	add_child_autofree(visual)
	visual.bind_controller(controller)
	visual._process(0.016)
	assert_eq(visual.runtime_snapshot().visual_node_count, 2)
	controller.queue_free()
	visual._process(0.016)
	var cleared := visual.runtime_snapshot()
	assert_false(cleared.controller_bound)
	assert_eq(cleared.drone_count, 0)
	assert_eq(cleared.edge_count, 0)
	assert_eq(cleared.subnet_count, 0)
	assert_eq(cleared.visual_node_count, 0)
	assert_true(visual._snapshot.is_empty())
	assert_true(visual._drone_sprites.is_empty())
	assert_eq(visual.get_child_count(), 6)
	for child in visual.get_children():
		assert_true((child as Sprite2D).is_queued_for_deletion())
	assert_eq(controller.active_snapshot(), before)
	await get_tree().process_frame
	assert_eq(visual.get_child_count(), 0)
