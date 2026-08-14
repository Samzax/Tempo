extends GutTest

const ROOM_DEF := preload("res://scripts/rooms/room_def.gd")
const SESSION := preload("res://scripts/run/session.gd")
const GENERATOR := preload("res://scripts/run/sector_generator.gd")

var _owned_nodes: Array[Node] = []

func _track_node(node: Node) -> Node:
	_owned_nodes.append(node)
	return node

func after_each() -> void:
	for node in _owned_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_owned_nodes.clear()
	await get_tree().process_frame
	await get_tree().process_frame

func test_sector3_treasure_has_private_profiles_and_preserves_dag() -> void:
	var session: Session = _track_node(SESSION.new()) as Session
	session.run_state = RunState.new()
	session.run_state.sector_index = 2
	var sector := GENERATOR.generate(4242, 2)
	var node23 := sector.get_node(23) as SectorNode
	var def := session._room_def_for(node23)
	assert_eq(node23.node_type, SectorNode.NodeType.TREASURE)
	assert_eq(def.encounter_profile, &"sector3_upper")
	assert_eq(def.environment_profile, &"sector3_upper_core")
	assert_eq(def.transition_profile, &"sector3_upper_transition")
	assert_eq(sector.get_children(23), [25])
	assert_eq(sector.get_children(25), [26])

func test_sector2_upper_keeps_legacy_profiles_and_single_wave() -> void:
	var session: Session = _track_node(SESSION.new()) as Session
	session.run_state = RunState.new()
	session.run_state.sector_index = 1
	var sector := GENERATOR.generate(4242, 1)
	var node13 := sector.get_node(13) as SectorNode
	var def := session._room_def_for(node13)
	assert_eq(def.encounter_profile, &"upper")
	assert_eq(def.environment_profile, &"upper_background_human_s2")
	assert_eq(def.transition_profile, &"default")
	assert_eq(def.wave_specs.size(), 1)
	assert_eq(def.wave_specs[0].max_active, 3)
	assert_eq(def.wave_specs[0].cadence, 1.1)

func test_sector3_wave_contract_is_four_moments_with_total_order() -> void:
	var def := ROOM_DEF.new()
	def.configure_sector3_upper_waves()
	assert_eq(def.wave_specs.size(), 4)
	var counts: Array[int] = []
	var active: Array[int] = []
	var order: Array[StringName] = []
	for wave in def.wave_specs:
		counts.append(wave.threat_types.size())
		active.append(wave.max_active)
		assert_eq(wave.cadence, 1.1)
		order.append_array(wave.threat_types)
	assert_eq(counts, [2, 1, 3, 2])
	assert_eq(active, [2, 1, 3, 2])
	assert_eq(order, [&"common", &"common", &"atirador", &"common", &"common", &"kamikaze", &"atirador", &"kamikaze"])

func test_sector3_assets_match_approved_sha256_and_dimensions() -> void:
	var expected := {
		"p1.png": [[756, 441], "1454ca132b592ac10d0418702dfbee55985e8225ec215871fdabf926340c579a"],
		"p2.png": [[756, 441], "721367b7d9976c784711d6de3b0d5e0371196e5483e42d7d5668f4560c311ed3"],
		"p3.png": [[756, 441], "081454edd6b87c280ee107430662f239126573f38d4830218053ce3f63e5fc64"],
		"core_states.png": [[880, 176], "e7c95f22b105f4b137579bd45dc5ffb0638db8c84f638b4ea0715f0b1aa59382"],
		"core_progress.png": [[1584, 176], "554f921a4c3fa73e9ac5694fd4d2843d8e4a8f73f0672d7d6005b62c9bc03dfb"],
		"core_release.png": [[1120, 384], "d6380dbeb3e5da21181aad38357174a3b4bdb4fd1f18ca2cfff253b90ad724db"]
	}
	for filename in expected:
		var path: String = ("res://assets/backgrounds/sector3_upper/" if filename.begins_with("p") else "res://assets/world/sector3_upper/") + filename
		var image := load(path) as Texture2D
		assert_not_null(image, path)
		assert_eq([image.get_width(), image.get_height()], expected[filename][0], path)
		assert_eq(FileAccess.get_sha256(path), expected[filename][1], path)

func test_sector3_import_sidecars_match_source_contract() -> void:
	var expected := {
		"res://assets/backgrounds/sector3_upper/p1.png.import": "res://assets/backgrounds/sector3_upper/p1.png",
		"res://assets/backgrounds/sector3_upper/p2.png.import": "res://assets/backgrounds/sector3_upper/p2.png",
		"res://assets/backgrounds/sector3_upper/p3.png.import": "res://assets/backgrounds/sector3_upper/p3.png",
		"res://assets/world/sector3_upper/core_states.png.import": "res://assets/world/sector3_upper/core_states.png",
		"res://assets/world/sector3_upper/core_progress.png.import": "res://assets/world/sector3_upper/core_progress.png",
		"res://assets/world/sector3_upper/core_release.png.import": "res://assets/world/sector3_upper/core_release.png"
	}
	for sidecar_path in expected:
		assert_true(FileAccess.file_exists(sidecar_path), sidecar_path)
		var text := FileAccess.get_file_as_string(sidecar_path)
		assert_false(text.contains("C:\\") or text.contains("C:/"), sidecar_path)
		assert_false(text.contains("user://") or text.contains(".harness"), sidecar_path)
		var config := ConfigFile.new()
		assert_eq(config.load(sidecar_path), OK, sidecar_path)
		assert_eq(config.get_value("remap", "importer", ""), "texture", sidecar_path)
		assert_eq(config.get_value("remap", "type", ""), "CompressedTexture2D", sidecar_path)
		assert_eq(config.get_value("deps", "source_file", ""), expected[sidecar_path], sidecar_path)
		assert_eq(config.get_value("params", "mipmaps/generate", null), false, sidecar_path)
		assert_ne(config.get_value("remap", "uid", ""), "", sidecar_path)
		assert_ne(config.get_value("remap", "path", ""), "", sidecar_path)
		assert_ne(config.get_value("deps", "dest_files", []), [], sidecar_path)
