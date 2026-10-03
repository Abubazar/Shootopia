extends Area3D

var health = 100
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	collision_layer = 3
	collision_mask = 3

@onready var player: CharacterBody3D = $"../../../../.."

func gotHit(area,damage,player_name):
	player.gotHit("headshot",damage,player_name)
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
