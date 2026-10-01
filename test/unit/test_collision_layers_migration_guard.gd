extends GutTest

## Guardas de migracao T4c: travam o contrato dos componentes Hitbox/Hurtbox
## sem tocar em cenas. Cobre caminho de no, polimorfismo Area2D e ausencia
## de shadow nas propriedades nativas de colisao.

func _area_class_of(area: Area2D) -> String:
	return area.get_class()

func _is_native_only_property(node: Object, property_name: StringName) -> bool:
	var usage := -1
	for entry in node.get_property_list():
		var prop := entry as Dictionary
		if prop.get("name", &"") == property_name:
			usage = int(prop.get("usage", 0))
			break
	if usage < 0:
		return false
	return (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0

func test_hurtbox_node_name_keeps_sector3_ejection_path_working() -> void:
	var root := Node2D.new()
	add_child_autofree(root)
	var hurtbox := Hurtbox.new()
	hurtbox.name = "Hurtbox"
	hurtbox.collision_layer = CollisionLayers.PLAYER
	hurtbox.collision_mask = CollisionLayers.ENEMY
	root.add_child(hurtbox)

	var found := root.get_node_or_null("Hurtbox") as CollisionObject2D
	assert_not_null(found)
	if found == null:
		return
	assert_true(found is Area2D)
	assert_eq(root.get_node_or_null("Hurtbox"), hurtbox)

	var saved_layer: int = found.collision_layer
	var saved_mask: int = found.collision_mask
	assert_eq(saved_layer, 2)
	assert_eq(saved_mask, 4)

	found.collision_layer = 0
	found.collision_mask = 0
	assert_eq(hurtbox.collision_layer, 0)
	assert_eq(hurtbox.collision_mask, 0)

	found.collision_layer = saved_layer
	found.collision_mask = saved_mask
	assert_eq(hurtbox.collision_layer, CollisionLayers.PLAYER)
	assert_eq(hurtbox.collision_mask, CollisionLayers.ENEMY)

	assert_null(root.get_node_or_null("HurtboxInexistente"))

func test_components_are_accepted_where_area2d_is_typed() -> void:
	var hurtbox := Hurtbox.new()
	var hitbox := Hitbox.new()
	add_child_autofree(hurtbox)
	add_child_autofree(hitbox)

	assert_true(hurtbox is Area2D)
	assert_true(hitbox is Area2D)
	assert_eq(hurtbox.get_class(), "Area2D")
	assert_eq(hitbox.get_class(), "Area2D")
	assert_eq(_area_class_of(hurtbox), "Area2D")
	assert_eq(_area_class_of(hitbox), "Area2D")

	var as_area: Area2D = hurtbox
	as_area.collision_layer = CollisionLayers.PICKUP
	as_area.collision_mask = CollisionLayers.ENEMY_BULLET
	assert_eq(hurtbox.collision_layer, 32)
	assert_eq(hurtbox.collision_mask, 16)

	# O parametro tipado Area2D de build_incoming_area_info aceita um Hitbox.
	var info := hurtbox.build_incoming_area_info(hitbox, 4)
	assert_not_null(info)
	assert_eq(info.amount, 4)
	assert_null(info.source)

func test_hurtbox_ready_keeps_authored_collision_properties_unshadowed() -> void:
	var hurtbox := Hurtbox.new()
	hurtbox.collision_layer = CollisionLayers.PICKUP
	hurtbox.collision_mask = CollisionLayers.ENEMY | CollisionLayers.ENEMY_BULLET
	hurtbox.monitoring = false
	hurtbox.monitorable = false
	add_child_autofree(hurtbox)
	await get_tree().process_frame

	assert_eq(hurtbox.collision_layer, 32)
	assert_eq(hurtbox.collision_mask, 20)
	assert_false(hurtbox.monitoring)
	assert_false(hurtbox.monitorable)

	hurtbox.collision_layer = CollisionLayers.PLAYER
	hurtbox.monitoring = true
	await get_tree().process_frame
	assert_eq(hurtbox.collision_layer, 2)
	assert_true(hurtbox.monitoring)

	assert_true(_is_native_only_property(hurtbox, &"collision_layer"))
	assert_true(_is_native_only_property(hurtbox, &"collision_mask"))
	assert_true(_is_native_only_property(hurtbox, &"monitoring"))
	assert_true(_is_native_only_property(hurtbox, &"monitorable"))
