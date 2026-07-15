class_name ResourceNode
extends StaticBody2D

signal depleted(node: Node2D)

@export var resource_type: String = "Food"
@export var remaining_amount: int = 100

@onready var sprite: Polygon2D = $Sprite
@onready var amount_label: Label = $AmountLabel

func _ready() -> void:
	_update_visual()

func extract(amount: int) -> int:
	var actual: int = mini(amount, remaining_amount)
	remaining_amount -= actual
	_update_visual()
	if remaining_amount <= 0:
		depleted.emit(self)
		queue_free()
	return actual

func _update_visual() -> void:
	if resource_type == "Food":
		sprite.color = Color(0.2, 0.7, 0.2, 1)
	else:
		sprite.color = Color(0.6, 0.4, 0.2, 1)
	amount_label.text = str(remaining_amount)
