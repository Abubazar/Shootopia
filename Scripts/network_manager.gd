class_name Network_manager
extends Node


@onready var canvas_layer: CanvasLayer = $"../CanvasLayer"
@onready var world: Node3D = $"../World"
@onready var lobbies: ItemList = $"../CanvasLayer/home/lobby/play game/GridContainer/VBoxContainer2/Control/lobbies"


const PLAYER_SCENE = preload("res://Scenes/player.tscn")

const PORT := 7777
const DISCOVERY_PORT := 7778
const MAX_PLAYERS := 10

const BROADCAST_INTERVAL := 1.0
const GAME_TIMEOUT := 3.0


var peer := ENetMultiplayerPeer.new()

var connected_players: Array[int] = []


# ============================================================
# DISCOVERY
# ============================================================

var discovery_listener := PacketPeerUDP.new()
var discovery_broadcaster := PacketPeerUDP.new()

var discovery_broadcasting := false
var broadcast_timer := 0.0
#
var discovered_games: Dictionary = {}


# ============================================================
# READY
# ============================================================

func _ready() -> void:

	# Everyone starts listening for games immediately.
	start_discovery_listener()


# ============================================================
# CREATE SERVER
# ============================================================

func create_server() -> void:

	print("Creating server...")

	var error := peer.create_server(PORT)

	if error != OK:
		print("Failed to create server: ", error)
		return

	multiplayer.multiplayer_peer = peer

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	var host_id := multiplayer.get_unique_id()

	print("Server started!")
	print("Host ID: ", host_id)

	connected_players.append(host_id)

	# Create host player.
	spawn_player.rpc(host_id)

	canvas_layer.hide()
	world.show()

	# Start advertising this game.
	start_game_broadcast()


# ============================================================
# JOIN SERVER
# ============================================================

func join_server(ip: String = "127.0.0.1") -> void:

	print("Joining server: ", ip)

	var error := peer.create_client(ip, PORT)

	if error != OK:
		print("Failed to connect: ", error)
		return

	multiplayer.multiplayer_peer = peer

	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)

	canvas_layer.hide()
	world.show()


# ============================================================
# PLAYER CONNECTED
# ============================================================

func _on_peer_connected(peer_id: int) -> void:

	print("Player connected: ", peer_id)

	if not multiplayer.is_server():
		return

	if connected_players.has(peer_id):
		return

	connected_players.append(peer_id)

	# Tell everyone about the new player.
	spawn_player.rpc(peer_id)

	# Tell the new player about everyone
	# who was already in the game.
	for existing_id in connected_players:

		if existing_id == peer_id:
			continue

		spawn_player.rpc_id(peer_id, existing_id)


# ============================================================
# PLAYER DISCONNECTED
# ============================================================

func _on_peer_disconnected(peer_id: int) -> void:

	print("Player disconnected: ", peer_id)

	if not multiplayer.is_server():
		return

	connected_players.erase(peer_id)

	remove_player.rpc(peer_id)


# ============================================================
# SPAWN PLAYER
# ============================================================

@rpc("authority", "call_local", "reliable")
func spawn_player(peer_id: int) -> void:

	print(
		"SPAWNING PLAYER | peer_id = ",
		peer_id,
		" | MY ID = ",
		multiplayer.get_unique_id()
	)

	var player_name := "Player_" + str(peer_id)

	if world.has_node(player_name):

		print("Player already exists: ", player_name)

		return

	var player = PLAYER_SCENE.instantiate()

	player.name = player_name

	player.set_multiplayer_authority(peer_id)

	world.add_child(player)

	print(
		"CREATED PLAYER | name = ",
		player.name,
		" | authority = ",
		player.get_multiplayer_authority(),
		" | MY ID = ",
		multiplayer.get_unique_id()
	)


# ============================================================
# REMOVE PLAYER
# ============================================================

@rpc("authority", "call_local", "reliable")
func remove_player(peer_id: int) -> void:

	var player_name := "Player_" + str(peer_id)

	if not world.has_node(player_name):
		return

	var player := world.get_node(player_name)

	player.queue_free()

	print("Removed player: ", peer_id)


# ============================================================
# CONNECTED TO SERVER
# ============================================================

func _on_connected() -> void:

	print("Successfully connected to server!")

	print(
		"My peer ID: ",
		multiplayer.get_unique_id()
	)


# ============================================================
# CONNECTION FAILED
# ============================================================

func _on_connection_failed() -> void:

	print("Failed to connect to server!")


