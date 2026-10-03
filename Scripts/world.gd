extends Node3D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$Player2.mainPlayer = true
	$Player.setup_character()
	$Player2.setup_character()
	
	$Player2.setName("abubuub")
	$Player.setName("MOOORRRTTTYYYY")
	#pass

func _input(event):
	if event.is_action_pressed("esc"):
		get_tree().quit()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
