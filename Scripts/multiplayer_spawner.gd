extends MultiplayerSpawner

const PLAYER_SCENE = preload("res://Scenes/player.tscn")


func _ready() -> void:
	spawn_path = NodePath("../Players")
	spawn_function = _spawn_player


func _spawn_player(peer_id):
	var player = PLAYER_SCENE.instantiate()

	player.name = "Player_" + str(peer_id)

	player.set_multiplayer_authority(peer_id)

	return player