# ============================================================
# START DISCOVERY LISTENER
# ============================================================

func start_discovery_listener() -> void:

	var error := discovery_listener.bind(DISCOVERY_PORT)

	if error != OK:
		print(
			"Failed to start discovery listener: ",
			error
		)

		return

	print(
		"LAN discovery listening on port ",
		DISCOVERY_PORT
	)


# ============================================================
# START GAME BROADCASTING
# ============================================================

func start_game_broadcast() -> void:

	if discovery_broadcasting:
		return

	discovery_broadcaster.set_broadcast_enabled(true)

	var error := discovery_broadcaster.set_dest_address(
		"255.255.255.255",
		DISCOVERY_PORT
	)

	if error != OK:

		print(
			"Failed to configure discovery broadcast: ",
			error
		)

		return

	discovery_broadcasting = true
	broadcast_timer = 0.0

	print("LAN game broadcasting started.")

	# Send the first packet immediately.
	send_game_broadcast()


# ============================================================
# SEND GAME BROADCAST
# ============================================================

func send_game_broadcast() -> void:

	if not multiplayer.is_server():
		return

	var game_info := {
		"type": "LAN_GAME",
		"username": Glob.username,
		"players": connected_players.size(),
		"max_players": MAX_PLAYERS,
		"port": PORT
	}

	var message := JSON.stringify(game_info)

	discovery_broadcaster.put_packet(
		message.to_utf8_buffer()
	)

	print(
		"Discovery broadcast: ",
		message
	)


# ============================================================
# PROCESS DISCOVERY
# ============================================================

func process_discovery() -> void:

	while discovery_listener.get_available_packet_count() > 0:

		var packet := discovery_listener.get_packet()

		var message := packet.get_string_from_utf8()

		var sender_ip := discovery_listener.get_packet_ip()

		var data = JSON.parse_string(message)

		if data == null:
			continue

		if not data is Dictionary:
			continue

		if not data.has("type"):
			continue

		if data["type"] != "LAN_GAME":
			continue

		# Don't show our own game in our own server list.
		if multiplayer.is_server():
			continue

		var game := {
			"ip": sender_ip,
			"username": str(data.get("username", "Unknown")),
			"players": int(data.get("players", 0)),
			"max_players": int(data.get("max_players", MAX_PLAYERS)),
			"port": int(data.get("port", PORT)),
			"last_seen": Time.get_ticks_msec()
		}

		var was_new := not discovered_games.has(sender_ip)

		discovered_games[sender_ip] = game

		if was_new:

			print(
				"NEW LAN GAME FOUND | ",
				sender_ip,
				" | ",
				game["username"]
			)

			notify_games_changed()


# ============================================================
# REMOVE OLD GAMES
# ============================================================

func remove_old_games() -> void:

	var current_time := Time.get_ticks_msec()

	var changed := false

	for ip in discovered_games.keys():

		var game: Dictionary = discovered_games[ip]

		var age := (
			current_time - int(game["last_seen"])
		)

		if age > GAME_TIMEOUT * 1000.0:

			print(
				"LAN GAME TIMED OUT: ",
				ip
			)

			discovered_games.erase(ip)

			changed = true

	if changed:
		notify_games_changed()


# ============================================================
# NOTIFY GAME LIST
# ============================================================

func notify_games_changed() -> void:

	var games: Array = []

	for game in discovered_games.values():

		games.append(game)

	# This is the function your UI will use.
	update_games(games)


# ============================================================
# GAME LIST UPDATE
# ============================================================

func update_games(list: Array) -> void:
	lobbies.clear()
	for game in list:
		var text := "%s    %d/%d" % [
			game["username"],
			game["players"],
			game["max_players"]
		]
		var index = lobbies.add_item(text)
		# Store the entire game dictionary as metadata.
		lobbies.set_item_metadata(index, game)
	print("AVAILABLE GAMES: ", list)


# ============================================================
# GET GAME IP
# ============================================================

func get_game_ip(index: int) -> String:

	var games: Array = discovered_games.values()

	if index < 0 or index >= games.size():
		return ""

	return str(games[index]["ip"])


# ============================================================
# MAIN PROCESS
# ============================================================

func _process(delta: float) -> void:

	# Always listen for LAN games.
	process_discovery()

	# Remove games that stopped broadcasting.
	remove_old_games()

	# Host keeps advertising its game.
	if discovery_broadcasting:

		broadcast_timer += delta

		if broadcast_timer >= BROADCAST_INTERVAL:

			broadcast_timer = 0.0

			send_game_broadcast()
