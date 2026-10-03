class_name Network_manager
extends Node

@onready var world: Node3D = $"../World"
@onready var canvas_layer: CanvasLayer = $"../CanvasLayer"

func create_serevr():
	var peer = ENetMultiplayerPeer.new()
	var res = peer.create_server(5000,10)
	multiplayer.multiplayer_peer = peer
	
	multiplayer.peer_connected.connect(
		func(peer_id):
			print(peer_id)
			world.visible = true
			canvas_layer.visible = false
			
	)

func join_server():
	var peer = ENetMultiplayerPeer.new()
	var res = peer.create_client("localhost",5000)
	multiplayer.peer_connected.connect(
		func(peer_id):
			print(peer_id)
			world.visible = true
			canvas_layer.visible = false
	)







# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
