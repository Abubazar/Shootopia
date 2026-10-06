class_name Network_manager
extends Node


@onready var canvas_layer: CanvasLayer = $"../CanvasLayer"
@onready var world: Node3D = $"../World"
@onready var lobbies: ItemList = $"../CanvasLayer/home/lobby/play game/GridContainer/VBoxContainer2/Control/lobbies"
@onready var host_players: ItemList = $"../CanvasLayer/home/lobby/current_players/PanelContainer/MarginContainer/VBoxContainer/host_players"
@onready var current_players: Control = $"../CanvasLayer/home/lobby/current_players"


const PLAYER_SCENE = preload("res://Scenes/player.tscn")

const PORT := 7777
const DISCOVERY_PORT := 7778
const MAX_PLAYERS := 10          # includes the host

const BROADCAST_INTERVAL := 1.0
const GAME_TIMEOUT := 3.0


var peer := ENetMultiplayerPeer.new()

# NOTE: multiplayer.is_server() is TRUE when no peer is set (offline mode),
# so we track our own state instead of relying on it for lobby logic.
var lobby_active := false        # we are hosting OR sitting in someone's lobby
var is_hosting := false          # public: use it to show/hide your "Start" button
var game_started := false

# peer_id -> username. Owned by the host, mirrored to every client.
var lobby_players: Dictionary = {}


# ============================================================
# DISCOVERY
# ============================================================

var discovery_listener := PacketPeerUDP.new()
var discovery_broadcaster := PacketPeerUDP.new()

var discovery_broadcasting := false
var broadcast_timer := 0.0

var discovered_games: Dictionary = {}


# ============================================================
# READY
# ============================================================

func _ready() -> void:
	# Connect once here (connecting inside create_server/join_server
	# would error with "already connected" the second time).
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	# Double-click (or Enter) on a lobby joins it.
	lobbies.item_activated.connect(_on_lobby_activated)

	current_players.hide()

	# Everyone starts listening for games immediately.
	start_discovery_listener()


func _my_name() -> String:
	if str(Glob.username) == "":
		return "Player"
	return str(Glob.username)


# ============================================================
# CREATE SERVER  (connect your "Host" button to this)
# ============================================================

func create_server() -> void:
	if lobby_active:
		return

	print("Creating server...")

	peer = ENetMultiplayerPeer.new()
	var error := peer.create_server(PORT, MAX_PLAYERS - 1)

	if error != OK:
		print("Failed to create server: ", error)
		return

	multiplayer.multiplayer_peer = peer

	lobby_active = true
	is_hosting = true
	game_started = false

	lobby_players = { 1: _my_name() }

	# Stop showing other lobbies, we're hosting now.
	discovered_games.clear()
	update_games([])

	# Show the lobby panel with the player list.
	current_players.show()
	refresh_lobby_list()

	start_game_broadcast()

	print("Server started! Host ID: ", multiplayer.get_unique_id())


# ============================================================
# JOIN SERVER  (called when you double-click a lobby)
# ============================================================

func join_server(ip: String = "127.0.0.1", port: int = PORT) -> void:
	if lobby_active:
		return

	print("Joining server: ", ip, ":", port)

	peer = ENetMultiplayerPeer.new()
	var error := peer.create_client(ip, port)

	if error != OK:
		print("Failed to connect: ", error)
		return

	multiplayer.multiplayer_peer = peer

	lobby_active = true
	is_hosting = false
	game_started = false


# Optional: connect a "Join" button to this to join the selected lobby.
func join_selected_lobby() -> void:
	var selected := lobbies.get_selected_items()
	if selected.is_empty():
		return
	_on_lobby_activated(selected[0])


func _on_lobby_activated(index: int) -> void:
	var game: Dictionary = lobbies.get_item_metadata(index)
	join_server(str(game["ip"]), int(game["port"]))


# ============================================================
# START GAME  (connect the host's "Start game" button to this)
# ============================================================

func start_game() -> void:
	if not is_hosting or game_started:
		return

	game_started = true
	stop_game_broadcast()

	# Everyone (host included) switches to the world and spawns all players.
	start_match.rpc(lobby_players.keys())


@rpc("authority", "call_local", "reliable")
func start_match(ids: Array) -> void:
	game_started = true

	current_players.hide()
	canvas_layer.hide()
	world.show()

	var index := 0
	for id in ids:
		_spawn_player(int(id), index)
		index += 1


