extends GutTest

const EXPECTED_ITEM_IDS: Array[StringName] = [
	&"nucleo_superaquecido", &"casco_reforcado", &"recarga_fria", &"reator_instavel",
	&"lente_de_foco", &"maldicao_do_peso", &"convergencia", &"cronometro_perfeito",
	&"eco_temporal", &"frenesi", &"vinganca", &"sanguessuga", &"estilhaco",
]
const ALLOWED_POOLS: Array[StringName] = [&"treasure", &"risk", &"boss"]
const MODIFIER_ONLY_IDS: Array[StringName] = [
	&"nucleo_superaquecido", &"casco_reforcado", &"recarga_fria", &"reator_instavel",
	&"lente_de_foco", &"maldicao_do_peso", &"convergencia", &"cronometro_perfeito",
]
## Estes dados sao deliberadamente literais: nao podem derivar de ItemDef.modifiers,
## pois este teste e a auditoria independente do conteudo de autoria.
const EXPECTED_MODIFIERS: Dictionary = {
	&"nucleo_superaquecido": [
		{"stat": &"fire_rate", "op": StatDef.Op.ADD_PCT, "value": 0.3, "duration": -1.0, "condition": null, "priority": 0},
	],
	&"casco_reforcado": [
		{"stat": &"max_health", "op": StatDef.Op.FLAT, "value": 1.0, "duration": -1.0, "condition": null, "priority": 0},
	],
	&"recarga_fria": [
		{"stat": &"blink_haste", "op": StatDef.Op.ADD_PCT, "value": 0.3, "duration": -1.0, "condition": null, "priority": 0},
	],
	&"reator_instavel": [
		{"stat": &"damage", "op": StatDef.Op.ADD_PCT, "value": 0.5, "duration": -1.0, "condition": null, "priority": 0},
		{"stat": &"max_health", "op": StatDef.Op.FLAT, "value": -1.0, "duration": -1.0, "condition": null, "priority": 0},
	],
	&"lente_de_foco": [
		{"stat": &"damage", "op": StatDef.Op.ADD_PCT, "value": 0.4, "duration": -1.0, "condition": null, "priority": 0},
		{"stat": &"fire_rate", "op": StatDef.Op.ADD_PCT, "value": -0.2, "duration": -1.0, "condition": null, "priority": 0},
	],
	&"maldicao_do_peso": [
		{"stat": &"max_speed", "op": StatDef.Op.ADD_PCT, "value": -0.2, "duration": -1.0, "condition": null, "priority": 0},
	],
	&"convergencia": [
		{"stat": &"fire_rate", "op": StatDef.Op.MULT, "value": 1.0, "duration": -1.0, "condition": null, "priority": 0},
	],
	&"cronometro_perfeito": [
		{"stat": &"blink_haste", "op": StatDef.Op.OVERRIDE, "value": 5.0, "duration": -1.0, "condition": null, "priority": 0},
	],
}
const EXPECTED_METADATA: Dictionary = {
	&"nucleo_superaquecido": {"rarity": ItemDef.Rarity.COMMON, "max_stacks": 3, "pools": [&"treasure"], "tags": []},
	&"casco_reforcado": {"rarity": ItemDef.Rarity.COMMON, "max_stacks": 3, "pools": [&"treasure"], "tags": []},
	&"recarga_fria": {"rarity": ItemDef.Rarity.COMMON, "max_stacks": 3, "pools": [&"treasure"], "tags": [&"blink"]},
	&"reator_instavel": {"rarity": ItemDef.Rarity.RARE, "max_stacks": 3, "pools": [&"treasure"], "tags": []},
	&"lente_de_foco": {"rarity": ItemDef.Rarity.RARE, "max_stacks": 3, "pools": [&"treasure"], "tags": []},
	&"maldicao_do_peso": {"rarity": ItemDef.Rarity.RARE, "max_stacks": 3, "pools": [&"risk"], "tags": [&"curse"]},
	&"convergencia": {"rarity": ItemDef.Rarity.LEGENDARY, "max_stacks": 1, "pools": [&"boss"], "tags": []},
	&"cronometro_perfeito": {"rarity": ItemDef.Rarity.LEGENDARY, "max_stacks": 1, "pools": [&"boss"], "tags": [&"time"]},
	&"eco_temporal": {"rarity": ItemDef.Rarity.RARE, "max_stacks": 3, "pools": [&"treasure"], "tags": [&"blink", &"time"]},
	&"frenesi": {"rarity": ItemDef.Rarity.RARE, "max_stacks": 3, "pools": [&"treasure"], "tags": []},
	&"vinganca": {"rarity": ItemDef.Rarity.RARE, "max_stacks": 3, "pools": [&"treasure"], "tags": []},
	&"sanguessuga": {"rarity": ItemDef.Rarity.RARE, "max_stacks": 3, "pools": [&"treasure"], "tags": []},
	&"estilhaco": {"rarity": ItemDef.Rarity.RARE, "max_stacks": 3, "pools": [&"treasure"], "tags": [&"explosion"]},
}

