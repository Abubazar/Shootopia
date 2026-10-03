extends MultiplayerSpawner

@export var network_player: PackedScene

func _ready() -> void:
	multiplayer.peer_connected.connect(spawn_player)
	
	
func spawn_player(id):
	if !multiplayer.is_server():return
	
	var player = network_player.instantiate()
	player.id_val = id
	player.setup_character()
	
	get_node(spawn_path).call_deferred("add_child",player)
