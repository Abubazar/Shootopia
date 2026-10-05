extends Area3D

var health = 100
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	collision_layer = 3
	collision_mask = 3

@onready var player: CharacterBody3D = $"../../../../.."

@rpc("any_peer","reliable")
func gotHit(area,dmg,player_name):
	player.gotHit("headshot",dmg,player_name)
