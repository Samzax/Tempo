extends GutTest

func test_same_seed_same_sequence() -> void:
	var first := RunRng.new(42)
	var second := RunRng.new(42)

	for index in 10:
		assert_eq(first.randf(), second.randf())

func test_different_seeds_diverge() -> void:
	var first := RunRng.new(1)
	var second := RunRng.new(2)
	var first_sequence: Array[float] = []
	var second_sequence: Array[float] = []

	for index in 10:
		first_sequence.append(first.randf())
		second_sequence.append(second.randf())

	assert_ne(first_sequence, second_sequence)

func test_chance_bounds() -> void:
	var rng := RunRng.new(123)

	for index in 20:
		assert_false(rng.chance(0.0))
		assert_true(rng.chance(1.0))

func test_state_snapshot_resumes() -> void:
	var rng := RunRng.new(456)

	for index in 5:
		rng.randf()
	var captured_state := rng.get_state()
	var expected: Array[float] = []

	for index in 5:
		expected.append(rng.randf())

	rng.set_state(captured_state)
	for value in expected:
		assert_eq(rng.randf(), value)

func test_randi_range_within_bounds() -> void:
	var rng := RunRng.new(789)

	for index in 20:
		var value := rng.randi_range(1, 6)
		assert_true(value >= 1)
		assert_true(value <= 6)

func test_pick_empty() -> void:
	var rng := RunRng.new(101112)

	assert_eq(rng.pick([]), null)