class OwnerStub extends Node:
	var _stats: StatBlock


func before_each() -> void:
	## Efeitos usam RunManager.rng; uma seed fixa impede que testes futuros com chance
	## alterem esta auditoria de catalogo.
	RunManager.start_run(1)


func _new_stats() -> StatBlock:
	return StatBlock.new(StatCatalog.get_all())


func _new_inventory(stats: StatBlock, dispatcher: EffectDispatcher) -> Inventory:
	return Inventory.new(stats, dispatcher)


func _assert_item_valid(item: ItemDef) -> void:
	var errors := item.validate_content()
	if not errors.is_empty():
		fail_test("Item %s invalido: %s" % [item.id, "; ".join(errors)])
	assert_eq(errors.size(), 0, "Item %s deve passar validate_content()." % item.id)
	assert_false(item.display_name.strip_edges().is_empty(), "Item %s sem display_name." % item.id)
	assert_false(item.description.strip_edges().is_empty(), "Item %s sem description." % item.id)
	assert_true(item.rarity in [ItemDef.Rarity.COMMON, ItemDef.Rarity.RARE, ItemDef.Rarity.LEGENDARY], "Item %s tem rarity invalida." % item.id)
	assert_true(item.max_stacks >= 1, "Item %s precisa aceitar ao menos um stack." % item.id)
	assert_false(item.pools.is_empty(), "Item %s sem pool de autoria." % item.id)
	assert_true(EXPECTED_METADATA.has(item.id), "Item %s nao possui metadata esperada." % item.id)
	var expected: Dictionary = EXPECTED_METADATA[item.id]
	assert_eq(item.rarity, expected["rarity"], "Rarity incorreta para %s." % item.id)
	assert_eq(item.max_stacks, expected["max_stacks"], "max_stacks incorreto para %s." % item.id)
	assert_eq(item.pools, expected["pools"], "Pools incorretos para %s." % item.id)
	assert_eq(item.tags, expected["tags"], "Tags incorretas para %s." % item.id)
	for pool in item.pools:
		assert_true(pool in ALLOWED_POOLS, "Item %s usa pool nao permitida: %s." % [item.id, pool])
	for tag in item.tags:
		assert_true(TagCatalog.is_valid(tag), "Item %s usa tag invalida: %s." % [item.id, tag])


func _assert_modifier_multiset(actual_modifiers: Array, expected_modifiers: Array, message: String) -> void:
	assert_eq(actual_modifiers.size(), expected_modifiers.size(), "%s: quantidade de modifiers incorreta." % message)
	var matched: Array[bool] = []
	matched.resize(actual_modifiers.size())
	for expected in expected_modifiers:
		var found := false
		for actual_index in actual_modifiers.size():
			var actual: StatModifierDef = actual_modifiers[actual_index]
			if not matched[actual_index] and actual.stat == expected["stat"] and actual.op == expected["op"] and is_equal_approx(actual.value, expected["value"]) and is_equal_approx(actual.duration, expected["duration"]) and actual.condition == expected["condition"] and actual.priority == expected["priority"]:
				matched[actual_index] = true
				found = true
				break
		assert_true(found, "%s: modifier ausente ou diferente (%s, %s, %s, %s, %s, %s)." % [message, expected["stat"], expected["op"], expected["value"], expected["duration"], expected["condition"], expected["priority"]])


