extends SceneTree

func _init():
	var scene = load("res://scenes/enemies/bosses/regente_dos_ecos.tscn")
	var boss = scene.instantiate()
	var root = Node2D.new()
	root.add_child(boss)
	boss.global_position = Vector2(100, 100)
	boss._facing = Vector2.DOWN
	boss._ready()
	boss._physics_process(0.016)
	var initial_mask_pos = boss.mask_pivot.global_position
	boss.global_position = Vector2(200, 100)
	boss._physics_process(0.0)
	var final_mask_pos = boss.mask_pivot.global_position
	print("Boss pos: ", boss.global_position)
	print("Mask pos: ", final_mask_pos)
	print("Detached distance: ", boss.global_position.distance_to(final_mask_pos))
	quit()
