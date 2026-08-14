class_name EnvironmentPresentation
extends Node2D

## Apresentacao local: o background global continua sendo o fallback e nunca e
## alterado por esta sala. A extensao aprovada ocupa a metade direita logica.
@export var environment_profile: StringName = &"default"

const UPPER_EXTENSION := preload("res://assets/backgrounds/phase_1_upper_space.png")

func _ready() -> void:
	if environment_profile == &"sector3_upper_core":
		return # O nucleo cria os tres planos locais, mantendo este fallback neutro.
	if environment_profile != &"upper_background_human_s2": return
	var extension := Sprite2D.new()
	extension.name = &"UpperSpaceExtension"
	extension.texture = UPPER_EXTENSION
	extension.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	extension.position = Vector2(360.0, 202.5)
	extension.scale = Vector2.ONE * 1.5
	add_child(extension)