func _repeated_modifiers(modifiers: Array, stack_count: int) -> Array:
	var repeated: Array = []
	for _stack_index in range(stack_count):
		for modifier in modifiers:
			repeated.append(modifier)
	return repeated


func test_catalog_has_exactly_the_expected_unique_ids() -> void:
	var items := ItemCatalog.get_all()
	var ids: Array[StringName] = []
	for item in items:
		ids.append(item.id)

	assert_eq(items.size(), 13)
	assert_eq(ids.size(), EXPECTED_ITEM_IDS.size())
	var unique_ids := {}
	for item_id in ids:
		unique_ids[item_id] = true
	assert_eq(unique_ids.size(), ids.size(), "O catalogo nao pode conter IDs duplicados.")
	for item_id in EXPECTED_ITEM_IDS:
		assert_true(ids.has(item_id), "Catalogo sem o item esperado: %s." % item_id)
		assert_not_null(ItemCatalog.get_item(item_id), "get_item deve resolver %s." % item_id)
		assert_true(ItemCatalog.is_valid(item_id), "is_valid deve aceitar %s." % item_id)
	assert_false(ItemCatalog.is_valid(&"nao_existe"))


func test_all_catalog_items_are_structurally_valid() -> void:
	for item in ItemCatalog.get_all():
		_assert_item_valid(item)


func test_modifier_only_items_match_literal_canon_and_restore_base() -> void:
	for item_id in MODIFIER_ONLY_IDS:
		var item := ItemCatalog.get_item(item_id)
		var expected_modifiers: Array = EXPECTED_MODIFIERS[item_id]
		assert_true(item.effects.is_empty(), "Item %s baseado somente em modifiers nao pode declarar EffectDefs." % item.id)
		_assert_modifier_multiset(item.modifiers, expected_modifiers, "Resource de %s" % item.id)
		var stats := _new_stats()
		var dispatcher := EffectDispatcher.new(autofree(Node.new()), [])
		var inventory := _new_inventory(stats, dispatcher)
		var base_by_stat: Dictionary = {}
		for modifier in expected_modifiers:
			base_by_stat[modifier.stat] = stats.get_stat(modifier.stat)

		for stack_index in range(item.max_stacks):
			assert_true(inventory.acquire(item), "Item %s deve adquirir ate max_stacks." % item.id)
			assert_eq(inventory.count(item.id), stack_index + 1, "Item %s teve contagem incorreta." % item.id)
			_assert_modifier_multiset(stats.get_active_modifiers(), _repeated_modifiers(expected_modifiers, stack_index + 1), "Runtime de %s apos stack %d" % [item.id, stack_index + 1])
		assert_false(inventory.acquire(item), "Item %s deve recusar stack acima do limite." % item.id)
		for stat_id in base_by_stat:
			assert_ne(stats.get_stat(stat_id), base_by_stat[stat_id], "Item %s deve alterar %s com seus ModifierDefs." % [item.id, stat_id])

		for expected_count in range(item.max_stacks - 1, -1, -1):
			assert_true(inventory.remove_one(item.id), "Item %s deve remover uma instancia." % item.id)
			assert_eq(inventory.count(item.id), expected_count, "Item %s teve contagem incorreta apos remocao." % item.id)
			_assert_modifier_multiset(stats.get_active_modifiers(), _repeated_modifiers(expected_modifiers, expected_count), "Runtime de %s apos remocao" % item.id)
		assert_false(inventory.remove_one(item.id), "Item %s nao pode remover abaixo de zero." % item.id)
		assert_eq(stats.get_active_modifiers().size(), 0, "Item %s deixou modifiers apos remover todos os stacks." % item.id)
		for stat_id in base_by_stat:
			assert_almost_eq(stats.get_stat(stat_id), base_by_stat[stat_id], 0.0001, "Item %s deve restaurar %s ao valor base." % [item.id, stat_id])


