extends Node2D

var food_storage: int = 0
var wood_storage: int = 0


func deposit(resource_type: String, amount: int) -> void:
	if resource_type == "Food":
		food_storage += amount
		print("Nest: deposited ", amount, " Food. Total: ", food_storage)
	elif resource_type == "Wood":
		wood_storage += amount
		print("Nest: deposited ", amount, " Wood. Total: ", wood_storage)


func get_storage_summary() -> Dictionary:
	return {"Food": food_storage, "Wood": wood_storage}
