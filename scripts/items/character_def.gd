class_name CharacterDef
extends ProviderDef
## Define os dados de autoria de um personagem jogável.

@export var display_name: String
@export var description: String
@export var portrait: Texture2D
## Arte de destaque usada na selecao. Quando ausente, a UI usa o retrato legado.
@export var splash_art: Texture2D
@export var ability_e: StringName
@export var thrust_color: Color = Color.WHITE
## Cor de apresentacao dos glifos de habilidade. Pertence ao personagem, nunca ao casco.
const NEUTRAL_ABILITY_ICON_TINT := Color(0.933333, 0.945098, 0.964706, 1.0) # #EEF1F6

@export var ability_icon_tint: Color = NEUTRAL_ABILITY_ICON_TINT

const ROSTER_IDS: Array[StringName] = [&"hacker", &"guardian", &"chronomancer"]
const BASE_CHARACTER_PATH := "res://resources/characters/base.tres"

## Devolve os tres personagens selecionaveis, preferindo os recursos de conteudo
## quando estiverem disponiveis e mantendo definicoes funcionais enquanto isso.
static func get_roster() -> Array[CharacterDef]:
	var roster: Array[CharacterDef] = []
	for character_id in ROSTER_IDS:
		roster.append(_load_or_make(character_id))
	return roster

## Resolve um id selecionado para uma definicao jogavel. Entradas invalidas usam
## o piloto base existente como fallback seguro.
static func resolve_id(character_id: StringName) -> CharacterDef:
	for definition in get_roster():
		if definition.id == character_id:
			return definition
	return _base_fallback()

static func _load_or_make(character_id: StringName) -> CharacterDef:
	var content_path := "res://resources/characters/%s.tres" % character_id
	if ResourceLoader.exists(content_path):
		var authored := load(content_path) as CharacterDef
		if authored != null and authored.id == character_id and authored.validate_content().is_empty():
			return authored
	return _make_builtin(character_id)

static func _base_fallback() -> CharacterDef:
	var base := load(BASE_CHARACTER_PATH) as CharacterDef
	if base != null:
		return base
	return _make_builtin(&"guardian")

static func _make_builtin(character_id: StringName) -> CharacterDef:
	var definition := CharacterDef.new()
	definition.id = character_id
	match character_id:
		&"hacker":
			definition.display_name = "Hacker"
			definition.description = "Precisao adaptativa e sobrecarga de tiro."
			definition.ability_e = &"hacker_overdrive"
			definition.ability_icon_tint = Color(0.129412, 0.835294, 0.87451, 1.0) # #21D5DF
			definition.modifiers = [_modifier(&"aim_tier", 1.0)]
		&"guardian":
			definition.display_name = "Guardian"
			definition.description = "Resistencia reforcada e escudo de emergencia."
			definition.ability_e = &"guardian_shield"
			definition.ability_icon_tint = Color(0.72549, 0.521569, 0.839216, 1.0) # #B985D6
			definition.modifiers = [_modifier(&"max_health", 1.0)]
		&"chronomancer":
			definition.display_name = "Chronomancer"
			definition.description = "Manipula o tempo ao redor do blink."
			definition.ability_e = &"time_warp"
			definition.ability_icon_tint = Color(0.843137, 0.654902, 1.0, 1.0) # #D7A7FF
			definition.modifiers = [_modifier(&"blink_haste", 0.25)]
		_:
			return _base_fallback()
	return definition

static func _modifier(stat_id: StringName, value: float) -> StatModifierDef:
	var modifier := StatModifierDef.new()
	modifier.stat = stat_id
	modifier.op = StatDef.Op.FLAT
	modifier.value = value
	return modifier

## Devolve os erros de autoria encontrados neste personagem.
func validate_content() -> Array[String]:
	var errors := super()
	if not ability_e.is_empty() and not AbilityCatalog.is_valid(ability_e):
		errors.append("Habilidade do personagem desconhecida: %s." % ability_e)
	return errors