# ============================================================
# CANCEL  (connect the "Cancel" button to this)
# Host: closes the lobby, clients get kicked back to the menu.
# Client: leaves the lobby.
# ============================================================

func cancel_lobby() -> void:
	_return_to_menu()
	lobby_active = false


# ============================================================
# LOBBY PLAYER LIST
# ============================================================

# Clients tell the host their name once they're connected.
@rpc("any_peer", "call_remote", "reliable")
func register_player(username: String) -> void:
	if not multiplayer.is_server() or game_started:
		return

	var id := multiplayer.get_remote_sender_id()
	lobby_players[id] = username
	_broadcast_lobby()


func _broadcast_lobby() -> void:
	sync_lobby.rpc(lobby_players)


# Host -> everyone (including itself): the current lobby contents.
@rpc("authority", "call_local", "reliable")
func sync_lobby(players: Dictionary) -> void:
	lobby_players = players
	refresh_lobby_list()


func refresh_lobby_list() -> void:
	host_players.clear()

	var my_id := multiplayer.get_unique_id()

	for id in lobby_players:
		var text: String = str(lobby_players[id])
		if id == 1:
			text += " (Host)"
		if id == my_id:
			text += " (You)"
		host_players.add_item(text)


# ============================================================
# CONNECTION EVENTS
# ============================================================

# Fires on the HOST when someone connects.
func _on_peer_connected(peer_id: int) -> void:
	print("Player connected: ", peer_id)

	if not lobby_active or not multiplayer.is_server():
		return

	# Lobby locked (game running) or full -> reject.
	if game_started or multiplayer.get_peers().size() + 1 > MAX_PLAYERS:
		peer.disconnect_peer(peer_id)
		return

	# Placeholder name until the client registers its real one.
	lobby_players[peer_id] = "Player " + str(peer_id)
	_broadcast_lobby()


# Fires on the HOST when someone leaves.
func _on_peer_disconnected(peer_id: int) -> void:
	print("Player disconnected: ", peer_id)

	if not lobby_active or not multiplayer.is_server():
		return

	lobby_players.erase(peer_id)

	if game_started:
		remove_player.rpc(peer_id)
	else:
		_broadcast_lobby()


# Fires on a CLIENT once it is connected to the host.
func _on_connected() -> void:
	print("Successfully connected! My peer ID: ", multiplayer.get_unique_id())

	discovered_games.clear()
	update_games([])

	current_players.show()

	register_player.rpc_id(1, _my_name())


func _on_connection_failed() -> void:
	print("Failed to connect to server!")
	_return_to_menu()


# Fires on a CLIENT when the host closes the lobby / drops.
func _on_server_disconnected() -> void:
	print("Host closed the game.")
	if not lobby_active:
		return
	_return_to_menu()


# Resets everything and goes back to the main menu.
func _return_to_menu() -> void:
	# Flip flags FIRST so the disconnect signals fired by close() are ignored.
	lobby_active = false
	is_hosting = false
	game_started = false

	stop_game_broadcast()

	peer.close()
	multiplayer.multiplayer_peer = null
	peer = ENetMultiplayerPeer.new()

	lobby_players.clear()
	discovered_games.clear()
	update_games([])
	host_players.clear()

	for child in world.get_children():
		if child.name.begins_with("Player_"):
			child.queue_free()

	current_players.hide()
	world.hide()
	canvas_layer.show()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


# ============================================================
# SPAWN / REMOVE PLAYER (local helpers, called from start_match)
# ============================================================

func _spawn_player(peer_id: int, index: int) -> void:
	var player_name := "Player_" + str(peer_id)

	if world.has_node(player_name):
		return

	var player = PLAYER_SCENE.instantiate()
	player.name = player_name
	player.set_multiplayer_authority(peer_id)

	# Same spawn point on every peer (based on join order) so players
	# don't stack at the origin.
	var spawns := world.get_node_or_null("spawn_points")
	if spawns and spawns.get_child_count() > 0:
		var marker: Node3D = spawns.get_child(index % spawns.get_child_count())
		player.position = marker.position

	world.add_child(player)

	# Needs to happen after add_child (uses @onready nodes).
	player.setName(str(lobby_players.get(peer_id, player_name)))

	print(
		"CREATED PLAYER | name = ", player.name,
		" | authority = ", player.get_multiplayer_authority(),
		" | MY ID = ", multiplayer.get_unique_id()
	)