func test_remove_one_uses_lifo_for_distinguishable_modifier_only_instances() -> void:
	var catalog_item := ItemCatalog.get_item(&"nucleo_superaquecido")
	var variant_a := catalog_item.duplicate(true) as ItemDef
	var variant_b := catalog_item.duplicate(true) as ItemDef
	assert_not_null(variant_a, "A variante A deve ser um clone profundo do ItemDef.")
	assert_not_null(variant_b, "A variante B deve ser um clone profundo do ItemDef.")
	if variant_a == null or variant_b == null:
		return
	assert_ne(variant_a, catalog_item, "A variante A nao pode ser o resource do catalogo.")
	assert_ne(variant_b, catalog_item, "A variante B nao pode ser o resource do catalogo.")
	assert_ne(variant_a.modifiers[0], catalog_item.modifiers[0], "A deve possuir modifier independente.")
	assert_ne(variant_b.modifiers[0], catalog_item.modifiers[0], "B deve possuir modifier independente.")
	assert_ne(variant_a.modifiers[0], variant_b.modifiers[0], "As variantes devem possuir modifiers independentes.")
	variant_a.modifiers[0].value = 0.2
	variant_b.modifiers[0].value = 0.4
	assert_almost_eq(catalog_item.modifiers[0].value, 0.3, 0.0001, "O resource do catalogo nao pode ser mutado pelas variantes.")

	var stats := _new_stats()
	var dispatcher := EffectDispatcher.new(autofree(Node.new()), [])
	var inventory := _new_inventory(stats, dispatcher)
	var expected_a: Array = [{"stat": &"fire_rate", "op": StatDef.Op.ADD_PCT, "value": 0.2, "duration": -1.0, "condition": null, "priority": 0}]
	var expected_b: Array = [{"stat": &"fire_rate", "op": StatDef.Op.ADD_PCT, "value": 0.4, "duration": -1.0, "condition": null, "priority": 0}]
	assert_true(inventory.acquire(variant_a), "Deve adquirir a variante A.")
	assert_true(inventory.acquire(variant_b), "Deve adquirir a variante B com o mesmo id.")
	assert_eq(inventory.count(catalog_item.id), 2, "A contagem deve ser dois antes da remocao.")
	_assert_modifier_multiset(stats.get_active_modifiers(), expected_a + expected_b, "Runtime com A e B")
	assert_true(inventory.remove_one(catalog_item.id), "Deve remover a instancia adquirida por ultimo.")
	assert_eq(inventory.count(catalog_item.id), 1, "A contagem deve cair de dois para um.")
	_assert_modifier_multiset(stats.get_active_modifiers(), expected_a, "Runtime apos remover B")


