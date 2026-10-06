class_name Network_manager
extends Node


@onready var canvas_layer: CanvasLayer = $"../CanvasLayer"
@onready var world: Node3D = $"../World"
@onready var host_players: ItemList = $"../CanvasLayer/home/lobby/current_players/PanelContainer/MarginContainer/VBoxContainer/host_players"
@onready var current_players: Control = $"../CanvasLayer/home/lobby/current_players"
@onready var line_edit: LineEdit = $"../CanvasLayer/home/lobby/play game/Control/HBoxContainer/LineEdit"


const PLAYER_SCENE = preload("res://Scenes/player.tscn")

const PORT := 7777
const MAX_PLAYERS := 10          # includes the host


var peer := ENetMultiplayerPeer.new()

# NOTE: multiplayer.is_server() is TRUE when no peer is set (offline mode),
# so we track our own state instead of relying on it for lobby logic.
var lobby_active := false        # we are hosting OR sitting in someone's lobby
var is_hosting := false          # public: use it to show/hide your "Start" button
var game_started := false

# peer_id -> username. Owned by the host, mirrored to every client.
var lobby_players: Dictionary = {}

# Label (created in code) that shows the host's IP in the players screen.
var ip_label: Label

# Text we put in the LineEdit to report problems. Cleared when the user clicks it.
const MSG_INVALID := "Invalid"
const MSG_FAILED := "Connection failed"


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

	# Pressing Enter in the IP box tries to join.
	line_edit.text_submitted.connect(_on_line_edit_submitted)
	# Clicking the box after an error message clears it.
	line_edit.focus_entered.connect(_on_line_edit_focus)

	# Label that sits above the player list and shows the host's IP.
	ip_label = Label.new()
	ip_label.visible = false
	var list_parent := host_players.get_parent()
	list_parent.add_child(ip_label)
	list_parent.move_child(ip_label, host_players.get_index())

	current_players.hide()


func _my_name() -> String:
	if str(Glob.username) == "":
		return "Player"
	return str(Glob.username)


# ============================================================
# LOCAL IP
# ============================================================

# Returns the most likely LAN IPv4 address of this machine.
func get_local_ip() -> String:
	var fallback := ""

	for ip in IP.get_local_addresses():
		var parts := ip.split(".")
		if parts.size() != 4:
			continue  # skip IPv6
		if ip.begins_with("127.") or ip.begins_with("169.254."):
			continue

		# Prefer typical home-network ranges.
		if ip.begins_with("192.168."):
			return ip
		if ip.begins_with("10."):
			fallback = ip if fallback == "" else fallback
		elif ip.begins_with("172."):
			var second := int(parts[1])
			if second >= 16 and second <= 31 and fallback == "":
				fallback = ip
		elif fallback == "":
			fallback = ip

	return fallback if fallback != "" else "127.0.0.1"


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

	# Show the lobby panel with the player list and the IP to share.
	ip_label.text = "Hosting on IP: %s" % get_local_ip()
	ip_label.visible = true
	current_players.show()
	refresh_lobby_list()

	print("Server started! Host ID: ", multiplayer.get_unique_id())


# ============================================================
# JOIN SERVER  (connect your "Join" button to join_from_input)
# ============================================================

# Reads the IP from the LineEdit, validates it, and connects.
func join_from_input() -> void:
	if lobby_active:
		return

	var ip := line_edit.text.strip_edges()

	if not ip.is_valid_ip_address():
		line_edit.text = MSG_INVALID
		return

	join_server(ip)


func _on_line_edit_submitted(_text: String) -> void:
	join_from_input()


func _on_line_edit_focus() -> void:
	if line_edit.text == MSG_INVALID or line_edit.text == MSG_FAILED:
		line_edit.text = ""


func join_server(ip: String, port: int = PORT) -> void:
	if lobby_active:
		return

	print("Joining server: ", ip, ":", port)

	peer = ENetMultiplayerPeer.new()
	var error := peer.create_client(ip, port)

	if error != OK:
		print("Failed to connect: ", error)
		line_edit.text = MSG_INVALID
		return

	multiplayer.multiplayer_peer = peer

	lobby_active = true
	is_hosting = false
	game_started = false


# ============================================================
# START GAME  (connect the host's "Start game" button to this)
# ============================================================

func start_game() -> void:
	if not is_hosting or game_started:
		return

	game_started = true

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

	ip_label.visible = false
	current_players.show()

	register_player.rpc_id(1, _my_name())


func _on_connection_failed() -> void:
	print("Failed to connect to server!")
	_return_to_menu()
	line_edit.text = MSG_FAILED


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

	peer.close()
	multiplayer.multiplayer_peer = null
	peer = ENetMultiplayerPeer.new()

	lobby_players.clear()
	host_players.clear()
	ip_label.visible = false

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