@rpc("authority", "call_local", "reliable")
func remove_player(peer_id: int) -> void:
	var player_name := "Player_" + str(peer_id)

	if not world.has_node(player_name):
		return

	world.get_node(player_name).queue_free()
	print("Removed player: ", peer_id)


# ============================================================
# START DISCOVERY LISTENER
# ============================================================

func start_discovery_listener() -> void:
	var error := discovery_listener.bind(DISCOVERY_PORT)

	if error != OK:
		print("Failed to start discovery listener: ", error)
		return

	print("LAN discovery listening on port ", DISCOVERY_PORT)


# ============================================================
# START / STOP GAME BROADCASTING
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
		print("Failed to configure discovery broadcast: ", error)
		return

	discovery_broadcasting = true
	broadcast_timer = 0.0

	print("LAN game broadcasting started.")

	send_game_broadcast()


func stop_game_broadcast() -> void:
	if not discovery_broadcasting:
		return

	discovery_broadcasting = false
	discovery_broadcaster.close()


func send_game_broadcast() -> void:
	if not is_hosting or game_started:
		return

	var game_info := {
		"type": "LAN_GAME",
		"username": _my_name(),
		"players": lobby_players.size(),
		"max_players": MAX_PLAYERS,
		"port": PORT
	}

	discovery_broadcaster.put_packet(
		JSON.stringify(game_info).to_utf8_buffer()
	)


# ============================================================
# PROCESS DISCOVERY
# ============================================================

func process_discovery() -> void:
	while discovery_listener.get_available_packet_count() > 0:

		var packet := discovery_listener.get_packet()
		var sender_ip := discovery_listener.get_packet_ip()

		# Always drain packets, but ignore them while we're hosting
		# or already inside a lobby.
		if lobby_active:
			continue

		# Dual-stack sockets can report IPv4 as "::ffff:192.168.x.x".
		if sender_ip.begins_with("::ffff:"):
			sender_ip = sender_ip.substr(7)

		var data = JSON.parse_string(packet.get_string_from_utf8())

		if not data is Dictionary:
			continue

		if data.get("type", "") != "LAN_GAME":
			continue

		var game := {
			"ip": sender_ip,
			"username": str(data.get("username", "Unknown")),
			"players": int(data.get("players", 0)),
			"max_players": int(data.get("max_players", MAX_PLAYERS)),
			"port": int(data.get("port", PORT)),
			"last_seen": Time.get_ticks_msec()
		}

		# Refresh the list if it's new OR if its info changed (player count etc.)
		var old = discovered_games.get(sender_ip)
		var changed: bool = (
			old == null
			or old["username"] != game["username"]
			or old["players"] != game["players"]
			or old["max_players"] != game["max_players"]
			or old["port"] != game["port"]
		)

		discovered_games[sender_ip] = game

		if changed:
			print("LAN GAME UPDATED | ", sender_ip, " | ", game["username"])
			notify_games_changed()


# ============================================================
# REMOVE OLD GAMES
# ============================================================

func remove_old_games() -> void:
	var current_time := Time.get_ticks_msec()
	var changed := false

	for ip in discovered_games.keys():
		var game: Dictionary = discovered_games[ip]
		var age := current_time - int(game["last_seen"])

		if age > GAME_TIMEOUT * 1000.0:
			print("LAN GAME TIMED OUT: ", ip)
			discovered_games.erase(ip)
			changed = true

	if changed:
		notify_games_changed()


# ============================================================
# GAME LIST -> UI
# ============================================================

func notify_games_changed() -> void:
	update_games(discovered_games.values())


func update_games(list: Array) -> void:
	# Remember the selected lobby so a refresh doesn't deselect it.
	var selected_ip := ""
	var selected := lobbies.get_selected_items()
	if not selected.is_empty():
		var meta = lobbies.get_item_metadata(selected[0])
		if meta is Dictionary:
			selected_ip = str(meta["ip"])

	lobbies.clear()

	for game in list:
		var text := "%s    %d/%d" % [
			game["username"],
			game["players"],
			game["max_players"]
		]
		var index: int = lobbies.add_item(text)
		lobbies.set_item_metadata(index, game)

		if str(game["ip"]) == selected_ip:
			lobbies.select(index)


# ============================================================
# MAIN PROCESS
# ============================================================

func _process(delta: float) -> void:
	process_discovery()
	remove_old_games()

	if discovery_broadcasting:
		broadcast_timer += delta

		if broadcast_timer >= BROADCAST_INTERVAL:
			broadcast_timer = 0.0
			send_game_broadcast()