func _assert_dynamic_item(item_id: StringName, wrong_event: StringName, expected: Dictionary) -> void:
	var item := ItemCatalog.get_item(item_id)
	assert_true(item.modifiers.is_empty(), "Item %s baseado somente em effects nao pode declarar StatModifierDefs passivos." % item_id)
	assert_eq(item.effects.size(), 1, "Item %s deve ter um unico EffectDef dinamico." % item_id)
	if item.effects.size() != 1:
		return
	var effect: EffectDef = item.effects[0]
	assert_not_null(effect, "Item %s precisa declarar EffectDef." % item_id)
	if effect == null:
		return
	assert_null(effect.condition, "Item %s nao pode restringir seu EffectDef com ConditionDef." % item_id)
	assert_almost_eq(effect.cooldown, 0.0, 0.0001, "Item %s nao pode ter recarga oculta no EffectDef." % item_id)
	assert_eq(effect.event, expected["event"], "Item %s foi ligado ao evento incorreto." % item_id)
	assert_true(effect.action is ModifyStatAction, "Item %s precisa usar ModifyStatAction." % item_id)
	if not effect.action is ModifyStatAction:
		return
	var action := effect.action as ModifyStatAction
	assert_eq(effect.chance, expected["chance"], "Item %s precisa ter a chance canonica." % item_id)
	assert_eq(action.stat, expected["stat"], "Item %s tem stat canonica incorreta." % item_id)
	assert_eq(action.op, expected["op"], "Item %s tem operacao canonica incorreta." % item_id)
	assert_almost_eq(action.value, expected["value"], 0.0001, "Item %s tem valor canonico incorreto." % item_id)
	assert_almost_eq(action.duration, expected["duration"], 0.0001, "Item %s tem duracao canonica incorreta." % item_id)
	assert_eq(item.max_stacks, expected["max_stacks"], "Item %s tem max_stacks canonico incorreto." % item_id)
	var stub_owner := autofree(OwnerStub.new()) as OwnerStub
	stub_owner._stats = _new_stats()
	var dispatcher := EffectDispatcher.new(stub_owner, [])
	var inventory := _new_inventory(stub_owner._stats, dispatcher)
	var base := stub_owner._stats.get_stat(action.stat)

	assert_true(inventory.acquire(item), "Item %s deve adquirir o primeiro stack." % item_id)
	dispatcher.dispatch(wrong_event, null, 0)
	assert_almost_eq(stub_owner._stats.get_stat(action.stat), base, 0.0001, "Item %s nao pode reagir ao evento errado." % item_id)
	for _stack_index in range(1, item.max_stacks):
		assert_true(inventory.acquire(item), "Item %s deve adquirir stacks adicionais." % item_id)
	assert_eq(inventory.count(item_id), item.max_stacks)

	dispatcher.dispatch(expected["event"], null, 0)
	assert_eq(stub_owner._stats.get_active_modifiers().size(), item.max_stacks, "Item %s deve criar um buff temporario por EffectDef." % item_id)
	assert_ne(stub_owner._stats.get_stat(expected["stat"]), base, "Item %s deve alterar a stat apos acumular buffs." % item_id)
	for active in stub_owner._stats.get_active_modifiers():
		assert_eq(active.stat, expected["stat"], "Item %s aplicou buff na stat errada." % item_id)
		assert_eq(active.op, expected["op"], "Item %s aplicou buff com op errado." % item_id)
		assert_almost_eq(active.value, expected["value"], 0.0001, "Item %s aplicou valor canonico incorreto." % item_id)
		assert_almost_eq(active.duration, expected["duration"], 0.0001, "Item %s aplicou duracao canonica incorreta." % item_id)
	stub_owner._stats.tick(expected["duration"] + 0.1)
	assert_almost_eq(stub_owner._stats.get_stat(expected["stat"]), base, 0.0001, "Item %s deve expirar seus buffs temporarios." % item_id)

	for _stack_index in range(item.max_stacks):
		assert_true(inventory.remove_one(item_id), "Item %s deve remover todos os EffectDefs." % item_id)
	dispatcher.dispatch(expected["event"], null, 0)
	assert_almost_eq(stub_owner._stats.get_stat(expected["stat"]), base, 0.0001, "Item %s removido nao pode reagir a dispatch posterior." % item_id)
	assert_eq(stub_owner._stats.get_active_modifiers().size(), 0, "Item %s removido nao pode criar modifiers novos." % item_id)


func test_eco_temporal_dispatches_temporary_fire_rate_buff() -> void:
	_assert_dynamic_item(&"eco_temporal", &"on_kill", {
		"event": &"on_blink", "stat": &"fire_rate", "op": StatDef.Op.ADD_PCT,
		"value": 0.5, "duration": 2.0, "chance": 1.0, "max_stacks": 3,
	})


