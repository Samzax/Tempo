extends GutTest

func test_catalog_loads_without_errors() -> void:
	var definitions := StatCatalog.get_all()
	assert_not_null(definitions)
	assert_eq(definitions.size(), 20)
	assert_eq(StatCatalog.get_stat(&"max_speed").default_base, 150.0)
