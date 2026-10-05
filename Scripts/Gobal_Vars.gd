extends Node

var save_path = "user://data.save"

# All variables to save in memory
var character: int = 0
var username = "Player"
var sound = true
var sensitivity = 0.016




func save_data():
	var file = FileAccess.open(save_path,FileAccess.WRITE)
	file.store_var(character)
	file.store_var(username)
	file.store_var(sound)
	file.store_var(sensitivity)
	
	
func load_data():
	if FileAccess.file_exists(save_path):
		var file = FileAccess.open(save_path, FileAccess.READ)
		character = file.get_var()
		username = file.get_var()
		sound = file.get_var()
		sensitivity = file.get_var()
	else:
		print("E no dey")

func _ready() -> void:
	load_data()