func test_frenesi_dispatches_temporary_fire_rate_buff() -> void:
	_assert_dynamic_item(&"frenesi", &"on_blink", {
		"event": &"on_kill", "stat": &"fire_rate", "op": StatDef.Op.ADD_PCT,
		"value": 0.1, "duration": 4.0, "chance": 1.0, "max_stacks": 3,
	})


func test_vinganca_dispatches_temporary_damage_buff() -> void:
	_assert_dynamic_item(&"vinganca", &"on_kill", {
		"event": &"on_damaged", "stat": &"damage", "op": StatDef.Op.ADD_PCT,
		"value": 0.25, "duration": 3.0, "chance": 1.0, "max_stacks": 3,
	})


func test_sanguessuga_and_estilhaco_catalog_wiring() -> void:
	var sanguessuga := ItemCatalog.get_item(&"sanguessuga")
	assert_true(sanguessuga.modifiers.is_empty(), "Sanguessuga baseada somente em effects nao pode declarar StatModifierDefs passivos.")
	assert_eq(sanguessuga.effects.size(), 1, "Sanguessuga deve ter exatamente um EffectDef.")
	if sanguessuga.effects.size() != 1:
		return
	var sanguessuga_effect: EffectDef = sanguessuga.effects[0]
	assert_not_null(sanguessuga_effect, "Sanguessuga precisa declarar EffectDef.")
	if sanguessuga_effect == null:
		return
	assert_null(sanguessuga_effect.condition, "Sanguessuga nao pode restringir seu EffectDef com ConditionDef.")
	assert_almost_eq(sanguessuga_effect.cooldown, 0.0, 0.0001, "Sanguessuga nao pode ter recarga oculta no EffectDef.")
	assert_eq(sanguessuga_effect.event, &"on_kill")
	assert_eq(sanguessuga_effect.chance, 1.0, "Sanguessuga precisa ter chance canonica.")
	assert_true(sanguessuga_effect.action is HealAction, "Sanguessuga precisa usar HealAction.")
	if not sanguessuga_effect.action is HealAction:
		return
	var heal_action := sanguessuga_effect.action as HealAction
	assert_almost_eq(heal_action.amount, 1.0, 0.0001, "Sanguessuga precisa curar o valor canonico.")

	var estilhaco := ItemCatalog.get_item(&"estilhaco")
	assert_true(estilhaco.modifiers.is_empty(), "Estilhaco baseado somente em effects nao pode declarar StatModifierDefs passivos.")
	assert_eq(estilhaco.effects.size(), 1, "Estilhaco deve ter exatamente um EffectDef.")
	if estilhaco.effects.size() != 1:
		return
	var estilhaco_effect: EffectDef = estilhaco.effects[0]
	assert_not_null(estilhaco_effect, "Estilhaco precisa declarar EffectDef.")
	if estilhaco_effect == null:
		return
	assert_null(estilhaco_effect.condition, "Estilhaco nao pode restringir seu EffectDef com ConditionDef.")
	assert_almost_eq(estilhaco_effect.cooldown, 0.0, 0.0001, "Estilhaco nao pode ter recarga oculta no EffectDef.")
	assert_eq(estilhaco_effect.event, &"on_kill")
	assert_eq(estilhaco_effect.chance, 1.0, "Estilhaco precisa ter chance canonica.")
	assert_true(estilhaco_effect.action is DamageAction, "Estilhaco precisa usar DamageAction.")
	if not estilhaco_effect.action is DamageAction:
		return
	var damage_action := estilhaco_effect.action as DamageAction
	assert_almost_eq(damage_action.amount, 1.0, 0.0001, "Estilhaco precisa causar o valor canonico.")
	assert_almost_eq(damage_action.radius, 48.0, 0.0001, "Estilhaco precisa ter o raio canonico.")
	assert_eq(damage_action.tags, [&"explosion"], "Estilhaco precisa usar exatamente a tag canonica.")
	assert_eq(damage_action.max_targets, 8, "Estilhaco precisa ter o limite canonico de alvos.")
